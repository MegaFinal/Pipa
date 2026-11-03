//
//  GlobalFunctions.swift
//  Cognitive-Work
//

import Foundation
import CloudKit

// MARK: - Context Construction

/// Builds the scheduling context containing user available times, capacities, and responsible maps.
///
/// - Parameters:
///   - users: An array of ``UserModel`` instances representing the household members.
///   - chores: An array of ``ChoreModel`` instances to evaluate.
///   - now: The start date of the scheduling period (today).
///   - windowEnd: The end date of the scheduling period (14 days later).
/// - Returns: A ``ScheduleContext`` instance containing aggregated scheduling metadata.
func buildScheduleContext(
    users: [UserModel],
    chores: [ChoreModel],
    now: Date,
    windowEnd: Date
) async -> ScheduleContext {
    
    var userAvailableTimeMap: [CKRecord.ID: [AvailableTimeModel]] = [:]
    var userTotalCapacity: [CKRecord.ID: Int] = [:]
    
    // Collect all user time request references into a single array
    var allTimeRefs: [CKRecord.Reference] = []
    for user in users {
        if let refs = user.availableTimeReference {
            allTimeRefs.append(contentsOf: refs)
        }
    }
    
    // Perform only 1 network request outside the for loop
    let allFetchedSlots = await CloudKitManager.shared.fetchRecordsByRecordReference(
        for: AvailableTimeModel.self,
        recordReferences: allTimeRefs
    ) ?? []
    
    for user in users {
        guard let userID = user.recordID, let refs = user.availableTimeReference else { continue }
        
        // Extract all record IDs belonging to this user
        let userRefIDs = Set(refs.map { $0.recordID })
        
        // Filter records belonging to this user from the main pool fetched in the single request
        let slots = allFetchedSlots.filter { slot in
            guard let slotID = slot.recordID else { return false }
            return userRefIDs.contains(slotID)
        }
        
        let validSlots = slots.filter { slot in
            let day = Calendar.current.startOfDay(for: slot.day)
            return day >= now && day <= windowEnd
        }
        
        userAvailableTimeMap[userID] = validSlots
        userTotalCapacity[userID] = validSlots.reduce(0) { $0 + $1.capacityMinutes }
    }
    
    var choreResponsibleMap: [CKRecord.ID: UserModel] = [:]
    
    // Additional optimization: Chores whose users are not found locally would traditionally trigger individual awaits in the loop
    var missingUserRefs = Set<CKRecord.Reference>()
    // We can similarly batch these requests
    var missingChores: [ChoreModel] = []
    
    for chore in chores {
        guard let ref = chore.currentResponsibleReference, let choreID = chore.recordID else { continue }
        
        if let local = users.first(where: { $0.recordID == ref.recordID }) {
            choreResponsibleMap[choreID] = local
        } else {
            missingUserRefs.insert(ref)
            missingChores.append(chore)
        }
    }
    
    // If there are missing users, fetch them all using a single request
    if !missingUserRefs.isEmpty {
        let fetchedUsers = await CloudKitManager.shared.fetchRecordsByRecordReference(
            for: UserModel.self,
            recordReferences: Array(missingUserRefs)
        ) ?? []
        
        // Populate the map in memory
        for chore in missingChores {
            guard let ref = chore.currentResponsibleReference, let choreID = chore.recordID else { continue }
            if let found = fetchedUsers.first(where: { $0.recordID == ref.recordID }) {
                choreResponsibleMap[choreID] = found
            }
        }
    }
    
    let minimumCapacity = userTotalCapacity.values.min() ?? 0
    
    return ScheduleContext(
        userAvailableTimeMap: userAvailableTimeMap,
        choreResponsibleMap: choreResponsibleMap,
        userTotalCapacity: userTotalCapacity,
        minimumCapacity: minimumCapacity
    )
}

// MARK: - Recurring Chores

/// Helper function to determine which day offsets a recurring frequency should appear on within the window.
func occurrenceOffsets(for frequency: Recurrence, windowDays: Int, phase: Int = 0) -> [Int] {
    let period: Int
    switch frequency {
    case .daily:       period = 1
    case .weekly:      period = 7
    case .fortnightly: period = 14
    case .monthly:     period = 14
    case .none:        return []
    case .undefined:   return []
    }
    
    let start = phase % period
    return stride(from: start, to: windowDays, by: period).map { $0 }
}

