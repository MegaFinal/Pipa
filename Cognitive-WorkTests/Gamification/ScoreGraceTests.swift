//
//  ScoreGraceTests.swift
//  Cognitive-WorkTests
//
//  Created by Jonas Melo on 11/11/26.
//

import Testing
import Foundation
@testable import Cognitive_Work

/// Checks ``ScoreManager/isWithinGrace(_:dueOn:completedAt:calendar:)``, shared by the points
/// and the room badges.
@MainActor
struct ScoreGraceTests {

    private let manager = ScoreManager(store: InMemoryAtomicRecordStore())
    private let due = GamificationFixture.day(2026, 11, 20)

    private func chore(_ frequency: Recurrence) -> ChoreModel {
        ChoreModel(name: "chore", description: "", frequency: frequency, duration: 15, isPublic: true, priorityTag: .medium)
    }

    @Test func dailyChoreIsOnTimeOnlyOnItsDay() {
        #expect(manager.isWithinGrace(chore(.daily), dueOn: due, completedAt: due))
        #expect(!manager.isWithinGrace(chore(.daily), dueOn: due, completedAt: GamificationFixture.day(2026, 11, 19)))
    }

    @Test func weeklyChoreIsOnTimeAnyDayOfItsWeek() {
        #expect(manager.isWithinGrace(chore(.weekly), dueOn: due, completedAt: GamificationFixture.day(2026, 11, 14)))
        #expect(!manager.isWithinGrace(chore(.weekly), dueOn: due, completedAt: GamificationFixture.day(2026, 11, 13)))
    }

    @Test func lateIsOnTime() {
        #expect(manager.isWithinGrace(chore(.daily), dueOn: due, completedAt: GamificationFixture.day(2026, 11, 25)))
    }

    @Test func choreWithoutDueDateIsAlwaysOnTime() {
        #expect(manager.isWithinGrace(chore(.none), dueOn: nil))
    }
}
