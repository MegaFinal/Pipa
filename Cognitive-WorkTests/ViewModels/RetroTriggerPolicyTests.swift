//
//  RetroTriggerPolicyTests.swift
//  Cognitive-WorkTests
//

import Testing
import Foundation
@testable import Cognitive_Work

struct RetroTriggerPolicyTests {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }
    private func day(_ offset: Int) -> Date {
        let base = Date(timeIntervalSince1970: 1_790_000_000)
        return calendar.date(byAdding: .day, value: offset, to: base)!
    }
    private var now: Date { day(0) }

    @Test func neverDividedShowsNothing() {
        #expect(!RetroTriggerPolicy.shouldPresent(lastScheduledDay: nil, lastPresentedDay: nil, now: now, calendar: calendar))
    }

    @Test func periodStillRunningShowsNothing() {
        #expect(!RetroTriggerPolicy.shouldPresent(lastScheduledDay: day(3), lastPresentedDay: nil, now: now, calendar: calendar))
    }

    @Test func lastDayOfThePeriodStillShowsNothing() {
        #expect(!RetroTriggerPolicy.shouldPresent(lastScheduledDay: day(0), lastPresentedDay: nil, now: now, calendar: calendar))
    }

    @Test func dayAfterThePeriodShowsRetro() {
        #expect(RetroTriggerPolicy.shouldPresent(lastScheduledDay: day(-1), lastPresentedDay: nil, now: now, calendar: calendar))
    }

    @Test func showsAtMostOncePerDay() {
        #expect(!RetroTriggerPolicy.shouldPresent(lastScheduledDay: day(-5), lastPresentedDay: now, now: now, calendar: calendar))
        #expect(RetroTriggerPolicy.shouldPresent(lastScheduledDay: day(-5), lastPresentedDay: day(-1), now: now, calendar: calendar))
    }

    // MARK: - isDivisionOver (whether the retrospective may offer a new division)

    @Test func divisionRunningIsNotOver() {
        // An old retrospective opened while the next cycle runs: no new division.
        #expect(!RetroTriggerPolicy.isDivisionOver(lastScheduledDay: day(10), now: now, calendar: calendar))
        #expect(!RetroTriggerPolicy.isDivisionOver(lastScheduledDay: day(0), now: now, calendar: calendar))
    }

    @Test func divisionIsOverTheDayAfterItsLastDay() {
        #expect(RetroTriggerPolicy.isDivisionOver(lastScheduledDay: day(-1), now: now, calendar: calendar))
    }

    @Test func neverDividedIsNotOver() {
        #expect(!RetroTriggerPolicy.isDivisionOver(lastScheduledDay: nil, now: now, calendar: calendar))
    }
}
