//
//  AlgorithmTests.swift
//  Cognitive-Work
//

import Testing
import Foundation
import CloudKit
@testable import Cognitive_Work

/// Exercises the pure scheduling building blocks used by ``TaskSchedulerEngine``
/// (``scheduleRecurringChores``, ``scheduleAssignedChores``, ``scheduleFreeChores``,
/// ``occurrenceOffsets(for:windowDays:phase:)`` and ``occurrenceDays(for:from:through:calendar:)``)
/// directly, with hand-built fixtures instead of live CloudKit records. None of these
/// functions perform network I/O, so the tests are deterministic and fast, unlike a
/// full `TaskSchedulerEngine.schedule(chores:users:)` run, which needs a real `HouseModel`
/// record to resolve a zone before it persists anything.
@MainActor
struct AlgorithmTests {

    // MARK: - Fixtures

    private func makeUser(_ name: String, recordName: String) -> UserModel {
        UserModel(
            name: name,
            tier: .tier1,
            recordID: CKRecord.ID(recordName: recordName),
            ownerRecordName: "owner"
        )
    }

    private func makeChore(
        recordName: String,
        frequency: Recurrence,
        duration: Double,
        currentResponsible: CKRecord.Reference? = nil,
        allResponsibleUsers: [CKRecord.Reference]? = nil
    ) -> ChoreModel {
        let chore = ChoreModel(
            name: "chore-\(recordName)",
            description: "desc",
            frequency: frequency,
            duration: duration,
            isPublic: true,
            priorityTag: .medium,
            currentResponsible: currentResponsible,
            allResponsibleUsers: allResponsibleUsers
        )
        chore.recordID = CKRecord.ID(recordName: recordName)
        return chore
    }

    private func makeSlot(day: Date, capacityMinutes: Int, recordName: String) -> AvailableTimeModel {
        var slot = AvailableTimeModel(capacityMinutes: capacityMinutes, day: day)
        slot.recordID = CKRecord.ID(recordName: recordName)
        return slot
    }

    private func reference(_ id: CKRecord.ID) -> CKRecord.Reference {
        CKRecord.Reference(recordID: id, action: .none)
    }

