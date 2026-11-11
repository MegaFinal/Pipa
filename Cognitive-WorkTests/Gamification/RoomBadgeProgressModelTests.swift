//
//  RoomBadgeProgressModelTests.swift
//  Cognitive-WorkTests
//
//  Created by Jonas Melo on 11/11/26.
//

import Testing
import Foundation
import CloudKit
@testable import Cognitive_Work

/// Checks how ``RoomBadgeProgressModel`` counts check-offs and unlocks badges.
struct RoomBadgeProgressModelTests {

    private let today = "2026-11-11"

    private func checkOffs(_ count: Int, in room: DefaultRoomsOnboarding) -> [RoomBadgeChange] {
        Array(repeating: RoomBadgeChange(room: room, delta: 1), count: count)
    }

    @Test func unlocksExactlyAtTheThreshold() {
        var progress = RoomBadgeProgressModel(ownerRecordName: "alice")

        let before = progress.apply(checkOffs(24, in: .kitchen), dayKey: today)
        #expect(before.isEmpty)

        let reached = progress.apply(checkOffs(1, in: .kitchen), dayKey: today)
        #expect(reached == [.torreDeLouca])
        #expect(progress.count(for: .kitchen) == 25)
        #expect(progress.nextBadge(in: .kitchen) == .panoDePratoDaVo)
    }

    @Test func oneBigChangeCanUnlockSeveralBadges() {
        var progress = RoomBadgeProgressModel(ownerRecordName: "alice")

        let unlocked = progress.apply([RoomBadgeChange(room: .garage, delta: 8)], dayKey: today)

        #expect(unlocked == [.quartinhoDaBagunca, .bikeDeRodinha])
    }

    @Test func uncheckingNeverTakesABadgeBack() {
        var progress = RoomBadgeProgressModel(ownerRecordName: "alice")
        progress.apply(checkOffs(2, in: .garage), dayKey: today)

        progress.apply([RoomBadgeChange(room: .garage, delta: -1)], dayKey: today)

        #expect(progress.count(for: .garage) == 1)
        #expect(progress.isUnlocked(.quartinhoDaBagunca))
    }

    @Test func reachingTheThresholdAgainDoesNotUnlockTwice() {
        var progress = RoomBadgeProgressModel(ownerRecordName: "alice")
        progress.apply(checkOffs(2, in: .garage), dayKey: today)
        progress.apply([RoomBadgeChange(room: .garage, delta: -1)], dayKey: today)

        let again = progress.apply(checkOffs(1, in: .garage), dayKey: today)

        #expect(again.isEmpty)
        #expect(progress.unlocked == [RoomBadge.quartinhoDaBagunca.rawValue])
    }

    @Test func countsNeverGoBelowZero() {
        var progress = RoomBadgeProgressModel(ownerRecordName: "alice")

        progress.apply([RoomBadgeChange(room: .pantry, delta: -3)], dayKey: today)

        #expect(progress.count(for: .pantry) == 0)
    }

    @Test func roomsCountSeparately() {
        var progress = RoomBadgeProgressModel(ownerRecordName: "alice")

        progress.apply(checkOffs(5, in: .pantry) + checkOffs(4, in: .laundryRoom), dayKey: today)

        #expect(progress.isUnlocked(.paoMofado))
        #expect(!progress.isUnlocked(.meiaSemPar))
    }

    @Test func oneOffCountsStartOverEveryDay() {
        var progress = RoomBadgeProgressModel(ownerRecordName: "alice")
        progress.apply([RoomBadgeChange(room: .kitchen, delta: 2, isOneOff: true)], dayKey: today)
        #expect(progress.oneOffCount(for: .kitchen, on: today) == 2)

        progress.apply([RoomBadgeChange(room: .kitchen, delta: 1, isOneOff: true)], dayKey: "2026-11-12")

        #expect(progress.oneOffCount(for: .kitchen, on: "2026-11-12") == 1)
        #expect(progress.oneOffCount(for: .kitchen, on: today) == 0)
        #expect(progress.count(for: .kitchen) == 3)
    }

    @Test func survivesARoundTripThroughARecord() {
        var progress = RoomBadgeProgressModel(ownerRecordName: "alice")
        progress.apply(checkOffs(7, in: .bathroom) + [RoomBadgeChange(room: .garden, delta: 1, isOneOff: true)], dayKey: today)
        let record = CKRecord(recordType: RoomBadgeProgressModel.recordType)

        progress.populate(record: record)
        let decoded = RoomBadgeProgressModel(record: record)

        #expect(decoded?.counts == progress.counts)
        #expect(decoded?.unlocked == progress.unlocked)
        #expect(decoded?.oneOffDay == today)
        #expect(decoded?.oneOffCounts == progress.oneOffCounts)
    }

    @Test func dayKeyIsTheCalendarDay() {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 23))!
        #expect(RoomBadgeProgressModel.dayKey(for: date) == "2026-03-07")
    }
}
