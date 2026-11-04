//
//  CoinPayoutModel.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 16/10/26.
//

import Foundation
import CloudKit

/// The coins one user earns for one closed cycle.
///
/// Lifecycle (see ``CycleSettlementService``):
/// 1. When a device notices a cycle ended, it creates one payout per member, `pending`, with the
///    amount frozen from the member's rank at that moment.
/// 2. The member taps "Resgatar" in the retrospective: the payout becomes `confirmed` and the
///    amount is added to their ``CoinWalletModel`` in the same atomic save.
///
/// Named `payout-<cycle key>-<user recordName>`: a second creation fails instead of duplicating,
/// and a confirmed payout is never credited again.
struct CoinPayoutModel: CloudKitSyncable, Equatable {

    /// The CloudKit record type.
    static var recordType: String = "CoinPayoutModel"

    /// Whether the payout's coins are already in the wallet.
    enum Status: String {
        /// Created, waiting for the member to redeem it.
        case pending
        /// Redeemed: the coins were added to the member's wallet.
        case confirmed
    }

    /// The CloudKit record ID (`payout-<cycle key>-<user>`). `nil` until the model is saved.
    var recordID: CKRecord.ID?

    /// The member who earns the coins.
    var user: CKRecord.Reference
    /// Key of the cycle being paid (see ``HouseCycleModel/key(for:calendar:)``).
    var cycleKey: String
    /// Rank the amount was computed from.
    var tier: Tier
    /// The member's points when the cycle was closed.
    var points: Int
    /// How many coins the member earns (``Tier/cycleCoins`` of ``tier``).
    var amount: Int
    /// Whether the coins were already redeemed.
    var status: Status
    /// When the member redeemed the coins. `nil` while ``status`` is ``Status/pending``.
    var confirmedAt: Date?

    /// Creates a new payout, pending by default and not saved yet.
    init(user: CKRecord.Reference, cycleKey: String, tier: Tier, points: Int, amount: Int,
         status: Status = .pending, confirmedAt: Date? = nil) {
        self.user = user
        self.cycleKey = cycleKey
        self.tier = tier
        self.points = points
        self.amount = amount
        self.status = status
        self.confirmedAt = confirmedAt
    }

    /// Creates the model from a CloudKit record. Returns `nil` when a required field is missing.
    init?(record: CKRecord) {
        guard
            let user = record["user"] as? CKRecord.Reference,
            let cycleKey = record["cycleKey"] as? String,
            let tier = record["tier"] as? String,
            let points = record["points"] as? Int,
            let amount = record["amount"] as? Int,
            let statusRaw = record["status"] as? String,
            let status = Status(rawValue: statusRaw)
        else { return nil }

        self.recordID = record.recordID
        self.user = user
        self.cycleKey = cycleKey
        self.tier = Tier(stored: tier)
        self.points = points
        self.amount = amount
        self.status = status
        self.confirmedAt = record["confirmedAt"] as? Date
    }

    /// Copies the model's fields into `record`, before saving it.
    func populate(record: CKRecord) {
        record["user"] = user
        record["cycleKey"] = cycleKey
        record["tier"] = tier.rawValue
        record["points"] = points
        record["amount"] = amount
        record["status"] = status.rawValue
        record["confirmedAt"] = confirmedAt
    }

    /// The fixed record ID of `userID`'s payout for the cycle `cycleKey`.
    static func recordID(cycleKey: String, userID: CKRecord.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: "payout-\(cycleKey)-\(userID.recordName)", zoneID: userID.zoneID)
    }
}
