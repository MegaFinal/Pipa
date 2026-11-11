//
//  ChoreCompletionBatcher.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 09/11/26.
//

import Foundation
import CloudKit

/// Collects check-offs (chores and occurrences) made close together and saves them in one go.
///
/// ## Bug fix: chores coming back unchecked
/// Each tap used to save its own record, plus the points and coins, right away. Checking several
/// chores off in a row fired all of those saves at once in the house's zone; CloudKit answered
/// most of them with `zoneBusy` / `requestRateLimited`, the model rolled the check back and, as
/// nothing on screen read the result, the chores turned unchecked a moment later without a word.
///
/// Now a tap only changes the model on screen. Taps that come close together are saved together
/// with ``CloudKitManager/batchUpdateRetrying(_:maxAttempts:)``, which waits and tries again when
/// CloudKit asks to, and the points of the whole batch go out as one change per member. A check
/// that can't be saved goes back and ``onError`` explains why.
@MainActor
final class ChoreCompletionBatcher {

    /// What gets checked off.
    enum Target {
        case chore(ChoreModel)
        case assignment(RecurrentAssignmentModel)

        var recordID: CKRecord.ID? {
            switch self {
            case .chore(let chore): return chore.recordID
            case .assignment(let assignment): return assignment.recordID
            }
        }

        /// The completion fields as they are now.
        var state: CompletionState {
            switch self {
            case .chore(let chore):
                return CompletionState(isDone: chore.isDone, doer: chore.userThatHaveDoneReference, awardedPoints: chore.awardedPoints, badgeRoom: chore.badgeRoom)
            case .assignment(let assignment):
                return CompletionState(isDone: assignment.isCompleted, doer: assignment.userThatHaveDoneReference, awardedPoints: assignment.awardedPoints, badgeRoom: assignment.badgeRoom)
            }
        }

        /// Writes `state` into the model (nothing is saved).
        func apply(_ state: CompletionState) {
            switch self {
            case .chore(let chore):
                chore.isDone = state.isDone
                chore.userThatHaveDoneReference = state.doer
                chore.awardedPoints = state.awardedPoints
                chore.badgeRoom = state.badgeRoom
            case .assignment(let assignment):
                assignment.isCompleted = state.isDone
                assignment.userThatHaveDoneReference = state.doer
                assignment.awardedPoints = state.awardedPoints
                assignment.badgeRoom = state.badgeRoom
            }
        }
    }