/// Schedules recurring chores across the 14-day period for appropriate users based on their frequency.
///
/// - Parameters:
///   - recurringChores: An array of recurring chores to schedule.
///   - users: An array of available household members.
///   - context: The current scheduling context.
///   - now: The start date.
///   - remainingCapacity: A mutable reference to remaining capacity per time slot.
///   - userAssignedMinutes: A mutable reference to total assigned minutes per user.
/// - Returns: An array of ``ScheduleResult`` containing the newly generated assignments.
func scheduleRecurringChores(
    _ recurringChores: [ChoreModel],
    users: [UserModel],
    context: ScheduleContext,
    now: Date,
    remainingCapacity: inout [CKRecord.ID: Double],
    userAssignedMinutes: inout [CKRecord.ID: Int],
    excludedUsersByChore: [CKRecord.ID: Set<CKRecord.ID>] = [:]
) -> [ScheduleResult] {
    
    let calendar = Calendar.current
    
    // Convert user available times into an indexed lookup structure
    var slotsByUserAndDay: [CKRecord.ID: [Date: AvailableTimeModel]] = [:]
    for (userID, slots) in context.userAvailableTimeMap {
        var dayMap: [Date: AvailableTimeModel] = [:]
        for slot in slots {
            dayMap[calendar.startOfDay(for: slot.day)] = slot
        }
        slotsByUserAndDay[userID] = dayMap
    }
    
    var results: [ScheduleResult] = []
    
    // Iterate through each recurring chore
    for chore in recurringChores {
        guard let choreID = chore.recordID else { continue }
        var result = ScheduleResult(chore: chore)
        
        // Users holding this chore's coupon are left out (see `CouponExemption`).
        let excluded = excludedUsersByChore[choreID] ?? []
        let isEligible: (UserModel) -> Bool = { user in
            user.recordID.map { !excluded.contains($0) } ?? true
        }
        let eligibleUsers = users.filter(isEligible)
        
        let targetUsers: [UserModel]
        if let assignedUserRefs = chore.allResponsibleUsersReference, !assignedUserRefs.isEmpty {
            let assignedIDs = Set(assignedUserRefs.map(\.recordID))
            let filtered = eligibleUsers.filter { $0.recordID.map { assignedIDs.contains($0) } ?? false }
            targetUsers = filtered.isEmpty ? eligibleUsers : filtered
        } else if let fixedUser = context.choreResponsibleMap[choreID], isEligible(fixedUser) {
            targetUsers = [fixedUser]
        } else {
            targetUsers = eligibleUsers
        }
        
        let phase = choreID.recordName.utf8.reduce(0) { $0 &+ Int($1) }
        
        // Calculate the date offsets where this recurring chore should occur
        for dayOffset in occurrenceOffsets(for: chore.frequency, windowDays: 14, phase: phase) {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            let dayStart = calendar.startOfDay(for: day)
            
            var chosenUser: UserModel?
            var chosenUserID: CKRecord.ID?
            var chosenSlotID: CKRecord.ID?
            var chosenRemaining: Double = 0
            var bestMinutes = Int.max
            
            // Attempt to find the most suitable, least-loaded user among the candidate pool for this day
            for user in targetUsers {
                guard let userID = user.recordID,
                      let slot = slotsByUserAndDay[userID]?[dayStart],
                      let slotID = slot.recordID else { continue }
                
                // Get the remaining capacity of this time slot (or use default capacity if no record exists)
                let remaining = remainingCapacity[slotID] ?? Double(slot.capacityMinutes)
                // Check if the remaining capacity is sufficient to support the current chore's duration
                guard remaining >= chore.duration else { continue }
                
                let assigned = userAssignedMinutes[userID] ?? 0
                
                // If the current user's assigned time is less than the current minimum record, update the best candidate
                if assigned < bestMinutes {
                    bestMinutes = assigned
                    chosenUser = user
                    chosenUserID = userID
                    chosenSlotID = slotID
                    chosenRemaining = remaining
                }
            }
            
            // If a suitable user and time slot are found, deduct capacity and bind the single chosen user
            let chosenUserRefs: [CKRecord.Reference]?
            if let finalUserID = chosenUserID, let slotID = chosenSlotID {
                remainingCapacity[slotID] = max(chosenRemaining - chore.duration, 0)
                userAssignedMinutes[finalUserID, default: 0] += Int(chore.duration)
                chosenUserRefs = [CKRecord.Reference(recordID: finalUserID, action: .none)]
            } else {
                // If no specific user is found, generate a placeholder instance with users set to nil.
                chosenUserRefs = nil
            }
            
            // Create a CloudKit reference, generate the daily assignment model, and append it to the current chore's results
            let choreRef = CKRecord.Reference(recordID: choreID, action: .deleteSelf)
            result.newAssignments.append(
                RecurrentAssignmentModel(day: day, isCompleted: false, users: chosenUserRefs, chore: choreRef)
            )
        }
        
        results.append(result)
    }
    
    return results
}

