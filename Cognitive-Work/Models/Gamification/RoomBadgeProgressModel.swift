//
//  RoomBadgeProgressModel.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 11/11/26.
//

import Foundation
import CloudKit

/// One change to a member's room badge count: a chore of `room` checked off (`delta` 1) or
/// unchecked (`delta` -1).
struct RoomBadgeChange: Equatable {
    /// The kind of room the chore belongs to.
    var room: DefaultRoomsOnboarding
    /// How many check-offs to add (negative to take back).
    var delta: Int
    /// Whether the chore is a one-off one: those count only up to
    /// ``RoomBadgeProgressModel/oneOffDailyLimit`` times a day per room.
    var isOneOff: Bool = false
}

/// A house member's progress towards the room badges (``RoomBadge``): how many chores they
/// checked off in each kind of default room, and which badges they unlocked.
///
/// Kept apart from ``UserModel`` for the same reason as ``UserScoreModel``: `UserModel` is saved
/// whole by every profile edit, so a stale copy could undo check-offs counted on another device.
/// Only ``BadgeManager`` writes it, always through ``AtomicRecordStore`` and starting from the
/// server's value.
///
/// One per person, named `badges-<ownerRecordName>` in the house zone. Unlike the points, it is
/// never reset at the end of a cycle, and an unlocked badge is never taken back, even when a
/// chore is unchecked.
struct RoomBadgeProgressModel: CloudKitSyncable, Equatable {

    /// The CloudKit record type.
    static var recordType: String = "RoomBadgeProgressModel"

    /// One-off chores of a room that count towards its badges each day. More than that are
    /// still checked off, but don't count, so creating, checking and deleting chores over and
    /// over doesn't unlock anything.
    static let oneOffDailyLimit = 3

    /// The CloudKit record ID (`badges-<owner>`). `nil` until the model is saved.
    var recordID: CKRecord.ID?

    /// The iCloud identity of the person (``UserModel/ownerRecordName``) this progress belongs to.
    var ownerRecordName: String
    /// Chores checked off per kind of room, keyed by ``DefaultRoomsOnboarding`` raw value.
    var counts: [String: Int]
    /// Raw values of the unlocked badges, in the order they were unlocked.
    var unlocked: [String]
    /// The day ``oneOffCounts`` is about (``dayKey(for:calendar:)``). `nil` before any one-off chore.
    var oneOffDay: String?
    /// One-off chores counted on ``oneOffDay``, per kind of room.
    var oneOffCounts: [String: Int]

    /// Creates an empty progress, not saved yet.
    init(
        ownerRecordName: String,
        counts: [String: Int] = [:],
        unlocked: [String] = [],
        oneOffDay: String? = nil,
        oneOffCounts: [String: Int] = [:]
    ) {
        self.ownerRecordName = ownerRecordName
        self.counts = counts
        self.unlocked = unlocked
        self.oneOffDay = oneOffDay
        self.oneOffCounts = oneOffCounts
    }

    /// Creates the model from a CloudKit record. Returns `nil` when the owner is missing.
    init?(record: CKRecord) {
        guard let ownerRecordName = record["ownerRecordName"] as? String else { return nil }

        self.recordID = record.recordID
        self.ownerRecordName = ownerRecordName
        self.counts = Self.decode(record["counts"] as? Data)
        self.unlocked = record["unlocked"] as? [String] ?? []
        self.oneOffDay = record["oneOffDay"] as? String
        self.oneOffCounts = Self.decode(record["oneOffCounts"] as? Data)
    }

    /// Copies the model's fields into `record`, before saving it.
    ///
    /// The counts are saved as JSON: a record can't hold a dictionary.
    func populate(record: CKRecord) {
        record["ownerRecordName"] = ownerRecordName
        record["counts"] = try? JSONEncoder().encode(counts)
        record["unlocked"] = unlocked
        record["oneOffDay"] = oneOffDay
        record["oneOffCounts"] = try? JSONEncoder().encode(oneOffCounts)
    }

    /// Counts saved as JSON; empty when missing or unreadable.
    private static func decode(_ data: Data?) -> [String: Int] {
        guard let data else { return [:] }
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }

    // MARK: - Reading

    /// Chores checked off in rooms of kind `room`.
    func count(for room: DefaultRoomsOnboarding) -> Int {
        counts[room.rawValue] ?? 0
    }

