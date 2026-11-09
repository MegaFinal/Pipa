//
//  HouseCycleModelTests.swift
//  Cognitive-WorkTests
//
//  Created by Jonas Melo on 16/10/26.
//

import Testing
import Foundation
@testable import Cognitive_Work

@MainActor
struct HouseCycleModelTests {

    typealias F = GamificationFixture

    @Test func keyIsTheStartDay() {
        #expect(F.cycle(start: F.day(2026, 10, 2)).key == "2026-10-02")
    }

    @Test func closesTheDayAfterItsLastDay() {
        let cycle = F.cycle(start: F.day(2026, 10, 2)) // 2 → 16 Oct
        #expect(!cycle.isClosed(asOf: F.day(2026, 10, 16)))
        #expect(cycle.isClosed(asOf: F.day(2026, 10, 17)))
    }

    @Test func newDivisionAfterTheEndKeepsPreviousCycle() {
        let old = F.cycle(start: F.day(2026, 10, 2))
        let toSave = HouseCycleModel.cyclesToSave(newStart: F.day(2026, 10, 18), newEnd: F.day(2026, 11, 1), existing: [old])
        #expect(toSave.map(\.key) == ["2026-10-18"])
    }

    @Test func newDivisionMidCycleCutsTheRunningCycleShort() {
        let old = F.cycle(start: F.day(2026, 10, 2))
        let toSave = HouseCycleModel.cyclesToSave(newStart: F.day(2026, 10, 9), newEnd: F.day(2026, 10, 23), existing: [old])
        #expect(toSave.count == 2)
        #expect(toSave[0].key == "2026-10-02")
        #expect(toSave[0].endDate == F.day(2026, 10, 8))
        #expect(toSave[1].key == "2026-10-09")
    }

    @Test func regeneratingOnTheSameDayRewritesTheSameCycle() {
        let old = F.cycle(start: F.day(2026, 10, 2))
        let toSave = HouseCycleModel.cyclesToSave(newStart: F.day(2026, 10, 2), newEnd: F.day(2026, 10, 16), existing: [old])
        #expect(toSave.map(\.key) == ["2026-10-02"])
    }

    @Test func latestPreviousAndClosed() {
        let a = F.cycle(start: F.day(2026, 9, 17))
        let b = F.cycle(start: F.day(2026, 10, 2))
        let c = F.cycle(start: F.day(2026, 10, 17))
        #expect(HouseCycleModel.latest([b, c, a])?.key == c.key)
        #expect(HouseCycleModel.previous([b, c, a])?.key == b.key)
        #expect(HouseCycleModel.closed([c, a, b], asOf: F.day(2026, 10, 20)).map(\.key) == [a.key, b.key])
    }

    // MARK: - Redoing the division

    @Test func redoingTheDivisionMarksTheCycleAsCutShort() {
        let old = F.cycle(start: F.day(2026, 10, 2))
        let toSave = HouseCycleModel.cyclesToSave(newStart: F.day(2026, 10, 9), newEnd: F.day(2026, 10, 23), existing: [old])

        #expect(toSave[0].isCutShort())
        #expect(!toSave[1].isCutShort())
        #expect(!old.isCutShort())
    }

    @Test func cyclesCutBeforeTheFlagExistedAreRecognizedByTheirLength() {
        let short = F.cycle(start: F.day(2026, 10, 2), days: 6)
        #expect(short.wasCutShort == nil)
        #expect(short.isCutShort())
    }

    @Test func seasonStartsAfterTheLastCycleThatRanItsCourse() {
        let full = F.cycle(start: F.day(2026, 9, 17))
        var cut = F.cycle(start: F.day(2026, 10, 2), days: 4)
        cut.wasCutShort = true
        let current = F.cycle(start: F.day(2026, 10, 7))

        // The cut cycle doesn't end the season: it began the day after the full one ended.
        let start = HouseCycleModel.currentSeasonStart([full, cut, current], asOf: F.day(2026, 10, 10))
        #expect(start == F.day(2026, 10, 2))
        #expect(HouseCycleModel.currentSeasonStart([current], asOf: F.day(2026, 10, 10)) == nil)
    }
}