// MARK: - Recurring Chores Created Mid-Cycle

/// The days a recurring chore created mid-cycle occurs on: its creation day, then once per
/// recurrence period, up to and including `cycleEnd`.
///
/// Deliberately separate from ``occurrenceOffsets(for:windowDays:phase:)``, which lays out a
/// whole division window starting *tomorrow*, with a per-chore phase to spread chores apart.
/// A chore the user creates today is expected to start today.
///
/// - Parameters:
///   - frequency: The chore's recurrence. `.none` yields no days.
///   - start: The creation date; its day is the first occurrence.
///   - cycleEnd: The last day of the division cycle in progress.
/// - Returns: Each occurrence's day, at its start, in chronological order.
func occurrenceDays(
    for frequency: Recurrence,
    from start: Date,
    through cycleEnd: Date,
    calendar: Calendar = .current
) -> [Date] {
    let step: DateComponents
    switch frequency {
    case .daily: step = DateComponents(day: 1)
    case .weekly: step = DateComponents(day: 7)
    case .fortnightly: step = DateComponents(day: 14)
    case .monthly: step = DateComponents(month: 1)
    case .none: return []
    case .undefined: return []
    }
    
    let lastDay = calendar.startOfDay(for: cycleEnd)
    var day = calendar.startOfDay(for: start)
    var days: [Date] = []
    
    while day <= lastDay {
        days.append(day)
        guard let next = calendar.date(byAdding: step, to: day) else { break }
        day = calendar.startOfDay(for: next)
    }
    
    return days
}

/// Creates the occurrences of a recurring chore the user just created, for what's left of the
/// division cycle already in progress.
///
/// Without this, a recurring chore created between divisions has no occurrences until the next
/// division runs, so it shows up as a single card instead of one per recurrence.
///
/// - Parameters:
///   - chore: The newly created chore. Must already be saved (have a `recordID`) and have no
///     occurrences yet; otherwise nothing happens.
///   - responsibleUsers: The users picked in the creation form; all of them are assigned to
///     every occurrence.
///   - cycleEnd: The last day of the division cycle in progress, or `nil` when none is.
func scheduleNewRecurringChore(
    _ chore: ChoreModel,
    responsibleUsers: [UserModel],
    cycleEnd: Date?,
    pickedDate: Date? = nil
) async {
    guard let cycleEnd,
          chore.frequency != .none,
          !chore.isDone,
          let choreID = chore.recordID,
          (chore.dailyAssignmentsReference ?? []).isEmpty
            else { return }
    
    let start = pickedDate ?? Date()
    let days = occurrenceDays(for: chore.frequency, from: start, through: cycleEnd)
    guard !days.isEmpty else { return }
    
    // Every occurrence is shared by all the users picked in the form, unlike the division,
    // which gives each occurrence to a single user.
    let userRefs = responsibleUsers.compactMap { user in
        user.recordID.map { CKRecord.Reference(recordID: $0, action: .none) }
    }
    // Same reference action the division uses for an occurrence's chore.
    let choreRef = CKRecord.Reference(recordID: choreID, action: .deleteSelf)
    
    let assignments = days.map { day in
        RecurrentAssignmentModel(
            day: day,
            isCompleted: false,
            users: userRefs.isEmpty ? nil : userRefs,
            chore: choreRef
        )
    }
    
    // The chore was created in the house's zone, so its zone is the one the division uses.
    await commitScheduleResults(
        [ScheduleResult(chore: chore, newAssignments: assignments)],
        users: responsibleUsers,
        houseZoneID: choreID.zoneID
    )
}

