//
//  UserScoreModel.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 19/10/26.
//

import Foundation
import CloudKit

/// A house member's points in the current cycle. The rank follows them (``Tier/init(points:)``).
///
/// Kept apart from ``UserModel`` on purpose, like ``CoinWalletModel``: `UserModel` is saved whole
/// by every profile edit, so points stored there could be overwritten by a stale copy (undoing
/// points from another device, or the reset at the end of a cycle). Only ``ScoreManager``
/// (adds/removes) and ``CycleSettlementService`` (resets to 0) write a score, always through
/// ``AtomicRecordStore`` and starting from the server's value.
///
/// One per person, named `score-<ownerRecordName>` in the house zone. Keyed by owner rather than
/// by user record, so the extra `UserModel` records of the same person (see
/// ``CloudKitManager/deduplicatedByOwner(_:)``) share it. It is created the first time points
/// change, seeded with the legacy `points` field of the user's record.
///
/// ``UserModel/points`` is the in-memory copy screens read: ``HouseDataStore`` fills it from these
/// records on every load.
struct UserScoreModel: CloudKitSyncable, Equatable {

    /// The CloudKit record type.
    static var recordType: String = "UserScoreModel"

    /// The CloudKit record ID (`score-<owner>`). `nil` until the model is saved.
    var recordID: CKRecord.ID?

    /// The iCloud identity of the person (``UserModel/ownerRecordName``) this score belongs to.
    var ownerRecordName: String
    /// The person's points in the current cycle.
    var points: Int

    /// Creates a new score, not saved yet.
    init(ownerRecordName: String, points: Int) {
        self.ownerRecordName = ownerRecordName
        self.points = points
    }

    /// Creates the model from a CloudKit record. Returns `nil` when a field is missing.
    init?(record: CKRecord) {
        guard
            let ownerRecordName = record["ownerRecordName"] as? String,
            let points = record["points"] as? Int
        else { return nil }

        self.recordID = record.recordID
        self.ownerRecordName = ownerRecordName
        self.points = points
    }

    /// Copies the model's fields into `record`, before saving it.
    func populate(record: CKRecord) {
        record["ownerRecordName"] = ownerRecordName
        record["points"] = points
    }

    // MARK: - Identity

    /// The fixed record ID of the score of `ownerRecordName` in the house zone `zoneID`.
    static func recordID(ownerRecordName: String, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: "score-\(ownerRecordName)", zoneID: zoneID)
    }

    /// ID of the score of the person behind `userID` (a house user record).
    static func recordID(for user: UserModel, userID: CKRecord.ID) -> CKRecord.ID {
        recordID(ownerRecordName: user.ownerRecordName, zoneID: userID.zoneID)
    }

    // MARK: - Reading and writing

    /// The fetched score record, or a new one seeded with the legacy points of `userRecord`.
    ///
    /// - Parameters:
    ///   - id: The score's ID (``recordID(for:userID:)``).
    ///   - fetched: Result of a fetch that included `id` and, for the seed, the user's record.
    ///   - userRecord: The user's `UserModel` record, if fetched; its old `points` field seeds a
    ///     new score.
    ///   - houseID: Parent of a new score, so it is shared with the house.
    /// - Returns: The record to save and the points it currently holds.
    static func record(
        _ id: CKRecord.ID,
        in fetched: [CKRecord.ID: CKRecord],
        ownerRecordName: String,
        userRecord: CKRecord?,
        houseID: CKRecord.ID?
    ) -> (record: CKRecord, points: Int) {
        if let existing = fetched[id], let score = UserScoreModel(record: existing) {
            return (existing, score.points)
        }
        let legacy = max(userRecord?["points"] as? Int ?? 0, 0)
        let record = CKRecord(recordType: recordType, recordID: id)
        if let houseID {
            record.parent = CKRecord.Reference(recordID: houseID, action: .none)
        }
        UserScoreModel(ownerRecordName: ownerRecordName, points: legacy).populate(record: record)
        return (record, legacy)
    }

    /// Copies each person's score into the matching users' ``UserModel/points``. Users without a
    /// score yet keep the legacy points read from their record.
    @MainActor
    static func apply(_ scores: [UserScoreModel], to users: [UserModel]) {
        var byOwner: [String: Int] = [:]
        for score in scores {
            // A record from another house's zone has a different zone; owners are unique per
            // zone, so match on both.
            guard let zone = score.recordID?.zoneID else { continue }
            byOwner["\(zone.zoneName)|\(zone.ownerName)|\(score.ownerRecordName)"] = score.points
        }
        for user in users {
            guard let zone = user.recordID?.zoneID,
                  let points = byOwner["\(zone.zoneName)|\(zone.ownerName)|\(user.ownerRecordName)"]
            else { continue }
            user.points = points
        }
    }

    /// Current points of `user` on the server; the legacy points while no score exists.
    @MainActor
    static func points(for user: UserModel, store: AtomicRecordStore? = nil) async -> Int {
        guard let userID = user.recordID else { return user.points }
        let store = store ?? CloudKitAtomicRecordStore()
        let id = recordID(for: user, userID: userID)
        guard let fetched = try? await store.fetch([id]) else { return user.points }
        return fetched[id].flatMap(UserScoreModel.init(record:))?.points ?? user.points
    }
}
