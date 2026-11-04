//
//  ScheduleContext.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 20/08/26.
//

import CloudKit

// MARK: - Support Models

/// A context structure that encapsulates all necessary metadata and maps for the scheduling algorithm.
struct ScheduleContext {
    
    /// A dictionary mapping each user's record ID to their array of available time slot models.
    let userAvailableTimeMap: [CKRecord.ID: [AvailableTimeModel]]
    
    /// A dictionary mapping each chore's record ID to its corresponding responsible user model.
    let choreResponsibleMap: [CKRecord.ID: UserModel]
    
    /// A dictionary mapping each user's record ID to their total available capacity in minutes.
    let userTotalCapacity: [CKRecord.ID: Int]
    
    /// The minimum total capacity found among all users, used as a baseline for workload balancing.
    let minimumCapacity: Int

    /// Generates and returns an initial mapping of remaining capacity for every time slot.
    ///
    /// - Returns: A dictionary with time slot record IDs as keys and their capacity in minutes as double values.
    func initialRemainingCapacity() -> [CKRecord.ID: Double] {
        // Initialize an empty dictionary to store the mapping from time slot ID to remaining capacity
        var map: [CKRecord.ID: Double] = [:]
        // Iterate through all users' available time slot lists
        for (_, slots) in userAvailableTimeMap {
            // Iterate through all time slots for the current user
            for slot in slots {
                // Ensure the current time slot's recordID exists, otherwise skip
                guard let id = slot.recordID else { continue }
                // Convert the time slot's capacity to a Double and store it in the dictionary
                map[id] = Double(slot.capacityMinutes)
            }
        }
        // Return the fully initialized capacity mapping dictionary
        return map
    }

    /// Generates and returns an initial tracking dictionary of assigned minutes for all users, defaulting to zero.
    ///
    /// - Parameter users: An array of ``UserModel`` to initialize tracking for.
    /// - Returns: A dictionary with user record IDs as keys and an initial assigned value of 0.
    func initialUserAssignedMinutes(users: [UserModel]) -> [CKRecord.ID: Int] {
        // Use Swift's Dictionary initializer to convert the user array into a [UserID: Initial Assigned Minutes] dictionary
        Dictionary(uniqueKeysWithValues: users.compactMap { user -> (CKRecord.ID, Int)? in
            // Ensure the user's recordID exists, otherwise return nil and get filtered out by compactMap
            guard let id = user.recordID else { return nil }
            // Return a key-value tuple where each user's initial assigned time is 0 minutes
            return (id, 0)
        })
    }
}

/// A structure representing the outcome of scheduling a specific chore, including updated models and new assignments.
struct ScheduleResult {
    
    /// The updated chore model containing modified due dates, current responsible references, or rotation lists.
    var chore: ChoreModel
    
    /// An array of newly generated daily assignment models associated with this chore.
    var newAssignments: [RecurrentAssignmentModel] = []
}
