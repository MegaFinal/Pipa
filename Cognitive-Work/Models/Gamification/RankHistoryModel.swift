//
//  RankHistoryModel.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 16/10/26.
//

import Foundation
import CloudKit

/// A user's rank and points at the end of one cycle, so they can follow their progress. Points
/// start over at every cycle, so `points` is what the user made in that cycle.
///
/// Created together with the cycle's ``CoinPayoutModel`` (same atomic save) and named
/// `rank-<cycle key>-<user recordName>`, so there is exactly one per user per cycle.
struct RankHistoryModel: CloudKitSyncable, Equatable {

    /// The CloudKit record type.
    static var recordType: String = "RankHistoryModel"

    /// The CloudKit record ID (`rank-<cycle key>-<user>`). `nil` until the model is saved.
    var recordID: CKRecord.ID?

    /// The member this entry belongs to.
    var user: CKRecord.Reference
    /// Key of the cycle (see ``HouseCycleModel/key(for:calendar:)``).
    var cycleKey: String
    /// First day of the cycle.
    var cycleStart: Date
    /// Last day of the cycle.
    var cycleEnd: Date
    /// The rank the member reached in the cycle.
    var tier: Tier
    /// The points the member made in the cycle.
    var points: Int

    /// Creates a new entry, not saved yet.
    init(user: CKRecord.Reference, cycleKey: String, cycleStart: Date, cycleEnd: Date, tier: Tier, points: Int) {
        self.user = user
        self.cycleKey = cycleKey
        self.cycleStart = cycleStart
        self.cycleEnd = cycleEnd
        self.tier = tier
        self.points = points
    }

    /// Creates the model from a CloudKit record. Returns `nil` when a field is missing.
    init?(record: CKRecord) {
        guard
            let user = record["user"] as? CKRecord.Reference,
            let cycleKey = record["cycleKey"] as? String,
            let cycleStart = record["cycleStart"] as? Date,
            let cycleEnd = record["cycleEnd"] as? Date,
            let tier = record["tier"] as? String,
            let points = record["points"] as? Int
        else { return nil }

        self.recordID = record.recordID
        self.user = user
        self.cycleKey = cycleKey
        self.cycleStart = cycleStart
        self.cycleEnd = cycleEnd
        self.tier = Tier(stored: tier)
        self.points = points
    }

    /// Copies the model's fields into `record`, before saving it.
    func populate(record: CKRecord) {
        record["user"] = user
        record["cycleKey"] = cycleKey
        record["cycleStart"] = cycleStart
        record["cycleEnd"] = cycleEnd
        record["tier"] = tier.rawValue
        record["points"] = points
    }

    /// The fixed record ID of `userID`'s entry for the cycle `cycleKey`.
    static func recordID(cycleKey: String, userID: CKRecord.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: "rank-\(cycleKey)-\(userID.recordName)", zoneID: userID.zoneID)
    }

    /// `userID`'s history, most recent cycle first.
    static func fetchHistory(for userID: CKRecord.ID) async -> [RankHistoryModel] {
        await CloudKitManager.shared.fetchAll(RankHistoryModel.self)
            .filter { $0.user.recordID == userID }
            .sorted { $0.cycleKey > $1.cycleKey }
    }
}
