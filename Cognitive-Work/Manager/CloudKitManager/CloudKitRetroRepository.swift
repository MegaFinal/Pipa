//
//  CloudKitRetroRepository.swift
//  Cognitive-Work
//
//  Production `RetroRepository`: reads what the retrospective needs from CloudKit and maps it to
//  plain value types, so the view model never touches CKRecord or the models.
//

import Foundation
import CloudKit

/// Reads the retrospective's data from CloudKit (see the file header).
@MainActor
struct CloudKitRetroRepository: RetroRepository {

    /// The signed-in member's work in `period`, the house's rooms and whether they can start a
    /// new division.
    /// - Throws: ``RetroError/userNotFound`` when the member's profile in the house can't be found.
    func fetchSnapshot(for period: RetroPeriod) async throws -> RetroSnapshot {
        let manager = CloudKitManager.shared

        async let fetchUser = manager.fetchMyHouseUser()
        async let fetchChores = manager.fetchAll(ChoreModel.self)
        async let fetchAssignments = manager.fetchAll(RecurrentAssignmentModel.self)
        async let fetchRooms = manager.fetchAll(RoomModel.self)

        let (user, chores, assignments, rooms) = await (fetchUser, fetchChores, fetchAssignments, fetchRooms)
        try Task.checkCancellation()

        guard let user, let userID = user.recordID else { throw RetroError.userNotFound }

        let choresByID = Dictionary(
            chores.compactMap { chore in chore.recordID.map { ($0, chore) } },
            uniquingKeysWith: { first, _ in first }
        )

        // 1. Recurring chores: the user's daily assignments inside the period.
        let assignmentItems: [RetroWorkItem] = assignments.compactMap { assignment in
            guard let id = assignment.recordID,
                  period.contains(assignment.day),
                  (assignment.userReferences ?? []).contains(where: { $0.recordID == userID })
            else { return nil }
            let roomID = assignment.choreReference
                .flatMap { choresByID[$0.recordID] }?
                .roomReference?.recordID.recordName
            return RetroWorkItem(id: id.recordName, day: assignment.day,
                                 isCompleted: assignment.isCompleted, roomID: roomID)
        }

        // 2. One-off chores (no daily assignments) owned by the user, due inside the period.
        let oneOffItems: [RetroWorkItem] = chores.compactMap { chore in
            guard chore.dailyAssignmentsReference?.isEmpty ?? true,
                  chore.currentResponsibleReference?.recordID == userID,
                  let id = chore.recordID,
                  let due = chore.dueDate,
                  period.contains(due)
            else { return nil }
            return RetroWorkItem(id: id.recordName, day: due, isCompleted: chore.isDone,
                                 roomID: chore.roomReference?.recordID.recordName)
        }

        let retroRooms: [RetroRoom] = rooms.compactMap { room in
            room.recordID.map { RetroRoom(id: $0.recordName, name: room.name, color: room.color) }
        }

        // Same admin check as the rest of the app. If the house can't be read, the user is
        // treated as a resident (no new-division prompt).
        let house = try? await manager.currentHouse()
        let isHouseAdmin = await house?.isAdmin() == true

        // Same rule as the automatic pop-up: the last scheduled day is in the past.
        let isDivisionOver = RetroTriggerPolicy.isDivisionOver(
            lastScheduledDay: assignments.map(\.day).max(),
            now: .now
        )

        return RetroSnapshot(
            items: assignmentItems + oneOffItems,
            rooms: retroRooms,
            isHouseAdmin: isHouseAdmin,
            isDivisionOver: isDivisionOver
        )
    }
}