    /// The fields a check-off changes.
    struct CompletionState: Equatable {
        var isDone: Bool
        var doer: CKRecord.Reference?
        var awardedPoints: Int?
        /// The kind of default room the completion counts for in the room badges (see
        /// ``ChoreModel/badgeRoom``); `nil` when it doesn't count.
        var badgeRoom: String? = nil

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.isDone == rhs.isDone
            && lhs.doer?.recordID == rhs.doer?.recordID
            && lhs.awardedPoints == rhs.awardedPoints
            && lhs.badgeRoom == rhs.badgeRoom
        }
    }

    /// A check-off waiting to be saved (or being saved).
    private struct Entry {
        /// The model on screen. Replaced when a reload brings a new instance of the same record.
        var target: Target
        /// The state CloudKit has, to go back to when the save fails.
        let original: CompletionState
        /// Points per member: `nil` is the signed-in member. Summed up on save.
        var points: [(user: UserModel?, delta: Int)]
        /// The chore to tell its owners about once the check is saved, when it was checked (not unchecked).
        var choreToNotify: ChoreModel?
        /// Who the saved completion was counted for in the room badges, when it was done before
        /// this change (`nil` is the signed-in member). Unchecking takes the check-off back from them.
        var originalDoer: UserModel?
    }

    /// Waits this long after the last tap before saving, so taps in a row go out together.
    var debounce: Duration = .milliseconds(700)
    /// Never holds a check longer than this, even while the user keeps tapping.
    var maxDelay: TimeInterval = 2.5

    /// Rebuilds the screen after a check goes back.
    var onRollback: () -> Void = {}
    /// Explains why some checks couldn't be saved.
    var onError: (String) -> Void = { _ in }
    /// Tells the owners that `chore` (or its `assignment`) was done by someone else.
    var onSavedDone: (ChoreModel, RecurrentAssignmentModel?) -> Void = { _, _ in }
    /// Tells the signed-in member about the room badges their saved checks just unlocked.
    var onBadgesUnlocked: ([RoomBadge]) -> Void = { _ in }

    private var pending: [CKRecord.ID: Entry] = [:]
    private var inFlight: [CKRecord.ID: Entry] = [:]
    private var firstPendingAt: Date?
    private var flushTask: Task<Void, Never>?
    private var isFlushing = false

    // MARK: - Recording

    /// Applies `state` to `target` on screen and queues the save.
    ///
    /// - Parameters:
    ///   - target: The chore or occurrence.
    ///   - state: Its new completion state.
    ///   - points: The points this change gives (positive) or takes back (negative).
    ///   - pointsOwner: Whose points change; `nil` for the signed-in member.
    ///   - choreToNotify: Set when it was checked off, to tell the chore's owners once it's saved.
    func record(
        _ target: Target,
        to state: CompletionState,
        points: Int,
        pointsOwner: UserModel?,
        choreToNotify: ChoreModel?
    ) {
        guard let id = target.recordID else { return }

        // A check-off already saved can only be unchecked first: whose points go back is whose
        // badge check-off goes back too.
        var entry = pending[id] ?? Entry(
            target: target,
            original: target.state,
            points: [],
            choreToNotify: nil,
            originalDoer: target.state.isDone ? pointsOwner : nil
        )
        entry.target = target
        entry.points.append((user: pointsOwner, delta: points))
        entry.choreToNotify = state.isDone ? choreToNotify : nil
        target.apply(state)

        // Back where CloudKit is: nothing to save, and the points cancel out.
        if entry.original == state {
            pending[id] = nil
        } else {
            pending[id] = entry
        }
        if firstPendingAt == nil { firstPendingAt = .now }
        scheduleFlush()
    }

    /// Whether `target` still has a check waiting or being saved.
    func isBusy(_ id: CKRecord.ID) -> Bool {
        pending[id] != nil || inFlight[id] != nil
    }

    /// Puts the checks not saved yet back on new instances of the same records (a reload while
    /// they wait would show them unchecked again), and makes those instances the ones saved.
    func overlay(chores: [ChoreModel], assignments: [RecurrentAssignmentModel]) {
        guard !pending.isEmpty || !inFlight.isEmpty else { return }

        func refresh(_ target: Target) {
            guard let id = target.recordID else { return }
            if var entry = pending[id] {
                target.apply(entry.target.state)
                entry.target = target
                pending[id] = entry
            } else if var entry = inFlight[id] {
                target.apply(entry.target.state)
                entry.target = target
                inFlight[id] = entry
            }
        }
        chores.forEach { refresh(.chore($0)) }
        assignments.forEach { refresh(.assignment($0)) }
    }

    // MARK: - Saving

    /// Saves now whatever is waiting (e.g. the app is going to the background).
    func flushNow() {
        flushTask?.cancel()
        flushTask = Task { await flush() }
    }

    private func scheduleFlush() {
        flushTask?.cancel()
        let waitedTooLong = firstPendingAt.map { Date.now.timeIntervalSince($0) >= maxDelay } ?? false
        let delay: Duration = waitedTooLong ? .zero : debounce
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    private func flush() async {
        // One save at a time: a batch that arrives meanwhile goes right after.
        guard !isFlushing else { return }
        guard !pending.isEmpty else { firstPendingAt = nil; return }

        isFlushing = true
        let batch = pending
        pending = [:]
        firstPendingAt = nil
        inFlight.merge(batch) { _, new in new }

        // Before saving: the completions must hold the room they really count for.
        await limitOneOffBadges(in: batch)

        var chores: [ChoreModel] = []
        var assignments: [RecurrentAssignmentModel] = []
        for entry in batch.values {
            switch entry.target {
            case .chore(let chore): chores.append(chore)
            case .assignment(let assignment): assignments.append(assignment)
            }
        }

        let manager = CloudKitManager.shared
        manager.errorMessage = nil
        var failed = await manager.batchUpdateRetrying(assignments)
        failed.formUnion(await manager.batchUpdateRetrying(chores))

        // Failed: back to what CloudKit has. A newer tap on the same record is dropped with it,
        // since it started from the state that couldn't be saved.
        for id in failed {
            guard let entry = batch[id] else { continue }
            (pending[id]?.target ?? inFlight[id]?.target ?? entry.target).apply(entry.original)
            pending[id] = nil
        }

        // Saved: the points of the whole batch, one change per member.
        let saved = batch.filter { !failed.contains($0.key) }
        await applyPoints(of: Array(saved.values))
        let unlockedBadges = await applyBadges(of: Array(saved.values))
        if !unlockedBadges.isEmpty { onBadgesUnlocked(unlockedBadges) }
        for entry in saved.values {
            guard let chore = entry.choreToNotify, entry.target.state.isDone else { continue }
            if case .assignment(let assignment) = entry.target {
                onSavedDone(chore, assignment)
            } else {
                onSavedDone(chore, nil)
            }
        }

        for id in batch.keys { inFlight[id] = nil }
        isFlushing = false

        if !failed.isEmpty {
            onRollback()
            let count = failed.count
            let reason = manager.errorMessage ?? L10n.tr("Tente novamente.")
            onError(count == 1
                ? L10n.tr("Uma tarefa não pôde ser salva e voltou como pendente. \(reason)")
                : L10n.tr("\(count) tarefas não puderam ser salvas e voltaram como pendentes. \(reason)"))
        }

        if !pending.isEmpty { scheduleFlush() }
    }

    /// Sums the points of `entries` per member and applies each sum once (``ScoreManager``).
    private func applyPoints(of entries: [Entry]) async {
        var totals: [String: (user: UserModel?, delta: Int)] = [:]
        for change in entries.flatMap(\.points) where change.delta != 0 {
            let key = change.user?.recordID?.recordName ?? "me"
            totals[key, default: (user: change.user, delta: 0)].delta += change.delta
        }
        guard !totals.isEmpty else { return }

        let scoreManager = ScoreManager.shared
        for total in totals.values where total.delta != 0 {
            if let user = total.user {
                await scoreManager.applyPoints(total.delta, to: user)
            } else if let me = await CloudKitManager.shared.fetchMyHouseUser() {
                await scoreManager.applyPoints(total.delta, to: me)
            }
        }
    }

    // MARK: - Room badges

    /// Leaves out of the room badges the one-off chores of `batch` checked off over the day's
    /// limit (``RoomBadgeProgressModel/oneOffDailyLimit``), before they are saved: their
    /// ``CompletionState/badgeRoom`` goes back to `nil`.
    private func limitOneOffBadges(in batch: [CKRecord.ID: Entry]) async {
        var newlyCounting: [DefaultRoomsOnboarding: [Target]] = [:]
        for entry in batch.values {
            guard case .chore = entry.target else { continue }
            let state = entry.target.state
            let alreadyCounted = entry.original.isDone && entry.original.badgeRoom != nil
            guard state.isDone, !alreadyCounted,
                  let room = state.badgeRoom.flatMap(DefaultRoomsOnboarding.init(rawValue:))
            else { continue }
            newlyCounting[room, default: []].append(entry.target)
        }
        guard !newlyCounting.isEmpty else { return }

        // Nobody to count them for: none of them counts.
        var countable: [DefaultRoomsOnboarding: Int] = [:]
        if let me = await CloudKitManager.shared.fetchMyHouseUser() {
            countable = await BadgeManager.shared.countableOneOffs(for: me)
        }
        for (room, targets) in newlyCounting {
            for target in targets.dropFirst(countable[room] ?? 0) {
                var state = target.state
                state.badgeRoom = nil
                target.apply(state)
            }
        }
    }

    /// Counts the saved checks towards the room badges (``BadgeManager``): a check adds one to
    /// the room it counts for, and unchecking takes it back from whoever it was counted for.
    ///
    /// - Returns: The badges the signed-in member just unlocked.
    private func applyBadges(of entries: [Entry]) async -> [RoomBadge] {
        var changesByMember: [String: (user: UserModel?, changes: [RoomBadgeChange])] = [:]
        func add(_ change: RoomBadgeChange, for user: UserModel?) {
            let key = user?.recordID?.recordName ?? "me"
            changesByMember[key, default: (user: user, changes: [])].changes.append(change)
        }

        for entry in entries {
            let before = entry.original
            let after = entry.target.state
            // A completion counts only while it is done (an old one may still hold a room).
            let counted = before.isDone ? before.badgeRoom.flatMap(DefaultRoomsOnboarding.init(rawValue:)) : nil
            let counts = after.isDone ? after.badgeRoom.flatMap(DefaultRoomsOnboarding.init(rawValue:)) : nil
            guard counted != counts || before.doer?.recordID != after.doer?.recordID else { continue }

            var isOneOff = false
            if case .chore = entry.target { isOneOff = true }
            if let counted {
                add(RoomBadgeChange(room: counted, delta: -1), for: entry.originalDoer)
            }
            if let counts {
                // A check is always made by the signed-in member.
                add(RoomBadgeChange(room: counts, delta: 1, isOneOff: isOneOff), for: nil)
            }
        }
        guard !changesByMember.isEmpty else { return [] }

        var unlocked: [RoomBadge] = []
        for (key, group) in changesByMember {
            var member = group.user
            if member == nil { member = await CloudKitManager.shared.fetchMyHouseUser() }
            guard let member else { continue }
            let newlyUnlocked = await BadgeManager.shared.apply(group.changes, to: member)
            if key == "me" { unlocked += newlyUnlocked }
        }
        return unlocked
    }
}