    private func dayOffset(_ offset: Int, from base: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: offset, to: base)!
    }

    // MARK: - scheduleRecurringChores

    @Test func recurringChoresAlternateBetweenEquallyLoadedUsers() {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date())

        let alice = makeUser("Alice", recordName: "alice-alt")
        let bob = makeUser("Bob", recordName: "bob-alt")

        var aliceSlots: [AvailableTimeModel] = []
        var bobSlots: [AvailableTimeModel] = []
        for offset in 0..<14 {
            let day = dayOffset(offset, from: now, calendar: calendar)
            aliceSlots.append(makeSlot(day: day, capacityMinutes: 100, recordName: "alice-alt-slot-\(offset)"))
            bobSlots.append(makeSlot(day: day, capacityMinutes: 100, recordName: "bob-alt-slot-\(offset)"))
        }

        let context = ScheduleContext(
            userAvailableTimeMap: [alice.recordID!: aliceSlots, bob.recordID!: bobSlots],
            choreResponsibleMap: [:],
            userTotalCapacity: [alice.recordID!: 1400, bob.recordID!: 1400],
            minimumCapacity: 1400
        )

        let chore = makeChore(recordName: "daily-alt", frequency: .daily, duration: 10)

        var remaining = context.initialRemainingCapacity()
        var assigned = context.initialUserAssignedMinutes(users: [alice, bob])

        let results = scheduleRecurringChores(
            [chore],
            users: [alice, bob],
            context: context,
            now: now,
            remainingCapacity: &remaining,
            userAssignedMinutes: &assigned
        )

        #expect(results.count == 1)
        let assignments = results[0].newAssignments
        #expect(assignments.count == 14)

        for (index, assignment) in assignments.enumerated() {
            let expected = index % 2 == 0 ? alice.recordID : bob.recordID
            #expect(assignment.userReferences?.first?.recordID == expected)
        }
    }

    @Test func recurringChoreLeavesOccurrenceUnassignedWhenNoUserHasCapacity() {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date())

        let alice = makeUser("Alice", recordName: "alice-nocap")
        let bob = makeUser("Bob", recordName: "bob-nocap")

        var slots: [CKRecord.ID: [AvailableTimeModel]] = [:]
        for (user, prefix) in [(alice, "alice"), (bob, "bob")] {
            slots[user.recordID!] = (0..<14).map { offset in
                makeSlot(day: dayOffset(offset, from: now, calendar: calendar), capacityMinutes: 5, recordName: "\(prefix)-nocap-\(offset)")
            }
        }

        let context = ScheduleContext(
            userAvailableTimeMap: slots,
            choreResponsibleMap: [:],
            userTotalCapacity: [alice.recordID!: 70, bob.recordID!: 70],
            minimumCapacity: 70
        )

        let chore = makeChore(recordName: "daily-nocap", frequency: .daily, duration: 10)

        var remaining = context.initialRemainingCapacity()
        var assigned = context.initialUserAssignedMinutes(users: [alice, bob])

        let results = scheduleRecurringChores(
            [chore],
            users: [alice, bob],
            context: context,
            now: now,
            remainingCapacity: &remaining,
            userAssignedMinutes: &assigned
        )

        let assignments = results[0].newAssignments
        #expect(assignments.count == 14)
        #expect(assignments.allSatisfy { $0.userReferences == nil })
    }

    @Test func recurringChoreWithFixedResponsibleIgnoresOtherUsersCapacity() {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date())

        let alice = makeUser("Alice", recordName: "alice-fixed")
        let bob = makeUser("Bob", recordName: "bob-fixed")

        // Alice only has a slot on day 0; Bob has slots every day but is not the fixed responsible.
        let aliceSlots = [makeSlot(day: now, capacityMinutes: 15, recordName: "alice-fixed-slot-0")]
        let bobSlots = (0..<14).map { offset in
            makeSlot(day: dayOffset(offset, from: now, calendar: calendar), capacityMinutes: 100, recordName: "bob-fixed-slot-\(offset)")
        }

        let chore = makeChore(recordName: "daily-fixed", frequency: .daily, duration: 10)

        let context = ScheduleContext(
            userAvailableTimeMap: [alice.recordID!: aliceSlots, bob.recordID!: bobSlots],
            choreResponsibleMap: [chore.recordID!: alice],
            userTotalCapacity: [alice.recordID!: 15, bob.recordID!: 1400],
            minimumCapacity: 15
        )

        var remaining = context.initialRemainingCapacity()
        var assigned = context.initialUserAssignedMinutes(users: [alice, bob])

        let results = scheduleRecurringChores(
            [chore],
            users: [alice, bob],
            context: context,
            now: now,
            remainingCapacity: &remaining,
            userAssignedMinutes: &assigned
        )

        let assignments = results[0].newAssignments
        #expect(assignments[0].userReferences?.first?.recordID == alice.recordID)
        for assignment in assignments.dropFirst() {
            #expect(assignment.userReferences == nil)
        }
    }

    @Test func recurringChoreRotationListRestrictsCandidatesToListedUsers() {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date())

        let alice = makeUser("Alice", recordName: "alice-rot")
        let bob = makeUser("Bob", recordName: "bob-rot")

        var slots: [CKRecord.ID: [AvailableTimeModel]] = [:]
        for (user, prefix) in [(alice, "alice"), (bob, "bob")] {
            slots[user.recordID!] = (0..<14).map { offset in
                makeSlot(day: dayOffset(offset, from: now, calendar: calendar), capacityMinutes: 100, recordName: "\(prefix)-rot-\(offset)")
            }
        }

        let chore = makeChore(
            recordName: "daily-rot",
            frequency: .daily,
            duration: 10,
            allResponsibleUsers: [reference(bob.recordID!)]
        )

        let context = ScheduleContext(
            userAvailableTimeMap: slots,
            // Fixed responsible is Alice, but the rotation list should win.
            choreResponsibleMap: [chore.recordID!: alice],
            userTotalCapacity: [alice.recordID!: 1400, bob.recordID!: 1400],
            minimumCapacity: 1400
        )

        var remaining = context.initialRemainingCapacity()
        var assigned = context.initialUserAssignedMinutes(users: [alice, bob])

        let results = scheduleRecurringChores(
            [chore],
            users: [alice, bob],
            context: context,
            now: now,
            remainingCapacity: &remaining,
            userAssignedMinutes: &assigned
        )

        let assignments = results[0].newAssignments
        #expect(assignments.allSatisfy { $0.userReferences?.first?.recordID == bob.recordID })
    }

    // MARK: - scheduleAssignedChores

    @Test func assignedChoresPickTheEarliestSlotWithEnoughCapacity() {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date())
        let windowEnd = dayOffset(15, from: now, calendar: calendar)

        let alice = makeUser("Alice", recordName: "alice-earliest")

        let tooSoon = makeSlot(day: dayOffset(-1, from: now, calendar: calendar), capacityMinutes: 100, recordName: "too-soon")
        let tooSmall = makeSlot(day: dayOffset(1, from: now, calendar: calendar), capacityMinutes: 5, recordName: "too-small")
        let valid = makeSlot(day: dayOffset(2, from: now, calendar: calendar), capacityMinutes: 100, recordName: "valid")
        let tooLate = makeSlot(day: dayOffset(20, from: now, calendar: calendar), capacityMinutes: 100, recordName: "too-late")

        let chore = makeChore(recordName: "assigned-earliest", frequency: .none, duration: 20)

        let context = ScheduleContext(
            userAvailableTimeMap: [alice.recordID!: [tooSoon, tooSmall, valid, tooLate]],
            choreResponsibleMap: [chore.recordID!: alice],
            userTotalCapacity: [alice.recordID!: 305],
            minimumCapacity: 305
        )

        var remaining = context.initialRemainingCapacity()
        var assigned = context.initialUserAssignedMinutes(users: [alice])

        let results = scheduleAssignedChores(
            [chore],
            context: context,
            now: now,
            windowEnd: windowEnd,
            remainingCapacity: &remaining,
            userAssignedMinutes: &assigned
        )

        #expect(results.count == 1)
        #expect(results[0].chore.dueDate == valid.day)
        #expect(remaining[valid.recordID!] == 80)
        #expect(assigned[alice.recordID!] == 20)
    }

    @Test func assignedChoreClearsDueDateWhenResponsibleHasNoAvailableTimeAtAll() {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date())
        let windowEnd = dayOffset(15, from: now, calendar: calendar)

        let alice = makeUser("Alice", recordName: "alice-noslots")
        let chore = makeChore(recordName: "assigned-noslots", frequency: .none, duration: 20)
        chore.dueDate = now

        let context = ScheduleContext(
            userAvailableTimeMap: [:],
            choreResponsibleMap: [chore.recordID!: alice],
            userTotalCapacity: [:],
            minimumCapacity: 0
        )

        var remaining = context.initialRemainingCapacity()
        var assigned = context.initialUserAssignedMinutes(users: [alice])

        let results = scheduleAssignedChores(
            [chore],
            context: context,
            now: now,
            windowEnd: windowEnd,
            remainingCapacity: &remaining,
            userAssignedMinutes: &assigned
        )

        #expect(results.count == 1)
        #expect(results[0].chore.dueDate == nil)
    }

    @Test func assignedChoreClearsDueDateWhenNoSlotHasEnoughCapacity() {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date())
        let windowEnd = dayOffset(15, from: now, calendar: calendar)

        let alice = makeUser("Alice", recordName: "alice-undercap")
        let slot = makeSlot(day: dayOffset(1, from: now, calendar: calendar), capacityMinutes: 5, recordName: "undercap-slot")
        let chore = makeChore(recordName: "assigned-undercap", frequency: .none, duration: 20)

        let context = ScheduleContext(
            userAvailableTimeMap: [alice.recordID!: [slot]],
            choreResponsibleMap: [chore.recordID!: alice],
            userTotalCapacity: [alice.recordID!: 5],
            minimumCapacity: 5
        )

        var remaining = context.initialRemainingCapacity()
        var assigned = context.initialUserAssignedMinutes(users: [alice])

        let results = scheduleAssignedChores(
            [chore],
            context: context,
            now: now,
            windowEnd: windowEnd,
            remainingCapacity: &remaining,
            userAssignedMinutes: &assigned
        )

        #expect(results[0].chore.dueDate == nil)
    }

    @Test func assignedChoreWithoutResolvedResponsibleProducesNoResult() {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date())
        let windowEnd = dayOffset(15, from: now, calendar: calendar)

        let chore = makeChore(recordName: "assigned-unresolved", frequency: .none, duration: 20)

        let context = ScheduleContext(
            userAvailableTimeMap: [:],
            choreResponsibleMap: [:],
            userTotalCapacity: [:],
            minimumCapacity: 0
        )

        var remaining = context.initialRemainingCapacity()
        var assigned = context.initialUserAssignedMinutes(users: [])

        let results = scheduleAssignedChores(
            [chore],
            context: context,
            now: now,
            windowEnd: windowEnd,
            remainingCapacity: &remaining,
            userAssignedMinutes: &assigned
        )

        #expect(results.isEmpty)
    }

    // MARK: - scheduleFreeChores

    @Test func freeChoresPreferABaselineCandidateOverAnEarlierFallbackSlot() {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date())
        let windowEnd = dayOffset(15, from: now, calendar: calendar)

        let alice = makeUser("Alice", recordName: "alice-baseline")
        let bob = makeUser("Bob", recordName: "bob-baseline")

        // Bob's slot is earlier, but Bob is already near the house's minimum capacity.
        let bobSlot = makeSlot(day: dayOffset(1, from: now, calendar: calendar), capacityMinutes: 100, recordName: "bob-baseline-slot")
        let aliceSlot = makeSlot(day: dayOffset(5, from: now, calendar: calendar), capacityMinutes: 100, recordName: "alice-baseline-slot")

        let chore = makeChore(recordName: "free-baseline", frequency: .none, duration: 10)

        let context = ScheduleContext(
            userAvailableTimeMap: [alice.recordID!: [aliceSlot], bob.recordID!: [bobSlot]],
            choreResponsibleMap: [:],
            userTotalCapacity: [alice.recordID!: 100, bob.recordID!: 100],
            minimumCapacity: 100
        )

        var remaining = context.initialRemainingCapacity()
        var assigned: [CKRecord.ID: Int] = [alice.recordID!: 0, bob.recordID!: 95]

        let results = scheduleFreeChores(
            [chore],
            users: [alice, bob],
            context: context,
            now: now,
            windowEnd: windowEnd,
            remainingCapacity: &remaining,
            userAssignedMinutes: &assigned
        )

        #expect(results[0].chore.currentResponsibleReference?.recordID == alice.recordID)
        #expect(results[0].chore.dueDate == aliceSlot.day)
        #expect(assigned[alice.recordID!] == 10)
    }

    @Test func freeChoresFallBackToLeastLoadedUserWhenNobodyIsUnderMinimumCapacity() {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date())
        let windowEnd = dayOffset(15, from: now, calendar: calendar)

        let alice = makeUser("Alice", recordName: "alice-fallback")
        let bob = makeUser("Bob", recordName: "bob-fallback")

        // Bob's slot is earlier, but Alice has fewer assigned minutes and should still win.
        let bobSlot = makeSlot(day: dayOffset(1, from: now, calendar: calendar), capacityMinutes: 100, recordName: "bob-fallback-slot")
        let aliceSlot = makeSlot(day: dayOffset(5, from: now, calendar: calendar), capacityMinutes: 100, recordName: "alice-fallback-slot")

        let chore = makeChore(recordName: "free-fallback", frequency: .none, duration: 10)

        let context = ScheduleContext(
            userAvailableTimeMap: [alice.recordID!: [aliceSlot], bob.recordID!: [bobSlot]],
            choreResponsibleMap: [:],
            userTotalCapacity: [alice.recordID!: 100, bob.recordID!: 100],
            minimumCapacity: 50
        )

        var remaining = context.initialRemainingCapacity()
        var assigned: [CKRecord.ID: Int] = [alice.recordID!: 50, bob.recordID!: 60]

        let results = scheduleFreeChores(
            [chore],
            users: [alice, bob],
            context: context,
            now: now,
            windowEnd: windowEnd,
            remainingCapacity: &remaining,
            userAssignedMinutes: &assigned
        )

        #expect(results[0].chore.currentResponsibleReference?.recordID == alice.recordID)
    }

    @Test func freeChoreClearsResponsibleAndDueDateWhenNoOneHasCapacity() {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date())
        let windowEnd = dayOffset(15, from: now, calendar: calendar)

        let alice = makeUser("Alice", recordName: "alice-nospace")
        let slot = makeSlot(day: dayOffset(1, from: now, calendar: calendar), capacityMinutes: 5, recordName: "nospace-slot")

        let chore = makeChore(
            recordName: "free-nospace",
            frequency: .none,
            duration: 20,
            currentResponsible: reference(alice.recordID!)
        )
        chore.dueDate = dayOffset(1, from: now, calendar: calendar)

        let context = ScheduleContext(
            userAvailableTimeMap: [alice.recordID!: [slot]],
            choreResponsibleMap: [:],
            userTotalCapacity: [alice.recordID!: 5],
            minimumCapacity: 5
        )

        var remaining = context.initialRemainingCapacity()
        var assigned = context.initialUserAssignedMinutes(users: [alice])

        let results = scheduleFreeChores(
            [chore],
            users: [alice],
            context: context,
            now: now,
            windowEnd: windowEnd,
            remainingCapacity: &remaining,
            userAssignedMinutes: &assigned
        )

        #expect(results[0].chore.currentResponsibleReference == nil)
        #expect(results[0].chore.dueDate == nil)
    }

    @Test func freeChoreRotationListNeverGetsDuplicateEntriesForTheSameUser() {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date())
        let windowEnd = dayOffset(15, from: now, calendar: calendar)

        let alice = makeUser("Alice", recordName: "alice-dedup")
        let slot = makeSlot(day: dayOffset(1, from: now, calendar: calendar), capacityMinutes: 100, recordName: "dedup-slot")

        let chore = makeChore(
            recordName: "free-dedup",
            frequency: .none,
            duration: 10,
            allResponsibleUsers: [reference(alice.recordID!)]
        )

        let context = ScheduleContext(
            userAvailableTimeMap: [alice.recordID!: [slot]],
            choreResponsibleMap: [:],
            userTotalCapacity: [alice.recordID!: 100],
            minimumCapacity: 100
        )

        var remaining = context.initialRemainingCapacity()
        var assigned = context.initialUserAssignedMinutes(users: [alice])

        let results = scheduleFreeChores(
            [chore],
            users: [alice],
            context: context,
            now: now,
            windowEnd: windowEnd,
            remainingCapacity: &remaining,
            userAssignedMinutes: &assigned
        )

        #expect(results[0].chore.allResponsibleUsersReference?.count == 1)
    }

    // MARK: - occurrenceOffsets

    @Test func occurrenceOffsetsCoverEveryFrequency() {
        #expect(occurrenceOffsets(for: .daily, windowDays: 5, phase: 0) == [0, 1, 2, 3, 4])
        #expect(occurrenceOffsets(for: .weekly, windowDays: 16, phase: 2) == [2, 9])
        #expect(occurrenceOffsets(for: .fortnightly, windowDays: 29, phase: 1) == [1, 15])
        #expect(occurrenceOffsets(for: .monthly, windowDays: 29, phase: 1) == [1, 15])
        #expect(occurrenceOffsets(for: .none, windowDays: 14, phase: 0) == [])
        #expect(occurrenceOffsets(for: .undefined, windowDays: 14, phase: 0) == [])
    }

    @Test func occurrenceOffsetsPhaseWrapsWithinThePeriod() {
        let wrapped = occurrenceOffsets(for: .weekly, windowDays: 14, phase: 9)
        let base = occurrenceOffsets(for: .weekly, windowDays: 14, phase: 2)
        #expect(wrapped == base)
    }

    // MARK: - occurrenceDays

    @Test func occurrenceDaysStepThroughTheCycleForEveryFrequency() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())

        let dailyEnd = dayOffset(3, from: start, calendar: calendar)
        let dailyDays = occurrenceDays(for: .daily, from: start, through: dailyEnd, calendar: calendar)
        #expect(dailyDays.count == 4)
        #expect(dailyDays.first == start)
        #expect(dailyDays.last == dailyEnd)

        let weeklyEnd = dayOffset(20, from: start, calendar: calendar)
        let weeklyDays = occurrenceDays(for: .weekly, from: start, through: weeklyEnd, calendar: calendar)
        #expect(weeklyDays == [start, dayOffset(7, from: start, calendar: calendar), dayOffset(14, from: start, calendar: calendar)])

        #expect(occurrenceDays(for: .none, from: start, through: dailyEnd, calendar: calendar).isEmpty)
        #expect(occurrenceDays(for: .undefined, from: start, through: dailyEnd, calendar: calendar).isEmpty)
    }

    @Test func occurrenceDaysIsEmptyWhenStartIsAfterCycleEnd() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let cycleEnd = dayOffset(-1, from: start, calendar: calendar)

        #expect(occurrenceDays(for: .daily, from: start, through: cycleEnd, calendar: calendar).isEmpty)
    }

    // MARK: - TaskSchedulerEngine.schedule guard clauses

    @Test func scheduleReturnsImmediatelyWhenThereAreNoUsers() async {
        let chore = makeChore(recordName: "lonely-chore", frequency: .none, duration: 10)

        await TaskSchedulerEngine.schedule(chores: [chore], users: [])

        #expect(chore.dueDate == nil)
    }
}