// MARK: - Assigned Chores

/// Schedules chores that already have a specific responsible user assigned.
///
/// - Parameters:
///   - assignedChores: An array of chores with predetermined assignees.
///   - context: The scheduling context.
///   - now: The start date.
///   - windowEnd: The end date.
///   - remainingCapacity: Mutable slot capacity dictionary.
///   - userAssignedMinutes: Mutable user assigned minutes dictionary.
/// - Returns: An array of ``ScheduleResult``.
func scheduleAssignedChores(
    _ assignedChores: [ChoreModel],
    context: ScheduleContext,
    now: Date,
    windowEnd: Date,
    remainingCapacity: inout [CKRecord.ID: Double],
    userAssignedMinutes: inout [CKRecord.ID: Int]
) -> [ScheduleResult] {
    
    let calendar = Calendar.current
    
    // Unified preprocessing: Convert user available times into a [UserID: [StartOfDay: TimeSlot]] structure
    var slotsByUserAndDay: [CKRecord.ID: [Date: AvailableTimeModel]] = [:]
    for (userID, slots) in context.userAvailableTimeMap {
        var dayMap: [Date: AvailableTimeModel] = [:]
        for slot in slots {
            dayMap[calendar.startOfDay(for: slot.day)] = slot
        }
        slotsByUserAndDay[userID] = dayMap
    }
    
    var results: [ScheduleResult] = []
    
    // Iterate through each chore with a designated responsible person
    for chore in assignedChores {
        guard let choreID = chore.recordID,
              let user = context.choreResponsibleMap[choreID],
              let userID = user.recordID else { continue }
        
        let updatable = chore
        
        // If the user has no time slot records at all, clear the due date and skip
        guard let dayMap = slotsByUserAndDay[userID] else {
            updatable.dueDate = nil
            results.append(ScheduleResult(chore: updatable))
            continue
        }
        
        // Find time slots within the window that meet capacity requirements and have the earliest date in the preprocessed dictionary
        let validOptions = dayMap.compactMap { dayStart, slot -> (day: Date, slot: AvailableTimeModel, remaining: Double)? in
            guard dayStart >= now && dayStart < windowEnd,
                  let slotID = slot.recordID else { return nil }
            
            let remaining = remainingCapacity[slotID] ?? Double(slot.capacityMinutes)
            guard remaining >= chore.duration else { return nil }
            
            return (dayStart, slot, remaining)
        }
        
        // Select the earliest day among them
        if let chosen = validOptions.min(by: { $0.day < $1.day }),
           let slotID = chosen.slot.recordID {
            
            updatable.dueDate = chosen.slot.day
            
            // Deduct capacity and accumulate user's assigned duration
            remainingCapacity[slotID] = chosen.remaining - chore.duration
            userAssignedMinutes[userID, default: 0] += Int(chore.duration)
        } else {
            // No suitable time slot available, clear the due date
            updatable.dueDate = nil
        }
        
        results.append(ScheduleResult(chore: updatable))
    }
    
    return results
}

// MARK: - Free Chores

