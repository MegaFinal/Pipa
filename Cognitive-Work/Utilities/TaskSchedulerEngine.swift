//
//  TaskSchedulerEngine.swift
//  Cognitive-Work
//

import Foundation
import CloudKit

// MARK: - Engine
/// Generates the division of chores: who does what, on which day, for the next 15 days.
///
/// Respects each member's free time and the coupons bought in the cycle, and records the new
/// cycle (``HouseCycleModel``) once the division is saved.
struct TaskSchedulerEngine {
    
    /// Schedules unassigned and recurring chores for all given users within a 14-day horizon.
    ///
    /// This method performs the following key steps:
    /// 1. Filters out recurring chores that have already been scheduled to prevent duplicate entries.
    /// 2. Sorts remaining non-recurring chores by their normalized weight.
    /// 3. Distributes tasks among assigned and free chores accordingly.
    /// 4. Commits the final generated schedule results.
    ///
    /// - Parameters:
    ///   - chores: An array of ``ChoreModel`` instances representing all tasks to evaluate.
    ///   - users: An array of ``UserModel`` instances representing available household members.
    static func schedule(chores: [ChoreModel], users: [UserModel]) async {
        // Return immediately if the user list is empty, without performing any scheduling
        guard !users.isEmpty else { return }
        
        // Get the start time of the tomorrow (00:00:00)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let now = calendar.date(byAdding: .day, value: 1, to: today) else { return }
        // Calculate the date 14 days from today; return if it fails
        guard let windowEnd = calendar.date(byAdding: .day, value: 15, to: now) else { return }
        
        // `DailyAssignmentModel` records must live in the house's own zone, never in
        // whichever device happens to run this first — otherwise anyone who isn't that
        // device (the owner included) can end up unable to read them back. Resolve the
        // real house zone once, up front, and thread it through to `commitScheduleResults`.
        // houseZoneID is independent of chores/users, so initiate it early to run concurrently with the next two steps
        async let houseTask = CloudKitManager.shared.fetchFirst(HouseModel.self)
        
        // Coupon holders are spared their chore in this division (see `CouponExemption`).
        // Must be read before this run records its own cycle below.
        let newCycleKey = HouseCycleModel.key(for: now)
        async let couponsTask = Self.loadCouponsToApply(newCycleKey: newCycleKey)
        
        // Chores scheduled before the fix above may still be pointing at daily-assignment
        // records that live in the wrong zone and are now unreadable. Clear those stale
        // references so they're picked up by the `recurringChores` filter below and
        // rescheduled correctly this run.
        // repair must precede buildScheduleContext (as it modifies chore.dailyAssignmentsReference,
        // which the subsequent recurringChores filter relies on), so these two steps remain sequential
        await repairOrphanedRecurringAssignments(in: chores)
        
        // Build the scheduling context to calculate environment variables such as user available time, capacity, etc.
        let context = await buildScheduleContext(
            users: users,
            chores: chores,
            now: now,
            windowEnd: windowEnd
        )
        // houseZoneID's result is only truly needed here (used by commitScheduleResults), by which time it is most likely ready
        let house = try? await houseTask
        let houseZoneID = house?.recordID?.zoneID
        let appliedCoupons = await couponsTask
        let exemptions = CouponExemption.exemptions(from: appliedCoupons)
        
        // Define the set of recurring frequencies
        let recurringFrequencies: Set<Recurrence> = [.daily, .weekly, .fortnightly, .monthly]
        
        // Filter out recurring chores that need to be scheduled
        // Condition: not done, recurring frequency, and do not yet have generated daily assignment records
        let recurringChores = chores.filter {
            recurringFrequencies.contains($0.frequency) && $0.shouldBeIncluded != false
        }
        
        // Monthly chores that wont be done now, but need to be done next 14 days
        let monthyChoresNotToDo = chores.filter { $0.frequency == .monthly && $0.shouldBeIncluded == false }
        
        for chore in recurringChores where chore.frequency == .monthly {
            chore.shouldBeIncluded?.toggle()
        }
        
        // Filter all unfinished chores with no set due date, excluding monthly tasks from this window
        let unassignedChores = chores.filter { !$0.isDone && $0.dueDate == nil && $0.frequency != .monthly}
        
        // Exclude recurring frequency chores from the above list, keeping only common non-recurring chores
        let nonRecurringChores = unassignedChores.filter { !recurringFrequencies.contains($0.frequency) }
        
        // Sort chores in descending order by weight, higher weights go to the top for priority scheduling
        let sortedChores = nonRecurringChores.sorted { normalizedWeight(chore: $0) > normalizedWeight(chore: $1) }
        
        // Divide the sorted chores into two categories:
        // - Chores that already have a specific assigned responsible user
        // A chore whose fixed responsible holds its coupon is handed to someone else this time,
        // so it is scheduled as a free chore.
        let isSparedResponsible: (ChoreModel) -> Bool = { chore in
            guard let choreID = chore.recordID,
                  let responsibleID = chore.currentResponsibleReference?.recordID
            else { return false }
            return exemptions[choreID]?.contains(responsibleID) ?? false
        }
        let assignedChores = sortedChores.filter { $0.currentResponsibleReference != nil && !isSparedResponsible($0) }
        // - "Free" chores without a defined responsible person, requiring automatic system assignment
        let freeChores = sortedChores.filter { $0.currentResponsibleReference == nil || isSparedResponsible($0) }
        
        // Initialize remaining capacity and minutes already assigned to each user
        var remainingCapacity = context.initialRemainingCapacity()
        var userAssignedMinutes = context.initialUserAssignedMinutes(users: users)
        
        // Store all generated scheduling results
        var allResults: [ScheduleResult] = []
        
        // Schedule all recurring chores
        allResults += scheduleRecurringChores(
            recurringChores,
            users: users,
            context: context,
            now: now,
            remainingCapacity: &remainingCapacity,
            userAssignedMinutes: &userAssignedMinutes,
            excludedUsersByChore: exemptions
        )

        // Schedule chores that already have a specific responsible user
        allResults += scheduleAssignedChores(
            assignedChores,
            context: context,
            now: now,
            windowEnd: windowEnd,
            remainingCapacity: &remainingCapacity,
            userAssignedMinutes: &userAssignedMinutes
        )

        // Schedule free chores
        allResults += scheduleFreeChores(
            freeChores,
            users: users,
            context: context,
            now: now,
            windowEnd: windowEnd,
            remainingCapacity: &remainingCapacity,
            userAssignedMinutes: &userAssignedMinutes,
            excludedUsersByChore: exemptions
        )
        
        // Commit and save the final schedule results to the cloud
        await commitScheduleResults(allResults, users: users, houseZoneID: houseZoneID)
        
        // Record the cycle this division covers: `now` through the last day of the window.
        if let houseID = house?.recordID,
           let lastDay = calendar.date(byAdding: .day, value: -1, to: windowEnd) {
            let recorded = await HouseCycleModel.recordNewDivision(start: now, end: lastDay, houseID: houseID)
            // The coupons this division applied are used up: they can be bought again.
            if recorded {
                await CouponExemption.consume(appliedCoupons, inCycle: newCycleKey)
            }
        }
        
        // toogle shouldBeIncluded chores so they can be included on the next 14 days and persists on cloudkit
        await withTaskGroup(of: Void.self) { group in
            for chore in monthyChoresNotToDo {
                chore.shouldBeIncluded?.toggle()
                group.addTask {
                    await CloudKitManager.shared.update(chore)
                }
            }
        }
    }
    