/// End-to-end exercise of ``TaskSchedulerEngine/schedule(chores:users:)`` against the real
/// CloudKit container (same approach as the other suites under `CloudKitManagerTests`).
/// Needs an actual `HouseModel` record to resolve a zone before anything is persisted, so —
/// unlike ``AlgorithmTests`` above — these are slower and depend on live CloudKit state.
@MainActor
struct SchedulerIntegrationTests {

    var avalibleTime1Reference: [CKRecord.Reference] = []
    var avalibleTime2Reference: [CKRecord.Reference] = []
    var chores: [ChoreModel] = []

    let runID = String(UUID().uuidString.prefix(8))
    var aliceName: String { "Alice-\(runID)" }
    var bobName: String { "Bob-\(runID)" }

    var alice = UserModel(name: "Alice", tier: .tier1, ownerRecordName: "")
    var bob = UserModel(name: "Bob", tier: .tier1, ownerRecordName: "")

    // MARK: - Setup

    mutating func setup(chores: [ChoreModel]) async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let avalibleTime1 = [
            AvailableTimeModel(capacityMinutes: 60, day: today, user: nil),
            AvailableTimeModel(capacityMinutes: 30, day: calendar.date(byAdding: .day, value: 1, to: today)!, user: nil),
            AvailableTimeModel(capacityMinutes: 120, day: calendar.date(byAdding: .day, value: 2, to: today)!, user: nil)
        ]
        let avalibleTime2 = [
            AvailableTimeModel(capacityMinutes: 20, day: calendar.date(byAdding: .day, value: 1, to: today)!, user: nil),
            AvailableTimeModel(capacityMinutes: 30, day: calendar.date(byAdding: .day, value: 2, to: today)!, user: nil),
            AvailableTimeModel(capacityMinutes: 60, day: calendar.date(byAdding: .day, value: 3, to: today)!, user: nil)
        ]