/// Automatically assigns and schedules chores that do not have a pre-assigned responsible user.
///
/// - Parameters:
///   - freeChores: An array of unassigned chores.
///   - users: All available household users.
///   - context: The scheduling context.
///   - now: The start date.
///   - windowEnd: The end date.
///   - remainingCapacity: Mutable slot capacity dictionary.
///   - userAssignedMinutes: Mutable user assigned minutes dictionary.
/// - Returns: An array of ``ScheduleResult``.
func scheduleFreeChores(
    _ freeChores: [ChoreModel],
    users: [UserModel],
    context: ScheduleContext,
    now: Date,
    windowEnd: Date,
    remainingCapacity: inout [CKRecord.ID: Double],
    userAssignedMinutes: inout [CKRecord.ID: Int],
    excludedUsersByChore: [CKRecord.ID: Set<CKRecord.ID>] = [:]
) -> [ScheduleResult] {
    
    let calendar = Calendar.current
    
    // Reuse preprocessing: Convert user available times into a [UserID: [StartOfDay: TimeSlot]] structure to avoid redundant calculations of startOfDay
    var slotsByUserAndDay: [CKRecord.ID: [Date: AvailableTimeModel]] = [:]
    for (userID, slots) in context.userAvailableTimeMap {
        var dayMap: [Date: AvailableTimeModel] = [:]
        for slot in slots {
            dayMap[calendar.startOfDay(for: slot.day)] = slot
        }
        slotsByUserAndDay[userID] = dayMap
    }
    
    var results: [ScheduleResult] = []
    
    // Iterate through each unassigned free chore
    for chore in freeChores {
        let updatable = chore
        
        // The candidate pool is divided into two tiers: baseline (preferred users below the minimum capacity limit) and fallback (all available users)
        // We use two variables to record their respective "optimal solutions" while accomplishing it in a single iteration
        var bestBaseline: (user: UserModel, slot: AvailableTimeModel, remaining: Double, assigned: Int)? = nil
        var bestFallback: (user: UserModel, slot: AvailableTimeModel, remaining: Double, assigned: Int)? = nil
        
        // Users holding this chore's coupon are left out (see `CouponExemption`).
        let excluded = chore.recordID.flatMap { excludedUsersByChore[$0] } ?? []
        
        // Iterate through all users and their preprocessed time slots (single pass, filtering and finding the optimal simultaneously)
        for user in users {
            guard let userID = user.recordID,
                  !excluded.contains(userID),
                  let dayMap = slotsByUserAndDay[userID] else { continue }
            
            let assigned = userAssignedMinutes[userID] ?? 0
            let isBaseline = Double(assigned) + chore.duration < Double(context.minimumCapacity)
            
            // Iterate through all available time slots of this user within the window period
            for (dayStart, slot) in dayMap {
                guard dayStart >= now && dayStart < windowEnd,
                      let slotID = slot.recordID else { continue }
                
                let remaining = remainingCapacity[slotID] ?? Double(slot.capacityMinutes)
                guard remaining >= chore.duration else { continue }
                
                let candidate = (user: user, slot: slot, remaining: remaining, assigned: assigned)
                
                if isBaseline {
                    // Update the optimal solution for the baseline group (logic: prioritize fewer assigned minutes, secondarily earlier slot.day)
                    if let currentBest = bestBaseline {
                        if candidate.assigned < currentBest.assigned ||
                            (candidate.assigned == currentBest.assigned && candidate.slot.day < currentBest.slot.day) {
                            bestBaseline = candidate
                        }
                    } else {
                        bestBaseline = candidate
                    }
                } else {
                    // Update the optimal solution for the fallback group
                    if let currentBest = bestFallback {
                        if candidate.assigned < currentBest.assigned ||
                            (candidate.assigned == currentBest.assigned && candidate.slot.day < currentBest.slot.day) {
                            bestFallback = candidate
                        }
                    } else {
                        bestFallback = candidate
                    }
                }
            }
        }
        
        // Prioritize the optimal solution from the baseline group; if empty, fallback to the fallback group
        guard let chosen = bestBaseline ?? bestFallback,
              let chosenUserID = chosen.user.recordID,
              let slotID = chosen.slot.recordID else {
            // If completely lacking a suitable time slot, clear the responsible person and due date
            updatable.currentResponsibleReference = nil
            updatable.dueDate = nil
            results.append(ScheduleResult(chore: updatable))
            continue
        }
        
        // Set the selected user as the current responsible person for the chore
        updatable.currentResponsibleReference = CKRecord.Reference(
            recordID: chosenUserID,
            action: CKRecord.ReferenceAction.none
        )
        
        // Update the historical rotation responsible list, ensuring no duplicate additions
        var rotation = updatable.allResponsibleUsersReference ?? []
        if !rotation.contains(where: { $0.recordID == chosenUserID }) {
            rotation.append(CKRecord.Reference(recordID: chosenUserID, action: CKRecord.ReferenceAction.none))
        }
        updatable.allResponsibleUsersReference = rotation
        
        // Set the chore's due date
        updatable.dueDate = chosen.slot.day
        
        // Deduct time slot capacity and accumulate the user's assigned minutes
        remainingCapacity[slotID] = chosen.remaining - chore.duration
        userAssignedMinutes[chosenUserID, default: 0] += Int(chore.duration)
        
        results.append(ScheduleResult(chore: updatable))
    }
    
    return results
}

