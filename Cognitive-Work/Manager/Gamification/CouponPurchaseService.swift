//
//  CouponPurchaseService.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 16/10/26.
//

import Foundation
import CloudKit

/// Buys a chore's coupon with coins, safely under concurrency.
///
/// Rules checked on the server's current values:
/// - the coupon is on sale and has no holder for the latest cycle (one holder per coupon);
/// - the buyer holds no other coupon of the same room in this cycle (one per room); a coupon a
///   division already used doesn't count;
/// - the buyer's wallet covers the price (the balance never goes negative).
///
/// The coupon, the buyer's ``CoinWalletModel`` and their ``CouponHoldModel`` for the room are
/// saved in **one** atomic, change-tag-checked request (see ``AtomicRecordStore``):
/// - two buyers of the same coupon both fetched the same coupon version, so the second save
///   conflicts and writes nothing — not even the debit;
/// - two purchases in the same room by the same person both write the same hold record;
/// - any concurrent debit or credit changes the wallet's version.
/// On a conflict the purchase starts over from fresh data, so the loser gets the real reason
/// (e.g. ``PurchaseError/alreadyTaken``) instead of a generic failure.
@MainActor
final class CouponPurchaseService {

    /// Why a purchase failed.
    enum PurchaseError: Error, Equatable {
        /// The coupon no longer exists.
        case couponNotFound
        /// The coupon is not for sale.
        case notOnSale
        /// Someone already holds this coupon in the current cycle.
        case alreadyTaken
        /// The buyer already bought a coupon in this room in the current cycle.
        case roomLimitReached
        /// The buyer doesn't have enough coins. Carries their balance and the price.
        case insufficientCoins(balance: Int, price: Int)
        /// The coupon's chore, or its room, no longer exists.
        case choreNotFound
        /// The house has no cycle yet: a division must be generated first.
        case noActiveCycle
        /// The coupon or wallet kept changing while buying, and the purchase gave up.
        case tooManyConflicts
    }

    /// What a successful purchase cost.
    struct Receipt: Equatable {
        /// Coins paid.
        let price: Int
        /// The buyer's balance after paying.
        let newBalance: Int
    }

    /// Where records are read and saved (CloudKit in the app, in memory in tests).
    private let store: AtomicRecordStore
    /// How coupon prices are calculated.
    private let pricing: CouponPricing
    /// How many times a purchase is retried when another device changed the records at the same time.
    private let maxAttempts: Int

    /// - Parameters:
    ///   - store: Defaults to ``CloudKitAtomicRecordStore``.
    ///   - pricing: Defaults to ``CouponPricing/current``.
    ///
    /// The defaults are resolved in the body: default argument expressions are evaluated outside
    /// the main actor, where those main-actor values can't be created.
    init(
        store: AtomicRecordStore? = nil,
        pricing: CouponPricing? = nil,
        maxAttempts: Int = 5
    ) {
        self.store = store ?? CloudKitAtomicRecordStore()
        self.pricing = pricing ?? .current
        self.maxAttempts = maxAttempts
    }

