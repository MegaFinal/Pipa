//
//  MyScheduleViewModel.swift
//  Cognitive-Work
//
//  Created by Carolina Sun on 02/10/26.
//

import Foundation
import SwiftUI
import CloudKit

/// A view model that exposes only the current user's share of the house schedule.
///
/// It composes a ``FortnightlyViewModel`` instead of duplicating its logic: the house view
/// model builds every ``DailyUsageEntry``, and this type narrows them down to the ones that
/// belong to ``currentUser``.
@Observable
final class CurrentScheduleViewModel {
    
    // MARK: - Dependencies
    
    /// Builds the usage entries for the whole house; reused so the logic lives in one place.
    private let houseViewModel = FortnightlyViewModel()
    
    // MARK: - State
    
    /// The signed-in resident whose schedule is displayed.
    private(set) var currentUser: UserModel?
    
    /// `true` until ``setup(users:chores:assignments:rooms:me:)`` finishes.
    private(set) var isLoading = true
    
    // MARK: - Exposed data
    
    /// Entries assigned to ``currentUser``, ordered by day.
    var myEntries: [DailyUsageEntry] {
        // Compared by record name so a different zone ID can't make the match fail
        guard let myName = currentUser?.recordID?.recordName else { return [] }
        return houseViewModel.usageEntries
            .filter { $0.userID.recordName == myName }
            .sorted { $0.day < $1.day }
    }
    /// First day of the fortnightly cycle.
    var startDate: Date { houseViewModel.startDate }
    
    /// Total minutes the user has scheduled in the cycle.
    var totalMinutes: Double {
        myEntries.reduce(0) { $0 + $1.minutes }
    }
    
    /// The distinct rooms that appear in ``myEntries``, in order of first appearance.
    ///
    /// Used to build the legend, so it never lists rooms the user has no chores in.
    var roomsInUse: [RoomModel] {
        var seen = Set<CKRecord.ID>()
        var result: [RoomModel] = []
        
        for entry in myEntries {
            guard let chore = chore(for: entry),
                  let room = room(for: chore),
                  let roomID = room.recordID,
                  seen.insert(roomID).inserted
            else { continue }
            result.append(room)
        }
        return result
    }
    
    // MARK: - Setup
    
    /// Loads the schedule and resolves who the current user is.
    ///
    /// - Parameters:
    ///   - users: Every resident of the house.
    ///   - chores: Every chore of the house.
    ///   - assignments: Assignments already in memory. When both `assignments` and `rooms`
    ///     are provided, CloudKit is not queried again.
    ///   - rooms: Rooms already in memory.
    ///   - me: The current user, if the caller already knows it. Otherwise it is fetched
    ///     with `CloudKitManager.fetchMyHouseUser()`.
    func setup(
        users: [UserModel],
        chores: [ChoreModel],
        assignments: [RecurrentAssignmentModel]? = nil,
        rooms: [RoomModel]? = nil,
        me: UserModel? = nil
    ) async {
        if let me {
            currentUser = me
        } else {
            // Adjust to the real signature of `fetchMyHouseUser()`.
            currentUser = await CloudKitManager.shared.fetchMyHouseUser()
        }
        
        if let assignments, let rooms {
            await houseViewModel.setup(users: users, chores: chores,
                                       assignments: assignments, rooms: rooms)
        } else {
            await houseViewModel.setup(users: users, chores: chores)
        }
        
        isLoading = false
    }
    
    /// Loads everything from CloudKit, for call sites that have no data in memory.
    ///
    /// - Parameter me: The current user, if already known. Otherwise it is fetched with
    ///   `CloudKitManager.fetchMyHouseUser()`.
    func setupWithFetch(me: UserModel? = nil) async {
        if let me {
            currentUser = me
        } else {
            currentUser = await CloudKitManager.shared.fetchMyHouseUser()
        }
        
        await houseViewModel.setupWithFetch()
        isLoading = false
    }
    
    // MARK: - Lookups
    
    /// Returns the chore an entry refers to.
    func chore(for entry: DailyUsageEntry) -> ChoreModel? {
        houseViewModel.chores.first { $0.recordID == entry.choreID }
    }
    
    /// Returns the room a chore belongs to.
    func room(for chore: ChoreModel) -> RoomModel? {
        houseViewModel.getRoom(for: chore)
    }
}
