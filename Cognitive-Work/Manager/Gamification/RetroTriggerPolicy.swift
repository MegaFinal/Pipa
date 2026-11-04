//
//  RetroTriggerPolicy.swift
//  Cognitive-Work
//
//  Decides when the retrospective should be offered to the user.
//

import Foundation

/// The retrospective is offered once the period of the last division is over.
enum RetroTriggerPolicy {

    /// Whether the last division's period is over: only on the day after its last day.
    /// `false` when nothing was ever divided. Also decides if the retrospective may offer a new
    /// division (an old retrospective, opened while the current cycle runs, must not).
    static func isDivisionOver(
        lastScheduledDay: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard let lastScheduledDay else { return false }
        return calendar.startOfDay(for: lastScheduledDay) < calendar.startOfDay(for: now)
    }

    /// - Parameters:
    ///   - lastScheduledDay: The latest day that has an assignment in the house (the end of the last
    ///     division). `nil` when nothing was ever divided, so there is nothing to look back on.
    ///   - lastPresentedDay: The day the retrospective was last shown, to offer it at most once a day.
    ///   - now: Current date.
    static func shouldPresent(
        lastScheduledDay: Date?,
        lastPresentedDay: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard isDivisionOver(lastScheduledDay: lastScheduledDay, now: now, calendar: calendar) else {
            return false
        }

        if let lastPresentedDay, calendar.isDate(lastPresentedDay, inSameDayAs: now) {
            return false
        }
        return true
    }
}