// MARK: - Repair

/// Clears stale ``ChoreModel/dailyAssignmentsReference`` lists left behind by the zone bug
/// fixed in ``commitScheduleResults(_:users:houseZoneID:)``: before that fix, whichever
/// device ran the scheduler first saved the `DailyAssignmentModel` records into its own
/// private zone instead of the house's, so nobody else — including the house owner — could
/// ever read them back.
///
/// Because ``TaskSchedulerEngine/schedule(chores:users:)`` only reschedules a recurring
/// chore whose reference list is empty, a chore stuck pointing at unreadable records would
/// otherwise never be rescheduled again. This checks whether the referenced records are
/// actually readable and, if none of them are, clears the list so the caller's own
/// `recurringChores` filter picks the chore back up this run.
///
/// - Parameter chores: Every chore currently loaded, as passed into ``TaskSchedulerEngine/schedule(chores:users:)``.
func repairOrphanedRecurringAssignments(in chores: [ChoreModel]) async {
    let recurringFrequencies: Set<Recurrence> = [.daily, .weekly, .fortnightly, .monthly]
    
    // Filter candidate chores
    let candidates = chores.filter {
        !$0.isDone &&
        recurringFrequencies.contains($0.frequency) &&
        !($0.dailyAssignmentsReference ?? []).isEmpty
    }
    
    await withTaskGroup(of: Void.self) { group in
        for chore in candidates {
            // Before entering the background task, extract the required reference data on the main thread first
            let refs = chore.dailyAssignmentsReference ?? []
            
            group.addTask {
                // Verify in the cloud concurrently in the background
                let resolved = await CloudKitManager.shared.fetchRecordsByRecordReference(
                    for: RecurrentAssignmentModel.self,
                    recordReferences: refs
                )
                
                guard let resolved, resolved.isEmpty else { return }
                
                // If properties on the main thread need to be modified, switch back to MainActor to execute
                await MainActor.run {
                    chore.dailyAssignmentsReference = nil
                }
                await CloudKitManager.shared.update(chore)
            }
        }
    }
}

// MARK: - Persistence

