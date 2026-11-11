//
//  BadgeManagerTests.swift
//  Cognitive-WorkTests
//
//  Created by Jonas Melo on 11/11/26.
//

import Testing
import Foundation
import CloudKit
@testable import Cognitive_Work

@MainActor
struct BadgeManagerTests {

    private let alice = GamificationFixture.id("alice-house")
    private let today = GamificationFixture.day(2026, 11, 11)

    private func localAlice() -> UserModel {
        UserModel(name: "alice", tier: .tradicionalI, recordID: alice, ownerRecordName: "alice")
    }

    private var progressID: CKRecord.ID {
        RoomBadgeProgressModel.recordID(ownerRecordName: "alice", zoneID: alice.zoneID)
    }

    private func stored(in store: InMemoryAtomicRecordStore) -> RoomBadgeProgressModel? {
        store.stored(progressID).flatMap(RoomBadgeProgressModel.init(record:))
    }

    private func checkOffs(_ count: Int, in room: DefaultRoomsOnboarding, oneOff: Bool = false) -> [RoomBadgeChange] {
        Array(repeating: RoomBadgeChange(room: room, delta: 1, isOneOff: oneOff), count: count)
    }

    @Test func firstChangeCreatesTheProgress() async {
        let store = InMemoryAtomicRecordStore()
        let manager = BadgeManager(store: store)

        let unlocked = await manager.apply(checkOffs(2, in: .garage), to: localAlice(), on: today)

        #expect(unlocked == [.quartinhoDaBagunca])
        #expect(stored(in: store)?.count(for: .garage) == 2)
        #expect(stored(in: store)?.ownerRecordName == "alice")
    }

    @Test func addsToTheServerValue() async {
        let store = InMemoryAtomicRecordStore()
        let manager = BadgeManager(store: store)
        await manager.apply(checkOffs(20, in: .kitchen), to: localAlice(), on: today)

        let unlocked = await manager.apply(checkOffs(5, in: .kitchen), to: localAlice(), on: today)

        #expect(unlocked == [.torreDeLouca])
        #expect(stored(in: store)?.count(for: .kitchen) == 25)
    }

    @Test func concurrentChangesBothCount() async {
        let store = InMemoryAtomicRecordStore()
        // The progress already exists, so both devices fetch it and race to save.
        let seed = CKRecord(recordType: RoomBadgeProgressModel.recordType, recordID: progressID)
        RoomBadgeProgressModel(ownerRecordName: "alice").populate(record: seed)
        store.seed(seed)
        let deviceA = BadgeManager(store: store)
        let deviceB = BadgeManager(store: store)
        store.holdFetches(2)

        async let first = deviceA.apply(checkOffs(1, in: .garage), to: localAlice(), on: today)
        async let second = deviceB.apply(checkOffs(1, in: .garage), to: localAlice(), on: today)
        let results = await [first, second]

        #expect(stored(in: store)?.count(for: .garage) == 2)
        #expect(results.flatMap { $0 } == [.quartinhoDaBagunca])
        #expect(store.conflictCount >= 1)
    }

    @Test func takingBackKeepsTheBadge() async {
        let store = InMemoryAtomicRecordStore()
        let manager = BadgeManager(store: store)
        await manager.apply(checkOffs(2, in: .garage), to: localAlice(), on: today)

        await manager.apply([RoomBadgeChange(room: .garage, delta: -2)], to: localAlice(), on: today)

        #expect(stored(in: store)?.count(for: .garage) == 0)
        #expect(stored(in: store)?.isUnlocked(.quartinhoDaBagunca) == true)
    }

    @Test func oneOffsCountOnlyUpToTheDailyLimit() async {
        let store = InMemoryAtomicRecordStore()
        let manager = BadgeManager(store: store)
        let limit = RoomBadgeProgressModel.oneOffDailyLimit

        let before = await manager.countableOneOffs(for: localAlice(), on: today)
        #expect(before[.kitchen] == limit)

        await manager.apply(checkOffs(limit, in: .kitchen, oneOff: true), to: localAlice(), on: today)
        let after = await manager.countableOneOffs(for: localAlice(), on: today)
        let tomorrow = await manager.countableOneOffs(for: localAlice(), on: GamificationFixture.day(2026, 11, 12))

        #expect(after[.kitchen] == 0)
        #expect(after[.bathroom] == limit)
        #expect(tomorrow[.kitchen] == limit)
    }

    @Test func progressOfSomeoneWithoutOneIsEmpty() async {
        let manager = BadgeManager(store: InMemoryAtomicRecordStore())

        let progress = await manager.progress(of: localAlice())

        #expect(progress.counts.isEmpty)
        #expect(progress.unlocked.isEmpty)
    }
}
