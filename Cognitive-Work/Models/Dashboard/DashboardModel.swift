//
//  DashboardModel.swift
//  Cognitive-Work
//
//  Created by Isabela Hissa Pinto on 28/08/26.
//

import Foundation
import SwiftUI
import CloudKit

/// Today's progress of one member: their chores for today, how many are left and how much time
/// they still need. Shown in the progress cards.
///
/// Works only on chores and occurrences the caller already fetched (no CloudKit requests).
@Observable
class DashboardModel: Identifiable {

    /// The member this progress is about.
    var user: UserModel
    /// Every chore the member has today, done or not.
    var todayChores: [ChoreModel] = []

    /// Today's chores that are still pending.
    var toDoList: [ChoreModel] = []

    // MARK: - Formatted Data

    /// The number of pending chores.
    var toDo: Int = 0

    /// Time still needed for today's pending chores (e.g. `"1h30"`). Goes down as chores are
    /// marked done and back up when they're undone.
    var totalTimeFormatted: String = "0h00"

    /// The fraction, from `0.0` to `1.0`, of today's chores that are marked as done.
    var completionPercentage: Double = 0.0

    /// ``completionPercentage`` as text, formatted for the app's language (e.g. `"75%"`).
    var completionPercentageString: String = "0%"

    /// Creates an empty progress for `user`. Call ``setup(chores:assignments:)`` to fill it.
    init(user: UserModel) {
        self.user = user
    }

    /// Recomputes every statistic for today's chores assigned to ``user``, out of `chores`
    /// and `assignments` the caller already has in memory (no CloudKit request here).
    ///
    /// - Parameters:
    ///   - chores: Every chore, e.g. ``CarouselViewModel/cardModels``.
    ///   - assignments: Every recurrent assignment, e.g. ``CarouselViewModel/dailyAssignments``.
    func setup(chores: [ChoreModel], assignments: [RecurrentAssignmentModel]) {
        guard let targetUserID = user.recordID else { return }

        let calendar = Calendar.current
        // The same day the grid shows — tomorrow while the schedule is being tested — so the
        // progress cards count the chores the user actually sees. Follows
        // ``CarouselViewModel/gridDayOffsetFromToday``; set that back to `0` and this goes
        // back to today with it.
        let today = CarouselViewModel.gridTargetDay()

        // Keyed by assignment recordID (not just a Set) so `isDoneToday(_:)` below can read
        // back each assignment's own `isCompleted`, not just whether it exists.
        var myAssignmentsToday: [CKRecord.ID: RecurrentAssignmentModel] = [:]
        var allAssignmentsToday: [CKRecord.ID: RecurrentAssignmentModel] = [:]
        for assignment in assignments {
            guard let assignmentID = assignment.recordID,
                  calendar.isDate(assignment.day, inSameDayAs: today)
            else { continue }
            allAssignmentsToday[assignmentID] = assignment
            
            let isAssignedToMe = (assignment.userReferences ?? []).contains { $0.recordID == targetUserID }
            if isAssignedToMe {
                myAssignmentsToday[assignmentID] = assignment
            }
        }
        
        /// Responsible for the chore even when the rotation gave today to someone else — the
        /// carousel shows these too, so the progress cards must count them as well.
        func isResponsible(_ chore: ChoreModel) -> Bool {
            chore.currentResponsibleReference?.recordID == targetUserID
            || (chore.allResponsibleUsersReference ?? []).contains { $0.recordID == targetUserID }
        }

        let filtered = chores.filter { chore in
            if let refs = chore.dailyAssignmentsReference, !refs.isEmpty {
                if refs.contains(where: { myAssignmentsToday[$0.recordID] != nil }) { return true }
                return isResponsible(chore) && refs.contains { allAssignmentsToday[$0.recordID] != nil }
            } else {
                guard let dueDate = chore.dueDate,
                      calendar.isDate(dueDate, inSameDayAs: today)
                else { return false }
                
                let isCurrentResponsible = chore.currentResponsibleReference?.recordID == targetUserID
                let isInRotation = (chore.allResponsibleUsersReference ?? []).contains { $0.recordID == targetUserID }
                return isCurrentResponsible || isInRotation
            }
        }
        self.todayChores = filtered

        func isDoneToday(_ chore: ChoreModel) -> Bool {
            guard let refs = chore.dailyAssignmentsReference, !refs.isEmpty else {
                return chore.isDone
            }
            // My own occurrence when it's my turn; otherwise the day's occurrence(s) of a chore
            // I'm responsible for.
            var todaysAssignments = refs.compactMap { myAssignmentsToday[$0.recordID] }
            if todaysAssignments.isEmpty {
                todaysAssignments = refs.compactMap { allAssignmentsToday[$0.recordID] }
            }
            guard !todaysAssignments.isEmpty else { return chore.isDone }
            return todaysAssignments.allSatisfy { $0.isCompleted }
        }

        self.toDoList = todayChores.filter { !isDoneToday($0) }

        calculateStatistics(isDoneToday: isDoneToday)
    }

    /// Recomputes ``toDo``, ``totalTimeFormatted``,
    /// ``completionPercentage`` and ``completionPercentageString`` from
    /// ``todayChores`` and ``toDoList``.
    ///
    /// - Parameter isDoneToday: Same predicate ``setup(chores:assignments:)`` used to build
    ///   ``toDoList``, so the completion count and ``toDoList`` never disagree about a chore.
    private func calculateStatistics(isDoneToday: (ChoreModel) -> Bool) {
        self.toDo = toDoList.count

        guard !todayChores.isEmpty else {
            self.totalTimeFormatted = "0h00"
            self.completionPercentage = 0
            self.completionPercentageString = "0%"
            return
        }

        let totalMinutes = toDoList.reduce(into: 0.0) { total, chore in
            total += chore.duration
        }

        let hours = Int(totalMinutes / 60)
        let minutes = Int(totalMinutes.truncatingRemainder(dividingBy: 60.0))
        self.totalTimeFormatted = "\(hours)h\(String(format: "%02d", minutes))"

        let completedChoresCount = todayChores.filter { isDoneToday($0) }.count

        self.completionPercentage = Double(completedChoresCount) / Double(todayChores.count)
        self.completionPercentageString = completionPercentage.formatted(
            .percent.precision(.fractionLength(0)).locale(L10n.locale)
        )
    }
}
