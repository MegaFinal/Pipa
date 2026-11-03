//
//  FortnightlyScheduleViewModel.swift
//  Cognitive-Work
//
//  Created by Carolina Sun on 28/08/26.
//

import Foundation
import CloudKit
import SwiftUI

/// Loads (and, when asked, generates) the division of chores shown on the schedule screen.
@Observable
@MainActor

final class ScheduleViewModel {    
    /// The house members.
    var users: [UserModel] = []
    /// Every chore of the house.
    var chores: [ChoreModel] = []
    /// An error to show, or `nil`.
    var errorMessage: String?
    /// `true` while loading or generating.
    var isLoading = true
    
    /// Assignments and rooms handed in up front; `nil` means ``FortnightlyView`` fetches them.
    private(set) var assignments: [RecurrentAssignmentModel]?
    /// The house's rooms, when handed in up front.
    private(set) var rooms: [RoomModel]?
    
    /// Whether the data was handed in up front, in which case nothing is fetched or generated.
    private let isPreloaded: Bool
    
    /// Chores known to exist that a query may not return yet (e.g. created by the onboarding
    /// a moment ago). They're read by ID, which is immediately consistent.
    private let knownChoreIDs: [CKRecord.ID]
    
    /// - Parameter knownChoreIDs: Chores just saved that must be part of the division even if
    ///   CloudKit's query index hasn't caught up with them yet.
    init(knownChoreIDs: [CKRecord.ID] = []) {
        self.isPreloaded = false
        self.knownChoreIDs = knownChoreIDs
    }
    
    /// Starts with data already in memory and never touches CloudKit (e.g. SwiftUI previews).
    init(
        users: [UserModel],
        chores: [ChoreModel],
        assignments: [RecurrentAssignmentModel],
        rooms: [RoomModel]
    ) {
        self.users = users
        self.chores = chores
        self.assignments = assignments
        self.rooms = rooms
        self.isLoading = false
        self.isPreloaded = true
        self.knownChoreIDs = []
    }
    
    /// Fetches the members and chores, including the chores known by ID.
    private func setup() async {
        async let fetchUsers = CloudKitManager.shared.fetchHouseUsers()
        async let fetchChores = CloudKitManager.shared.fetchAll(ChoreModel.self)
        async let fetchKnownChores = fetchKnownChoresByID()
        
        self.users = await fetchUsers
        self.chores = Self.merge(queried: await fetchChores, fetchedByID: await fetchKnownChores)
    }
    
    /// Reads ``knownChoreIDs`` directly by record ID.
    private func fetchKnownChoresByID() async -> [ChoreModel] {
        guard !knownChoreIDs.isEmpty else { return [] }
        let references = knownChoreIDs.map { CKRecord.Reference(recordID: $0, action: .none) }
        return await CloudKitManager.shared.fetchRecordsByRecordReference(
            for: ChoreModel.self,
            recordReferences: references
        ) ?? []
    }
    
    /// Query results plus the chores read by ID. When both have a chore, the one read by ID
    /// wins: it is the latest version (a lagging index can also return an older copy, e.g.
    /// without the occurrences the scheduler just added).
    private static func merge(queried: [ChoreModel], fetchedByID: [ChoreModel]) -> [ChoreModel] {
        guard !fetchedByID.isEmpty else { return queried }
        let fetchedIDs = Set(fetchedByID.compactMap(\.recordID))
        return queried.filter { chore in
            guard let recordID = chore.recordID else { return true }
            return !fetchedIDs.contains(recordID)
        } + fetchedByID
    }
    
    /// Clears the upcoming schedule and generates a new division. Does nothing with preloaded data.
    func generateSchedule() async {
        guard !isPreloaded else { return }
        isLoading = true
        await setup()
        await resetUpcomingSchedule(for: chores)
        await TaskSchedulerEngine.schedule(chores: chores, users: users)
        isLoading = false
    }
    
    /// Loads the schedule, generating a new division first when `shouldGenerate` is `true`.
    /// Does nothing with preloaded data.
    func loadSchedule(shouldGenerate: Bool) async {
        guard !isPreloaded else { return }
        isLoading = true

        if shouldGenerate {
            await setup()

            await resetUpcomingSchedule(for: chores)

            await TaskSchedulerEngine.schedule(
                chores: chores,
                users: users
            )

            // TODO: implement notification for users when its done loading?
            NotificationCenter.default.post(
                name: .cloudKitDidChange,
                object: nil
            )
        }

        await setup()
        
        isLoading = false
    }
}
