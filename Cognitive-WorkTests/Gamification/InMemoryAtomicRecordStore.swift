//
//  InMemoryAtomicRecordStore.swift
//  Cognitive-WorkTests
//
//  Created by Jonas Melo on 16/10/26.
//

import Foundation
import CloudKit
@testable import Cognitive_Work

/// ``AtomicRecordStore`` that behaves like CloudKit's `.ifServerRecordUnchanged` atomic saves,
/// without a server.
///
/// Every stored record has a version (CloudKit's change tag). A fetch hands out *copies* and
/// remembers which version each copy came from. A save succeeds only if every record is at the
/// version it was fetched at — and a record that was never fetched (created locally) must not
/// exist yet. Otherwise nothing is written and `.conflict` is thrown.
///
/// ``holdFetches(_:)`` makes the next `n` fetches wait for each other, so concurrent flows are
/// guaranteed to read the same versions before any of them saves — the race the real code has
/// to survive.
@MainActor
final class InMemoryAtomicRecordStore: AtomicRecordStore {

    private var records: [CKRecord.ID: (record: CKRecord, version: Int)] = [:]

    /// Version each handed-out copy was fetched at. Holds the copies so their identifiers stay unique.
    private var issued: [ObjectIdentifier: (record: CKRecord, version: Int)] = [:]

    private(set) var conflictCount = 0
    private(set) var successfulSaves = 0

    private var gateSize = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    // MARK: - Test helpers

    func seed(_ record: CKRecord) {
        records[record.recordID] = (record.copy() as! CKRecord, (records[record.recordID]?.version ?? 0) + 1)
    }

    func stored(_ id: CKRecord.ID) -> CKRecord? {
        records[id]?.record
    }

    func storedRecords(ofType type: String) -> [CKRecord] {
        records.values.map(\.record).filter { $0.recordType == type }
    }

    /// The next `count` fetches wait until all of them arrived.
    func holdFetches(_ count: Int) {
        gateSize = count
    }

    private func passGate() async {
        guard gateSize > 0 else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiting.append(continuation)
            if waiting.count >= gateSize {
                gateSize = 0
                let all = waiting
                waiting = []
                all.forEach { $0.resume() }
            }
        }
    }

    // MARK: - AtomicRecordStore

    func fetch(_ ids: [CKRecord.ID]) async throws -> [CKRecord.ID: CKRecord] {
        await passGate()
        var result: [CKRecord.ID: CKRecord] = [:]
        for id in ids {
            guard let entry = records[id] else { continue }
            let copy = entry.record.copy() as! CKRecord
            issued[ObjectIdentifier(copy)] = (copy, entry.version)
            result[id] = copy
        }
        return result
    }

    func saveAtomically(_ toSave: [CKRecord]) async throws {
        await Task.yield()

        for record in toSave {
            let fetchedVersion = issued[ObjectIdentifier(record)]?.version
            let serverVersion = records[record.recordID]?.version
            guard fetchedVersion == serverVersion else {
                conflictCount += 1
                throw AtomicRecordStoreError.conflict
            }
        }

        for record in toSave {
            let next = (records[record.recordID]?.version ?? 0) + 1
            records[record.recordID] = (record.copy() as! CKRecord, next)
            // Like CloudKit, the object that was saved still carries its old tag.
            issued[ObjectIdentifier(record)] = nil
        }
        successfulSaves += 1
    }
}

// MARK: - Fixtures

@MainActor
enum GamificationFixture {

    static let zone = CKRecordZone.ID(zoneName: "HomeEnvironment", ownerName: CKCurrentUserDefaultName)
    static let houseID = CKRecord.ID(recordName: "house", zoneID: zone)

    static func id(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: zone)
    }

    /// A daily, 15-minute chore.
    static func chore(_ name: String, room: CKRecord.ID) -> CKRecord {
        let record = CKRecord(recordType: ChoreModel.recordType, recordID: id(name))
        ChoreModel(
            name: name,
            description: "",
            frequency: .daily,
            duration: 15,
            isPublic: true,
            priorityTag: .medium,
            roomReference: CKRecord.Reference(recordID: room, action: .none)
        ).populate(record: record)
        return record
    }

    static func coupon(_ name: String, chore: CKRecord.ID) -> CKRecord {
        let record = CKRecord(recordType: CouponModel.recordType, recordID: id(name))
        CouponModel(
            name: name,
            isOnSale: true,
            price: 0,
            tier: .novatoDaCasa,
            task: CKRecord.Reference(recordID: chore, action: .none)
        ).populate(record: record)
        return record
    }

    /// A house member's ``UserModel`` record (owner = its record name). `legacyPoints` is the old
    /// `points` field, which seeds the score when none exists yet.
    static func user(_ id: CKRecord.ID, points legacyPoints: Int = 0) -> CKRecord {
        let record = CKRecord(recordType: UserModel.recordType, recordID: id)
        UserModel(name: id.recordName, tier: .novatoDaCasa, recordID: id, ownerRecordName: id.recordName)
            .populate(record: record)
        record["points"] = legacyPoints
        return record
    }

    /// The ``UserScoreModel`` of the member whose user record is `user`.
    static func score(for user: CKRecord.ID, points: Int) -> CKRecord {
        let id = scoreID(of: user)
        let record = CKRecord(recordType: UserScoreModel.recordType, recordID: id)
        UserScoreModel(ownerRecordName: user.recordName, points: points).populate(record: record)
        return record
    }

    static func scoreID(of user: CKRecord.ID) -> CKRecord.ID {
        UserScoreModel.recordID(ownerRecordName: user.recordName, zoneID: user.zoneID)
    }

    /// Points in the score of `user`, or `nil` when it has no score yet.
    @MainActor
    static func points(of user: CKRecord.ID, in store: InMemoryAtomicRecordStore) -> Int? {
        store.stored(scoreID(of: user))?["points"] as? Int
    }

    static func wallet(for user: CKRecord.ID, balance: Int) -> CKRecord {
        let record = CKRecord(recordType: CoinWalletModel.recordType, recordID: CoinWalletModel.recordID(for: user))
        CoinWalletModel(user: CKRecord.Reference(recordID: user, action: .none), balance: balance)
            .populate(record: record)
        return record
    }

    static func balance(of user: CKRecord.ID, in store: InMemoryAtomicRecordStore) -> Int? {
        store.stored(CoinWalletModel.recordID(for: user)).flatMap(CoinWalletModel.init(record:))?.balance
    }

    static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    static func cycle(start: Date, days: Int = 14) -> HouseCycleModel {
        HouseCycleModel(startDate: start, endDate: Calendar.current.date(byAdding: .day, value: days, to: start)!)
    }
}