    // MARK: - Coupons
    
    /// Coupons the division about to be generated applies; empty when there is no house yet.
    private static func loadCouponsToApply(newCycleKey: String) async -> [CouponModel] {
        guard let zoneID = try? await CloudKitManager.shared.currentHouse()?.recordID?.zoneID else {
            return []
        }
        let (coupons, cycles) = await CouponExemption.load(houseZoneID: zoneID)
        return CouponExemption.toApply(coupons: coupons, cycles: cycles, newCycleKey: newCycleKey)
    }
    
    // MARK: - Prioritization
    
    /// Calculates a combined normalized weight used to sort chores.
    ///
    /// The final weight is a weighted average: **70% priority** and **30% duration**.
    ///
    /// - Parameter chore: The ``ChoreModel`` to evaluate.
    /// - Returns: A `Double` value between `0.0` and `1.0`.
    static func normalizedWeight(chore: ChoreModel) -> Double {
        let priorityNormalized = normalization(
            value: Double(chore.priorityTag.intValue),
            min: Double(PriorityTag.low.intValue),
            max: Double(PriorityTag.urgent.intValue)
        )
        
        let timeNormalized = normalization(
            value: chore.duration,
            min: 1 * 60,
            max: 8 * 60
        )
        
        return (priorityNormalized * 0.7) + (timeNormalized * 0.3)
    }
    
    /// Normalizes a given numeric value into the range of `0...1`.
    ///
    /// - Parameters:
    ///   - value: The actual numeric value to normalize.
    ///   - minValue: The lower bound limit.
    ///   - maxValue: The upper bound limit.
    /// - Returns: A clamped `Double` between `0` and `1`.
    static func normalization(value: Double, min minValue: Double, max maxValue: Double) -> Double {
        guard maxValue != minValue else { return 0 }
        
        let normalized = (value - minValue) / (maxValue - minValue)
        
        return Swift.min(Swift.max(normalized, 0), 1)
    }
}