        for avt in avalibleTime1 {
            let saved = await CloudKitManager.shared.create(avt)
            let avtReference = CKRecord.Reference(recordID: (saved?.recordID!)!,
                                                  action: CKRecord.ReferenceAction.none)
            avalibleTime1Reference.append(avtReference)
        }

        for avt in avalibleTime2 {
            let saved = await CloudKitManager.shared.create(avt)
            let avtReference = CKRecord.Reference(recordID: (saved?.recordID!)!,
                                                  action: CKRecord.ReferenceAction.none)
            avalibleTime2Reference.append(avtReference)
        }

        alice.availableTimeReference = avalibleTime1Reference
        bob.availableTimeReference = avalibleTime2Reference

        alice.name = aliceName
        bob.name = bobName

        await CloudKitManager.shared.create(alice)
        await CloudKitManager.shared.create(bob)

        try? await Task.sleep(for: .seconds(1))

        let alicePredicate = NSPredicate(format: "name == %@", aliceName)
        let bobPredicate = NSPredicate(format: "name == %@", bobName)

        alice = await CloudKitManager.shared.fetchAll(UserModel.self, predicate: alicePredicate).first!
        bob = await CloudKitManager.shared.fetchAll(UserModel.self, predicate: bobPredicate).first!

        for chore in chores {
            let uniqueChore = chore
            uniqueChore.name = "\(chore.name)-\(runID)"
            self.chores.append(await CloudKitManager.shared.create(uniqueChore)!)
        }
    }

    // MARK: - Limpeza

    func deleteAll() async {
        await CloudKitManager.shared.delete(alice)
        await CloudKitManager.shared.delete(bob)

        for av in avalibleTime1Reference {
            await CloudKitManager.shared.delete(AvailableTimeModel.self, recordID: av.recordID)
        }
        for av in avalibleTime2Reference {
            await CloudKitManager.shared.delete(AvailableTimeModel.self, recordID: av.recordID)
        }
        for chore in chores {
            await CloudKitManager.shared.delete(chore)
        }
    }

    // MARK: - Teste Schedule

    @Test mutating func schedule() async {
        await setup(
            chores: [
                ChoreModel(name: "tarefa1", description: "description1", frequency: .daily, duration: 20, isPublic: true, priorityTag: .low),
                ChoreModel(name: "tarefa2", description: "description2", frequency: .fortnightly, duration: 40, isPublic: true, priorityTag: .medium),
                ChoreModel(name: "tarefa3", description: "description3", frequency: .monthly, duration: 30, isPublic: true, priorityTag: .high),
                ChoreModel(name: "tarefa4", description: "description4", frequency: .none, duration: 10, isPublic: true, priorityTag: .urgent),
                ChoreModel(name: "tarefa5", description: "description5", frequency: .weekly, duration: 15, isPublic: true, priorityTag: .low),
            ]
        )
        await TaskSchedulerEngine.schedule(chores: chores, users: [alice, bob])

        let alicePredicate = NSPredicate(format: "name == %@", aliceName)
        let bobPredicate = NSPredicate(format: "name == %@", bobName)

        alice = await CloudKitManager.shared.fetchAll(UserModel.self, predicate: alicePredicate).first!
        bob = await CloudKitManager.shared.fetchAll(UserModel.self, predicate: bobPredicate).first!

        #expect(alice.choresReference?.isEmpty == false)
        #expect(bob.choresReference?.isEmpty == false)

        await deleteAll()
    }

    // MARK: - Teste Incremental Scheduling and Reassignment

    @Test mutating func incrementalSchedulingAndReassignment() async {
        await setup(
            chores: [
                ChoreModel(name: "tarefa1", description: "description1", frequency: .daily, duration: 20, isPublic: true, priorityTag: .low),
                ChoreModel(name: "tarefa2", description: "description2", frequency: .fortnightly, duration: 40, isPublic: true, priorityTag: .medium),
                ChoreModel(name: "tarefa3", description: "description1", frequency: .none, duration: 20, isPublic: true, priorityTag: .low),
                ChoreModel(name: "tarefa4", description: "description2", frequency: .fortnightly, duration: 40, isPublic: true, priorityTag: .medium),
                ChoreModel(name: "tarefa5", description: "description3", frequency: .monthly, duration: 30, isPublic: true, priorityTag: .high),
                ChoreModel(name: "tarefa6", description: "description4", frequency: .daily, duration: 10, isPublic: true, priorityTag: .urgent),
                ChoreModel(name: "tarefa7", description: "description5", frequency: .weekly, duration: 15, isPublic: true, priorityTag: .low),
            ]
        )
        await TaskSchedulerEngine.schedule(chores: [chores[0], chores[1]], users: [alice])

        let alicePredicate = NSPredicate(format: "name == %@", aliceName)
        alice = await CloudKitManager.shared.fetchAll(UserModel.self, predicate: alicePredicate).first!

        let aliceChores = await CloudKitManager.shared.fetchRecordsByRecordReference(
            for: ChoreModel.self,
            recordReferences: alice.choresReference!
        )
        for chore in aliceChores ?? [] {
            print("Alice chore: \(chore.name), duration: \(chore.duration), frequency: \(chore.frequency.rawValue)")
            if chore.frequency == .daily {
                let dailyAssignments = await CloudKitManager.shared.fetchRecordsByRecordReference(
                    for: RecurrentAssignmentModel.self,
                    recordReferences: chore.dailyAssignmentsReference!
                )

                for d in (dailyAssignments ?? []).filter({ $0.userReferences?.contains(where: { $0.recordID == alice.recordID }) == true }) {
                    print("     daily date: \(d.day)")
                }
            }
        }

        print("-------------------------------------------")

        let myChoreRefs = chores.compactMap { $0.recordID }
            .map { CKRecord.Reference(recordID: $0, action: CKRecord.ReferenceAction.none) }
        chores = await CloudKitManager.shared.fetchRecordsByRecordReference(
            for: ChoreModel.self,
            recordReferences: myChoreRefs
        ) ?? []

        await TaskSchedulerEngine.schedule(chores: chores, users: [alice, bob])
        alice = await CloudKitManager.shared.fetchAll(UserModel.self, predicate: alicePredicate).first!

        let aliceChores2 = await CloudKitManager.shared.fetchRecordsByRecordReference(
            for: ChoreModel.self,
            recordReferences: alice.choresReference!
        )
        for chore in aliceChores2 ?? [] {
            print("Alice chore: \(chore.name), duration: \(chore.duration), frequency: \(chore.frequency.rawValue), dueDate: \(String(describing: chore.dueDate))")
            if chore.frequency == .daily {
                let dailyAssignments = await CloudKitManager.shared.fetchRecordsByRecordReference(
                    for: RecurrentAssignmentModel.self,
                    recordReferences: chore.dailyAssignmentsReference!
                )
                for d in (dailyAssignments ?? []).filter({ $0.userReferences?.contains(where: { $0.recordID == alice.recordID }) == true }) {
                    print("     daily date: \(d.day)")
                }
            }
        }

        let bobPredicate = NSPredicate(format: "name == %@", bobName)
        bob = await CloudKitManager.shared.fetchAll(UserModel.self, predicate: bobPredicate).first!

        let bobChores = await CloudKitManager.shared.fetchRecordsByRecordReference(
            for: ChoreModel.self,
            recordReferences: bob.choresReference!
        )
        for chore in bobChores ?? [] {
            print("Bob chore: \(chore.name), duration: \(chore.duration), frequency: \(chore.frequency.rawValue), dueDate: \(String(describing: chore.dueDate))")
            if chore.frequency == .daily {
                let dailyAssignments = await CloudKitManager.shared.fetchRecordsByRecordReference(
                    for: RecurrentAssignmentModel.self,
                    recordReferences: chore.dailyAssignmentsReference!
                )
                for d in (dailyAssignments ?? []).filter({ $0.userReferences?.contains(where: { $0.recordID == bob.recordID }) == true }) {
                    print("     daily date: \(d.day)")
                }
            }
        }

        #expect(alice.choresReference?.isEmpty == false)
        #expect(bob.choresReference?.isEmpty == false)

        await deleteAll()
    }

    // MARK: - Teste Insufficient Capacity
    @Test mutating func insufficientCapacity() async {
        await setup(
            chores: [
                ChoreModel(name: "tarefaGigante", description: "Muito longa", frequency: .none, duration: 999, isPublic: true, priorityTag: .urgent)
            ]
        )

        await TaskSchedulerEngine.schedule(chores: chores, users: [alice, bob])

        let taskRef = CKRecord.Reference(recordID: chores[0].recordID!, action: .none)
        let fetchedChore = await CloudKitManager.shared.fetchRecordsByRecordReference(
            for: ChoreModel.self,
            recordReferences: [taskRef]
        )?.first

        #expect(fetchedChore?.dueDate == nil)
        #expect(fetchedChore?.currentResponsibleReference == nil)

        await deleteAll()
    }

    // MARK: - Teste Idempotency / Re-scheduling
    @Test mutating func schedulingIdempotency() async {
        await setup(
            chores: [
                ChoreModel(name: "tarefaRepetida", description: "Teste idempotencia", frequency: .daily, duration: 10, isPublic: true, priorityTag: .medium)
            ]
        )

        await TaskSchedulerEngine.schedule(chores: chores, users: [alice, bob])

        let alicePredicate = NSPredicate(format: "name == %@", aliceName)
        alice = await CloudKitManager.shared.fetchAll(UserModel.self, predicate: alicePredicate).first!
        let choreCount = alice.choresReference?.count ?? 0

        let refreshedChores = await CloudKitManager.shared.fetchRecordsByRecordReference(
            for: ChoreModel.self,
            recordReferences: chores.compactMap { $0.recordID }.map { CKRecord.Reference(recordID: $0, action: .none) }
        ) ?? []

        await TaskSchedulerEngine.schedule(chores: refreshedChores, users: [alice, bob])

        alice = await CloudKitManager.shared.fetchAll(UserModel.self, predicate: alicePredicate).first!
        let choreCount2 = alice.choresReference?.count ?? 0

        #expect(choreCount == choreCount2)

        await deleteAll()
    }

    // MARK: - Teste Fixed Responsible with No Capacity
    @Test mutating func fixedResponsibleWithoutCapacity() async {
        let aliceChore = ChoreModel(name: "AliceChore", description: "AliceChore no time", frequency: .none, duration: 500, isPublic: true, priorityTag: .high)

        await setup(chores: [aliceChore])

        let choreRef = CKRecord.Reference(recordID: chores[0].recordID!, action: .none)
        let savedChore = (await CloudKitManager.shared.fetchRecordsByRecordReference(for: ChoreModel.self, recordReferences: [choreRef]))!.first!
        savedChore.currentResponsibleReference = CKRecord.Reference(recordID: alice.recordID!, action: .none)

        _ = await CloudKitManager.shared.update(savedChore)

        await TaskSchedulerEngine.schedule(chores: [savedChore], users: [alice, bob])

        let choreFetched = await CloudKitManager.shared.fetchRecordsByRecordReference(for: ChoreModel.self, recordReferences: [choreRef])?.first

        #expect(choreFetched?.dueDate == nil)

        await deleteAll()
    }
}