    /// Whether `badge` was unlocked.
    func isUnlocked(_ badge: RoomBadge) -> Bool {
        unlocked.contains(badge.rawValue)
    }

    /// The first badge of `room` still locked; `nil` once all of them are unlocked.
    func nextBadge(in room: DefaultRoomsOnboarding) -> RoomBadge? {
        room.badges.first { !isUnlocked($0) }
    }

    /// One-off chores of `room` counted on the day `dayKey`.
    func oneOffCount(for room: DefaultRoomsOnboarding, on dayKey: String) -> Int {
        oneOffDay == dayKey ? oneOffCounts[room.rawValue] ?? 0 : 0
    }

    // MARK: - Changing

    /// Applies `changes` and unlocks every badge whose threshold was reached.
    ///
    /// Counts never go below 0, and badges already unlocked stay unlocked. The one-off counts of
    /// a day other than `dayKey` are dropped first. It's up to the caller to leave out one-off
    /// check-offs over ``oneOffDailyLimit`` (``BadgeManager/countableOneOffs(in:for:on:)``).
    ///
    /// - Returns: The badges unlocked by this change, in the order of each room's ladder.
    @discardableResult
    mutating func apply(_ changes: [RoomBadgeChange], dayKey: String) -> [RoomBadge] {
        if oneOffDay != dayKey {
            oneOffDay = dayKey
            oneOffCounts = [:]
        }

        var touched: [DefaultRoomsOnboarding] = []
        for change in changes where change.delta != 0 {
            let key = change.room.rawValue
            counts[key] = max((counts[key] ?? 0) + change.delta, 0)
            if change.isOneOff, change.delta > 0 {
                oneOffCounts[key, default: 0] += change.delta
            }
            if !touched.contains(change.room) { touched.append(change.room) }
        }

        var newlyUnlocked: [RoomBadge] = []
        for room in touched {
            for badge in room.badges where !isUnlocked(badge) && count(for: room) >= badge.threshold {
                unlocked.append(badge.rawValue)
                newlyUnlocked.append(badge)
            }
        }
        return newlyUnlocked
    }

    // MARK: - Identity

    /// The fixed record ID of the progress of `ownerRecordName` in the house zone `zoneID`.
    static func recordID(ownerRecordName: String, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: "badges-\(ownerRecordName)", zoneID: zoneID)
    }

    /// ID of the progress of the person behind `userID` (a house user record).
    ///
    /// Keyed by owner, like ``UserScoreModel``, so the extra records of the same person share it.
    /// Falls back to the user record's name when the owner isn't known.
    static func recordID(for user: UserModel, userID: CKRecord.ID) -> CKRecord.ID {
        recordID(ownerRecordName: owner(of: user, userID: userID), zoneID: userID.zoneID)
    }

    /// The owner the progress of `user` is saved under.
    static func owner(of user: UserModel, userID: CKRecord.ID) -> String {
        user.ownerRecordName.isEmpty ? userID.recordName : user.ownerRecordName
    }

    /// The day a one-off check-off is counted on, as `yyyy-MM-dd` in `calendar`.
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // MARK: - Reading and writing

    /// The fetched progress record, or a new empty one.
    ///
    /// - Parameters:
    ///   - id: The progress' ID (``recordID(for:userID:)``).
    ///   - fetched: Result of a fetch that included `id`.
    ///   - ownerRecordName: Whose progress it is, for a new record.
    ///   - houseID: Parent of a new record, so it is shared with the house.
    /// - Returns: The record to save and the progress it currently holds.
    static func record(
        _ id: CKRecord.ID,
        in fetched: [CKRecord.ID: CKRecord],
        ownerRecordName: String,
        houseID: CKRecord.ID?
    ) -> (record: CKRecord, progress: RoomBadgeProgressModel) {
        if let existing = fetched[id], let progress = RoomBadgeProgressModel(record: existing) {
            return (existing, progress)
        }
        let record = CKRecord(recordType: recordType, recordID: id)
        if let houseID {
            record.parent = CKRecord.Reference(recordID: houseID, action: .none)
        }
        var progress = RoomBadgeProgressModel(ownerRecordName: ownerRecordName)
        progress.recordID = id
        progress.populate(record: record)
        return (record, progress)
    }
}