/// Commits all schedule results by saving them to CloudKit and updating user relationships.
///
/// - Parameters:
///   - results: An array of ``ScheduleResult`` to commit.
///   - users: An array of ``UserModel`` to update.
///   - houseZoneID: The house's actual record zone, so the new `DailyAssignmentModel`
///     records land where every housemate (owner included) can read them, rather than in
///     whichever device happens to run this. `nil` falls back to the old, zone-unsafe
///     behavior if the house couldn't be resolved.
func commitScheduleResults(_ results: [ScheduleResult], users: [UserModel], houseZoneID: CKRecordZone.ID?) async {
    // Validate the Record Zone to prevent data from falling back to the default private zone, which breaks multi-device sharing.
    guard let zoneID = houseZoneID else { return }
    
    var recordsToSave: [CKRecord] = []
    var choresByUser: [CKRecord.ID: [CKRecord.Reference]] = [:]
    
    for result in results {
        guard let choreID = result.chore.recordID else { continue }
        var savedRefs: [CKRecord.Reference] = []
        for assignment in result.newAssignments {
            let recordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID)
            let record = CKRecord(recordType: RecurrentAssignmentModel.recordType, recordID: recordID)
            assignment.populate(record: record)
            
            // Set the CloudKit Parent reference to establish a parent-child hierarchy between Chore and DailyAssignment.
            record.parent = CKRecord.Reference(recordID: choreID, action: .none)
            recordsToSave.append(record)
            savedRefs.append(CKRecord.Reference(recordID: recordID, action: .none))
            
            if let assignedRefs = assignment.userReferences {
                for ref in assignedRefs {
                    choresByUser[ref.recordID, default: []].append(CKRecord.Reference(recordID: choreID, action: .none))
                }
            }
        }
        if !savedRefs.isEmpty {
            result.chore.dailyAssignmentsReference = (result.chore.dailyAssignmentsReference ?? []) + savedRefs
        }
    }
    
    if !recordsToSave.isEmpty {
        await CloudKitManager.shared.batchSave(records: recordsToSave, zoneID: zoneID)
    }
    
    let choresToUpdate = results.map { $0.chore }
    var usersToUpdate: [UserModel] = []
    for user in users {
        guard let userID = user.recordID,
              let newRefs = choresByUser[userID],
              !newRefs.isEmpty else { continue }
        let existingRefs = user.choresReference ?? []
        let existingIDs = Set(existingRefs.map { $0.recordID })
        
        // Deduplicate chore references to filter out items the user already has, preventing redundant data.
        let dedupedNewRefs = newRefs.filter { !existingIDs.contains($0.recordID) }
        guard !dedupedNewRefs.isEmpty else { continue }
        user.choresReference = existingRefs + dedupedNewRefs
        usersToUpdate.append(user)
    }
    
    // Use async let to concurrently update Chores and Users, improving network efficiency.
    async let choresDone: Bool = {
        let r = await CloudKitManager.shared.batchUpdate(choresToUpdate)
        return r
    }()
    
    async let usersDone: Bool = {
        let r = await CloudKitManager.shared.batchUpdate(usersToUpdate)
        return r
    }()
    _ = await (choresDone, usersDone)
}


// MARK: - Reset Before Re-Division

/// Clears the schedule from tomorrow on so the division starts from scratch; today is left untouched.
/// Recurring chores are reopened, pending one-off chores lose their date, and completed
/// one-off chores are deleted (except today's).
///
/// - Parameter chores: Every chore currently loaded.
@MainActor
func resetUpcomingSchedule(for chores: [ChoreModel]) async {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return }
    
    var recordsToDelete: [CKRecord.ID] = []
    var zoneID: CKRecordZone.ID?
    var choresToUpdate: [ChoreModel] = []
    var choresToDelete: [ChoreModel] = []
    
    for chore in chores {
        
        // Completed one-off chores are deleted on a new division; today's stay until the next one.
        if chore.frequency == .none, chore.isDone
        {
            choresToDelete.append(chore)
            continue
        }
        
        var changed = false
        
        // Every chore enters the new division, so none stays done besides .none recurrence.
        if chore.isDone && chore.frequency != .none {
            chore.isDone = false
            chore.userThatHaveDoneReference = nil
            changed = true
        }
        
        if let refs = chore.dailyAssignmentsReference, !refs.isEmpty {
            let existing = await chore.dailyAssignments
            let removeIDs = existing.filter { $0.day >= tomorrow }.compactMap(\.recordID)
            
            if !removeIDs.isEmpty {
                if zoneID == nil { zoneID = removeIDs.first?.zoneID }
                recordsToDelete.append(contentsOf: removeIDs)
                
                let removedSet = Set(removeIDs)
                chore.dailyAssignmentsReference = refs.filter { !removedSet.contains($0.recordID) }
                changed = true
            }
        }
        else if chore.frequency == .none, !chore.isDone, let dueDate = chore.dueDate, !calendar.isDateInToday(dueDate) {            chore.dueDate = nil
            changed = true
        }
        
        if changed { choresToUpdate.append(chore) }
    }
    
    if !recordsToDelete.isEmpty, let zoneID {
        await CloudKitManager.shared.delete(recordIDs: recordsToDelete, zoneID: zoneID)
    }
    
    if !choresToUpdate.isEmpty {
        await CloudKitManager.shared.batchUpdate(choresToUpdate)
    }
    
    for chore in choresToDelete {
        await chore.delete()
    }
}
