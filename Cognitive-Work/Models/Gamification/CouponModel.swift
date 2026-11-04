//
//  Coupon.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 27/08/26.
//

import Foundation
import CloudKit

/// A coupon that spares its holder from one chore in the next division.
///
/// Every chore has one coupon (see the extension below). A member buys it with coins in the
/// rewards tab; the next division gives that chore to someone else. Once the division used it,
/// anyone can buy it again.
struct CouponModel: CloudKitSyncable {
    /// The CloudKit record type.
    static var recordType: String = "CouponModel"
    
    /// The CloudKit record ID. `nil` until the model is saved.
    var recordID: CKRecord.ID?
    
    /// The coupon's name (the chore's name).
    var name: String
    /// Whether the coupon can be bought at all.
    var isOnSale: Bool
    /// Price in coins (see ``CouponPricing``).
    var price: Int
    /// The coupon's rank, from how hard the chore is (see ``tier(forScore:)``).
    var tier: Tier
    /// The member who bought the coupon most recently. `nil` if nobody bought it yet.
    var currentUser: CKRecord.Reference?
    /// The member who held the coupon before ``currentUser``.
    var lastUser: CKRecord.Reference?
    /// The chore the coupon is for. Deleting the chore deletes the coupon.
    var task: CKRecord.Reference?
    
    /// Key of the ``HouseCycleModel`` in which ``currentUser`` bought the coupon. The purchase
    /// spares its holder this chore in the next division generated after that cycle.
    var purchasedCycleKey: String?

    /// Key of the cycle whose division used this purchase (spared ``currentUser`` the chore), or
    /// `nil` while it hasn't been used. Set by ``CouponExemption/consume(_:inCycle:store:)``,
    /// cleared by the next purchase. A used coupon can be bought again, even in the same cycle.
    var consumedCycleKey: String?
    
    /// Creates the model from a CloudKit record. Returns `nil` when a required field is missing.
    init?(record: CKRecord) {
        guard
            let name = record["name"] as? String,
            let isOnSale = record["isOnSale"] as? Bool,
            let price = record["price"] as? Int,
            let tier = record["tier"] as? String
        else {
            return nil
        }
        
        self.recordID = record.recordID
        
        self.name = name
        self.isOnSale = isOnSale
        self.price = price
        self.tier = Tier(stored: tier)
        self.currentUser = record["currentUser"] as? CKRecord.Reference
        self.lastUser = record["lastUser"] as? CKRecord.Reference
        self.task = record["task"] as? CKRecord.Reference
        self.purchasedCycleKey = record["purchasedCycleKey"] as? String
        self.consumedCycleKey = record["consumedCycleKey"] as? String
    }
    
    /// Creates a new coupon, not saved yet.
    init(
        name: String,
        isOnSale: Bool,
        price: Int,
        tier: Tier,
        currentUser: CKRecord.Reference? = nil,
        lastUser: CKRecord.Reference? = nil,
        task: CKRecord.Reference? = nil
        )
    {
        self.name = name
        self.isOnSale = isOnSale
        self.price = price
        self.tier = tier
        self.currentUser = currentUser
        self.lastUser = lastUser
        self.task = task
    }
    
    /// Copies the model's fields into `record`, before saving it.
    func populate(record: CKRecord) {
        record["name"] = self.name
        record["isOnSale"] = self.isOnSale
        record["price"] = self.price
        record["tier"] = tier.rawValue
        if let currentUser {
            record["currentUser"] = currentUser
        }
        if let lastUser {
            record["lastUser"] = lastUser
        }
        if let task {
            record["task"] = task
        }
        if let purchasedCycleKey {
            record["purchasedCycleKey"] = purchasedCycleKey
        }
        // Always written: a new purchase has to clear it.
        record["consumedCycleKey"] = consumedCycleKey
    }
}

/// Every chore has one coupon, created together with it and listed under the chore's room in the
/// rewards tab.
extension CouponModel {

    /// The rank a coupon gets from the chore's ``ChoreModel/score``: the harder the chore, the
    /// higher the rank, from ``Tier/novatoDaCasa`` to ``Tier/lendaDaCasa`` in steps of 4 points
    /// (scores start at about 8). ``Tier/almaDaCasa`` is not given to coupons.
    static func tier(forScore score: Int) -> Tier {
        let ranks = Tier.allCases.filter { $0 != .almaDaCasa }
        let index = min(max((score - 8) / 4, 0), ranks.count - 1)
        return ranks[index]
    }

    /// Whether the coupon can be bought in the cycle `latestCycleKey`.
    ///
    /// A coupon has one holder at a time, until a division uses the purchase
    /// (``consumedCycleKey``); then anyone can buy it again. A purchase from an older cycle that
    /// was never marked as used counts as used too.
    func isAvailable(latestCycleKey: String) -> Bool {
        guard isOnSale else { return false }
        guard currentUser != nil, let purchasedCycleKey else { return true }
        if consumedCycleKey != nil { return true }
        return purchasedCycleKey < latestCycleKey
    }

    /// Whether `userID` bought this coupon during the cycle `cycleKey` and no division used it yet.
    func isHeld(by userID: CKRecord.ID, inCycle cycleKey: String) -> Bool {
        currentUser?.recordID == userID && purchasedCycleKey == cycleKey && consumedCycleKey == nil
    }

    /// A coupon for `chore`, priced by ``CouponPricing`` and pointing at it through ``task``.
    ///
    /// The reference uses `.deleteSelf`, so CloudKit deletes the coupon whenever the chore is
    /// deleted, whichever screen deletes it (including the onboarding rollback).
    ///
    /// - Parameter choreRecordID: Record ID of the chore; it may not be saved yet.
    init(for chore: ChoreModel, choreRecordID: CKRecord.ID) {
        let score = max(chore.score, 1)
        self.init(
            name: chore.name,
            isOnSale: true,
            price: CouponPricing.current.price(for: chore),
            tier: CouponModel.tier(forScore: score),
            task: CKRecord.Reference(recordID: choreRecordID, action: .deleteSelf)
        )
    }
}
