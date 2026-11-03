//
//  HardwareDailyChoresViewModel.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 17/09/26.
//

import Foundation
import CloudKit

/// A single house member's chores for the dashboard's target day, together with their share of
/// that day's total workload.
struct UserDailyChoresGroup: Identifiable {
    /// The member.
    var user: UserModel

    /// This user's chores due on the target day, in display order.
    var chores: [ChoreModel]

    /// This user's share of every chore due on the target day across the whole house,
    /// from `0.0` to `1.0`.
    var shareOfDay: Double

    /// Identifier for SwiftUI lists (the member's ID).
    var id: String { user.id }

    /// ``shareOfDay`` formatted (e.g. `"45%"`).
    var shareOfDayFormatted: String {
        ChartA11y.percent(shareOfDay)
    }
}

/// Loads a single day's chores for every member of the house and groups them by responsible
/// user, for the daily chores dashboard (``HardwareDailyChoresView``).
@Observable
class HardwareDailyChoresViewModel {

    // MARK: - Target Day

    /// How many days ahead of today the dashboard renders.
    /// > Note: `1` (tomorrow) is intentional and matches what the device shows today, because
    /// > the scheduler seeds its 14-day window starting tomorrow
    /// > (see ``TaskSchedulerEngine/schedule(chores:users:)``), so "today" is empty on a freshly
    /// > generated division. Set this to `0` to ship the real "Tarefas do Dia".
    static let dayOffsetFromToday = 0

    /// The day the dashboard renders: ``dayOffsetFromToday`` days after `reference`, normalised
    /// to the start of that day.
    ///
    /// - Parameter reference: The day to count from. Defaults to now; injectable for tests.
    static func targetDay(from reference: Date = Date()) -> Date {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: reference)
        return calendar.date(byAdding: .day, value: dayOffsetFromToday, to: startOfToday)
            ?? startOfToday
    }

    // MARK: - Core Data

    /// Every chore of the house.
    private var allChores: [ChoreModel] = []
    /// Every room of the house.
    private var roomModels: [RoomModel] = []
    /// Every chore occurrence of the house.
    private var dailyAssignments: [RecurrentAssignmentModel] = []

    // MARK: - Display Data

    /// Every house member's chores due on the target day.
    private(set) var userGroups: [UserDailyChoresGroup] = []

    /// Every room referenced by the target day's chores, for the color legend.
    private(set) var roomsInUse: [RoomModel] = []

    /// The rendered day, formatted for the header in the app's language
    /// ("quinta-feira, 1 de outubro" / "Thursday, October 1").
    var targetDateFormatted: String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter.string(from: Self.targetDay())
    }

    // MARK: - Initialization
    /// Creates the view model with data already loaded (or empty, to load later).
    init(
        chores: [ChoreModel] = [],
        users: [UserModel] = [],
        rooms: [RoomModel] = [],
        assignments: [RecurrentAssignmentModel] = []
    ) {
        self.allChores = chores
        self.roomModels = rooms
        self.dailyAssignments = assignments
        rebuildUserGroups(for: users)
    }

    // MARK: - Data Fetching

    /// Fetches every chore, room, house member, and daily assignment from CloudKit, then
    /// rebuilds ``userGroups`` and ``roomsInUse``.
    func setup() async {
        async let fetchChores = CloudKitManager.shared.fetchAll(ChoreModel.self)
        async let fetchUsers = CloudKitManager.shared.fetchHouseUsers()
        async let fetchRoom = CloudKitManager.shared.fetchAll(RoomModel.self)
        async let fetchAssignment = CloudKitManager.shared.fetchAll(RecurrentAssignmentModel.self)

        let (chores, users, rooms, assignments) = await (fetchChores, fetchUsers, fetchRoom, fetchAssignment)
        
        let filteredChores = chores.filter{ $0.isDone == false }
        let filteredAssignments = assignments.filter { $0.isCompleted == false }
    
        self.allChores = filteredChores
        self.roomModels = rooms
        self.dailyAssignments = filteredAssignments

        rebuildUserGroups(for: users)
    }

    // MARK: - Grouping & Statistics

    /// Rebuilds ``userGroups`` and ``roomsInUse`` from ``allChores``/``dailyAssignments`` for the
    /// given house members.
    private func rebuildUserGroups(for users: [UserModel]) {
        let targetDay = Self.targetDay()

        let assignmentsByID = Dictionary(
            dailyAssignments.compactMap { assignment in
                assignment.recordID.map { ($0, assignment) }
            },
            uniquingKeysWith: { _, latest in latest }
        )

        let dayRows: [(chore: ChoreModel, responsibleID: CKRecord.ID)] = allChores.flatMap { chore in
            responsibleUserIDs(for: chore, on: targetDay, assignmentsByID: assignmentsByID)
                .map { (chore: chore, responsibleID: $0) }
        }

        let totalChoresOnDay = dayRows.count

        self.userGroups = users.map { user in
            let choresForUser = dayRows
                .filter { $0.responsibleID == user.recordID }
                .map { $0.chore }

            let share = totalChoresOnDay > 0
                ? Double(choresForUser.count) / Double(totalChoresOnDay)
                : 0.0

            return UserDailyChoresGroup(user: user, chores: choresForUser, shareOfDay: share)
        }
        .sorted { $0.user.name < $1.user.name }

        let roomIDsInUse = Set(dayRows.compactMap { $0.chore.roomReference?.recordID })
        self.roomsInUse = roomModels.filter { room in
            guard let roomID = room.recordID else { return false }
            return roomIDsInUse.contains(roomID)
        }
    }

    /// Everyone responsible for `chore` on `day`, or an empty array when the chore isn't due
    /// then or has nobody assigned.
    ///
    /// - Parameters:
    ///   - chore: The chore to evaluate.
    ///   - day: The day the dashboard is rendering. Named `day`, not `today`: the previous name
    ///     is what made the hardcoded `isDateInToday` above read as correct.
    ///   - assignmentsByID: Every known assignment, keyed by its own record ID.
    /// - Returns: The responsible users' record IDs, in reference order, without duplicates.
    private func responsibleUserIDs(
        for chore: ChoreModel,
        on day: Date,
        assignmentsByID: [CKRecord.ID: RecurrentAssignmentModel]
    ) -> [CKRecord.ID] {
        let calendar = Calendar.current

        if let refs = chore.dailyAssignmentsReference, !refs.isEmpty {
            var seen: Set<CKRecord.ID> = []
            var responsibleIDs: [CKRecord.ID] = []

            for ref in refs {
                guard let assignment = assignmentsByID[ref.recordID],
                      calendar.isDate(assignment.day, inSameDayAs: day),
                      let userRefs = assignment.userReferences else { continue }

                for userRef in userRefs {
                    let userID = userRef.recordID
                    if seen.insert(userID).inserted {
                        responsibleIDs.append(userID)
                    }
                }
            }

            return responsibleIDs
        }

        guard let dueDate = chore.dueDate,
              calendar.isDate(dueDate, inSameDayAs: day)
        else {
            return []
        }

        var seen: Set<CKRecord.ID> = []
        let candidates = [chore.currentResponsibleReference].compactMap { $0 }
            + (chore.allResponsibleUsersReference ?? [])
        return candidates.map(\.recordID).filter { seen.insert($0).inserted }
    }

    // MARK: - Helpers

    /// The room a chore belongs to
    func room(for chore: ChoreModel) -> RoomModel? {
        guard let roomID = chore.roomReference?.recordID else { return nil }
        return roomModels.first { $0.recordID == roomID }
    }
}
