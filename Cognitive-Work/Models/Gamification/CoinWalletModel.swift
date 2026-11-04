//
//  CoinWalletModel.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 16/10/26.
//

import Foundation
import CloudKit

/// A user's coin balance.
///
/// Kept apart from ``UserModel`` on purpose: `UserModel` is re-saved whole by every profile
/// edit, so a balance stored there could be overwritten by a stale copy and undo a purchase
/// (points are kept apart for the same reason, in ``UserScoreModel``). Only ``CouponPurchaseService`` (debits) and ``CycleSettlementService``
/// (credits) write a wallet, always through ``AtomicRecordStore``, so the balance never goes
/// negative and no credit is lost.
///
/// One per user, named `wallet-<user recordName>` in the house zone, so it is read by ID. It is
/// created the first time it is needed, seeded with the legacy ``UserModel/coins``.
struct CoinWalletModel: CloudKitSyncable, Equatable {

    /// The CloudKit record type.
    static var recordType: String = "CoinWalletModel"

    /// The CloudKit record ID (`wallet-<user>`). `nil` until the model is saved.
    var recordID: CKRecord.ID?

    /// The member who owns the wallet.
    var user: CKRecord.Reference
    /// How many coins the member has. Never negative.
    var balance: Int

    /// Creates a new wallet, not saved yet.
    init(user: CKRecord.Reference, balance: Int) {
        self.user = user
        self.balance = balance
    }

    /// Creates the model from a CloudKit record. Returns `nil` when a field is missing.
    init?(record: CKRecord) {
        guard
            let user = record["user"] as? CKRecord.Reference,
            let balance = record["balance"] as? Int
        else { return nil }

        self.recordID = record.recordID
        self.user = user
        self.balance = balance
    }

    /// Copies the model's fields into `record`, before saving it.
    func populate(record: CKRecord) {
        record["user"] = user
        record["balance"] = balance
    }

    /// The fixed record ID of `userID`'s wallet.
    static func recordID(for userID: CKRecord.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: "wallet-\(userID.recordName)", zoneID: userID.zoneID)
    }

    /// The fetched wallet record of `userID`, or a new one seeded with `legacyCoins`.
    ///
    /// - Parameters:
    ///   - userID: The member the wallet belongs to.
    ///   - fetched: Records already fetched from the server (the wallet may be among them).
    ///   - houseID: The house, set as the parent of a new wallet so it is shared with the house.
    ///   - legacyCoins: The coins kept in the old ``UserModel/coins`` field, used to start a new wallet.
    /// - Returns: The record to save and its current balance.
    static func record(
        for userID: CKRecord.ID,
        in fetched: [CKRecord.ID: CKRecord],
        houseID: CKRecord.ID,
        legacyCoins: Int
    ) -> (record: CKRecord, balance: Int) {
        let id = recordID(for: userID)
        if let existing = fetched[id], let wallet = CoinWalletModel(record: existing) {
            return (existing, wallet.balance)
        }
        let record = CKRecord(recordType: recordType, recordID: id)
        record.parent = CKRecord.Reference(recordID: houseID, action: .none)
        CoinWalletModel(user: CKRecord.Reference(recordID: userID, action: .none), balance: max(legacyCoins, 0))
            .populate(record: record)
        return (record, max(legacyCoins, 0))
    }

    /// Current balance of `userID`; `legacyCoins` while the wallet doesn't exist yet.
    @MainActor
    static func balance(
        for userID: CKRecord.ID,
        legacyCoins: Int,
        store: AtomicRecordStore? = nil
    ) async -> Int {
        let store = store ?? CloudKitAtomicRecordStore()
        let id = recordID(for: userID)
        guard let fetched = try? await store.fetch([id]) else { return max(legacyCoins, 0) }
        return fetched[id].flatMap(CoinWalletModel.init(record:))?.balance ?? max(legacyCoins, 0)
    }
}
