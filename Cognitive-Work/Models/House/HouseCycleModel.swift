//
//  HouseCycleModel.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 16/10/26.
//

import Foundation
import CloudKit

/// One division cycle of a house: the days a chore division covers.
///
/// Written by ``TaskSchedulerEngine/schedule(chores:users:)`` every time it generates a division,
/// so the end of a cycle is read instead of guessed. Everything that depends on "which cycle is
/// this" uses ``key``: coin payouts, the rank history, and coupon purchases.
///
/// Rules:
/// - A cycle covers `startDate...endDate`, both days included.
/// - The **latest** cycle is the one with the most recent start. Coupons bought now belong to it.
/// - A cycle is **closed** once today is after its `endDate`; closed cycles get paid.
/// - Generating a division before the latest cycle ended cuts that cycle short: it ends the day
///   before the new one starts.
struct HouseCycleModel: CloudKitSyncable, Equatable {

    /// The CloudKit record type.
    static var recordType: String = "HouseCycleModel"

    /// The CloudKit record ID (`cycle-<key>`). `nil` until the model is saved.
    var recordID: CKRecord.ID?

    /// First day of the cycle (start of day).
    var startDate: Date

    /// Last day of the cycle (start of day), included.
    var endDate: Date

    /// Stable identifier, `yyyy-MM-dd` of ``startDate``. Stored, so every device reads the same
    /// value whatever its time zone. Keys sort chronologically as plain strings.
    var key: String

    /// Creates a cycle, moving both dates to the start of their day.
    /// - Parameters:
    ///   - startDate: First day of the cycle.
    ///   - endDate: Last day of the cycle, included.
    ///   - key: The cycle's key; by default built from `startDate`.
    ///   - calendar: The calendar used for days.
    init(startDate: Date, endDate: Date, key: String? = nil, calendar: Calendar = .current) {
        self.startDate = calendar.startOfDay(for: startDate)
        self.endDate = calendar.startOfDay(for: endDate)
        self.key = key ?? Self.key(for: startDate, calendar: calendar)
    }

    /// Creates the model from a CloudKit record. Returns `nil` when a field is missing.
    init?(record: CKRecord) {
        guard
            let startDate = record["startDate"] as? Date,
            let endDate = record["endDate"] as? Date,
            let key = record["key"] as? String
        else { return nil }

        self.recordID = record.recordID
        self.startDate = startDate
        self.endDate = endDate
        self.key = key
    }

    /// Copies the model's fields into `record`, before saving it.
    func populate(record: CKRecord) {
        record["startDate"] = startDate
        record["endDate"] = endDate
        record["key"] = key
    }

    // MARK: - Keys

    /// The key of a cycle that starts on `date`: its day as `yyyy-MM-dd`.
    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0, components.month ?? 0, components.day ?? 0
        )
    }

    /// The fixed record ID of the cycle with `key` in the house zone `zoneID`.
    static func recordID(forKey key: String, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: "cycle-\(key)", zoneID: zoneID)
    }

    // MARK: - Rules

    /// Whether the cycle already ended: `today` is after its last day.
    func isClosed(asOf today: Date, calendar: Calendar = .current) -> Bool {
        calendar.startOfDay(for: endDate) < calendar.startOfDay(for: today)
    }

    /// Cycles sorted by start, oldest first.
    static func sorted(_ cycles: [HouseCycleModel]) -> [HouseCycleModel] {
        cycles.sorted { $0.key < $1.key }
    }

    /// The cycle with the most recent start.
    static func latest(_ cycles: [HouseCycleModel]) -> HouseCycleModel? {
        sorted(cycles).last
    }

    /// The cycle right before ``latest(_:)``.
    static func previous(_ cycles: [HouseCycleModel]) -> HouseCycleModel? {
        let sorted = sorted(cycles)
        return sorted.count >= 2 ? sorted[sorted.count - 2] : nil
    }

    /// Every cycle that already ended, oldest first.
    static func closed(_ cycles: [HouseCycleModel], asOf today: Date, calendar: Calendar = .current) -> [HouseCycleModel] {
        sorted(cycles).filter { $0.isClosed(asOf: today, calendar: calendar) }
    }

    /// The cycles to write when a new division covering `start...end` is generated: the new
    /// cycle and, when the latest one is still running past `start`, that one cut short.
    ///
    /// Re-generating on the day a cycle was created (same start) just rewrites that cycle.
    static func cyclesToSave(
        newStart start: Date,
        newEnd end: Date,
        existing: [HouseCycleModel],
        calendar: Calendar = .current
    ) -> [HouseCycleModel] {
        var new = HouseCycleModel(startDate: start, endDate: end, calendar: calendar)
        var result: [HouseCycleModel] = []

        if let latest = latest(existing) {
            if latest.key == new.key {
                new.recordID = latest.recordID
            } else if latest.endDate >= new.startDate,
                      let dayBefore = calendar.date(byAdding: .day, value: -1, to: new.startDate) {
                var shortened = latest
                shortened.endDate = max(calendar.startOfDay(for: dayBefore), latest.startDate)
                result.append(shortened)
            }
        }

        result.append(new)
        return result
    }
}