    /// Buys `couponID` for `buyerID` in the cycle `cycleKey`.
    ///
    /// - Parameters:
    ///   - buyerID: The buyer's in-house ``UserModel`` record.
    ///   - houseID: Parent of the records this creates.
    ///   - cycleKey: Key of the latest ``HouseCycleModel``; `nil` fails with `.noActiveCycle`.
    ///   - legacyCoins: Seeds the wallet if the buyer has none yet (``UserModel/coins``).
    func purchase(
        couponID: CKRecord.ID,
        buyerID: CKRecord.ID,
        houseID: CKRecord.ID,
        cycleKey: String?,
        legacyCoins: Int = 0
    ) async throws -> Receipt {
        guard let cycleKey else { throw PurchaseError.noActiveCycle }

        let walletID = CoinWalletModel.recordID(for: buyerID)
        let buyerReference = CKRecord.Reference(recordID: buyerID, action: .none)

        for _ in 0..<maxAttempts {
            // 1. Coupon and wallet.
            let fetched = try await store.fetch([couponID, walletID])
            guard let couponRecord = fetched[couponID],
                  var coupon = CouponModel(record: couponRecord)
            else { throw PurchaseError.couponNotFound }

            guard coupon.isOnSale else { throw PurchaseError.notOnSale }
            guard coupon.isAvailable(latestCycleKey: cycleKey) else { throw PurchaseError.alreadyTaken }

            // 2. The chore gives the price and the room.
            guard let choreID = coupon.task?.recordID,
                  let choreRecord = try await store.fetch([choreID])[choreID],
                  let chore = ChoreModel(record: choreRecord),
                  let roomID = chore.roomReference?.recordID
            else { throw PurchaseError.choreNotFound }

            // 3. One coupon per room per cycle.
            let holdID = CouponHoldModel.recordID(userID: buyerID, roomID: roomID)
            let existingHold = try await store.fetch([holdID])[holdID]
            // The hold only counts while its coupon is still the buyer's and unused.
            if let existingHold,
               let hold = CouponHoldModel(record: existingHold),
               hold.cycleKey == cycleKey {
                let heldID = hold.coupon.recordID
                let held: CouponModel?
                if heldID == couponID {
                    held = coupon
                } else {
                    held = try await store.fetch([heldID])[heldID].flatMap(CouponModel.init(record:))
                }
                if held?.isHeld(by: buyerID, inCycle: cycleKey) == true {
                    throw PurchaseError.roomLimitReached
                }
            }

            // 4. Funds.
            let price = pricing.price(for: chore)
            let wallet = CoinWalletModel.record(for: buyerID, in: fetched, houseID: houseID, legacyCoins: legacyCoins)
            guard wallet.balance >= price else {
                throw PurchaseError.insufficientCoins(balance: wallet.balance, price: price)
            }

            // 5. Changes, saved together.
            coupon.lastUser = coupon.currentUser
            coupon.currentUser = buyerReference
            coupon.purchasedCycleKey = cycleKey
            coupon.consumedCycleKey = nil
            coupon.price = price
            coupon.populate(record: couponRecord)

            let newBalance = wallet.balance - price
            wallet.record["balance"] = newBalance

            let holdRecord = existingHold ?? {
                let record = CKRecord(recordType: CouponHoldModel.recordType, recordID: holdID)
                record.parent = CKRecord.Reference(recordID: houseID, action: .none)
                return record
            }()
            CouponHoldModel(
                user: buyerReference,
                room: CKRecord.Reference(recordID: roomID, action: .none),
                coupon: CKRecord.Reference(recordID: couponID, action: .none),
                cycleKey: cycleKey
            ).populate(record: holdRecord)

            do {
                try await store.saveAtomically([couponRecord, wallet.record, holdRecord])
                return Receipt(price: price, newBalance: newBalance)
            } catch AtomicRecordStoreError.conflict {
                continue
            }
        }

        throw PurchaseError.tooManyConflicts
    }
}

extension CouponPurchaseService.PurchaseError {

    /// Message shown to the user.
    var userMessage: String {
        switch self {
        case .couponNotFound, .choreNotFound:
            return L10n.tr("Esse cupom não existe mais.")
        case .notOnSale:
            return L10n.tr("Esse cupom não está à venda.")
        case .alreadyTaken:
            return L10n.tr("Alguém já comprou esse cupom neste ciclo.")
        case .roomLimitReached:
            return L10n.tr("Você já tem um cupom desse cômodo neste ciclo.")
        case .insufficientCoins:
            return L10n.tr("Moedas insuficientes")
        case .noActiveCycle:
            return L10n.tr("Gere a divisão de tarefas para começar um ciclo antes de comprar cupons.")
        case .tooManyConflicts:
            return L10n.tr("Não foi possível concluir a compra. Tente de novo.")
        }
    }
}