// MARK: - Persistence

extension HouseCycleModel {

    /// Cycles this device saved in the last ``recentSaveWindow``, by record ID.
    ///
    /// A CloudKit query only returns a record once the server has indexed it, a few seconds after
    /// the save. Without these, every screen that reloads right after a division (the rewards tab
    /// above all) would still read the old cycles, and the coupons that division used would keep
    /// showing as the user's until the app was reopened.
    private static var recentlySaved: [CKRecord.ID: (cycle: HouseCycleModel, savedAt: Date)] = [:]

    /// How long a cycle saved by this device overrides what the query returns.
    private static let recentSaveWindow: TimeInterval = 120

    /// Every cycle of the house in `zoneID`, including the ones this device just saved.
    static func fetchAll(inHouseZone zoneID: CKRecordZone.ID, now: Date = .now) async -> [HouseCycleModel] {
        let fetched = await CloudKitManager.shared.fetchAll(HouseCycleModel.self)
            .filter { $0.recordID?.zoneID == zoneID }
        return mergingRecentlySaved(into: fetched, zoneID: zoneID, now: now)
    }

    /// `fetched` with the cycles saved by this device in the last ``recentSaveWindow`` in place of
    /// (or added to) what the query returned.
    private static func mergingRecentlySaved(
        into fetched: [HouseCycleModel],
        zoneID: CKRecordZone.ID,
        now: Date
    ) -> [HouseCycleModel] {
        recentlySaved = recentlySaved.filter { now.timeIntervalSince($0.value.savedAt) < recentSaveWindow }
        guard !recentlySaved.isEmpty else { return fetched }

        let kept = fetched.filter { cycle in
            guard let id = cycle.recordID else { return true }
            return recentlySaved[id] == nil
        }
        let saved = recentlySaved.values.map { $0.cycle }.filter { $0.recordID?.zoneID == zoneID }
        return kept + saved
    }

    /// Records the cycle of a division just generated. See ``cyclesToSave(newStart:newEnd:existing:calendar:)``.
    ///
    /// Not contended (only the device generating the division writes it), so it saves with
    /// `.allKeys`.
    @discardableResult
    static func recordNewDivision(start: Date, end: Date, houseID: CKRecord.ID) async -> Bool {
        let zoneID = houseID.zoneID
        let existing = await fetchAll(inHouseZone: zoneID)
        let toSave = cyclesToSave(newStart: start, newEnd: end, existing: existing)

        let records: [CKRecord] = toSave.map { cycle in
            let recordID = cycle.recordID ?? Self.recordID(forKey: cycle.key, zoneID: zoneID)
            let record = CKRecord(recordType: recordType, recordID: recordID)
            cycle.populate(record: record)
            record.parent = CKRecord.Reference(recordID: houseID, action: .none)
            return record
        }

        let didSave = await CloudKitManager.shared.batchSave(records: records, zoneID: zoneID, savePolicy: .allKeys)
        if didSave {
            // Readers see these right away, before the query catches up (see `recentlySaved`).
            let now = Date.now
            for (cycle, record) in zip(toSave, records) {
                var saved = cycle
                saved.recordID = record.recordID
                recentlySaved[record.recordID] = (saved, now)
            }
        }
        return didSave
    }
}
