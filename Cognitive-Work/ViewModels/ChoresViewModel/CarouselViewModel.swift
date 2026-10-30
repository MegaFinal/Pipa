//
//  CarouselViewModel.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 18/08/26.
//

import SwiftUI
import CloudKit

/// The filters the user picked in the chores list. Empty arrays mean "no filter".
struct ChoreFilters {
    /// Show only chores of these members.
    var users: [UserModel] = []
    /// Show only chores with these priorities.
    var tags: [PriorityTag] = []
    /// Show only chores with these frequencies.
    var frequencies: [Recurrence] = []
    /// Show only chores of these rooms.
    var rooms: [RoomModel] = []
    /// Show only done (`true`) or pending (`false`) chores; `nil` shows both.
    var state: Bool? = nil
}

/// Controls the state, data fetching, filtering, and mathematical rendering of the carousel.
@Observable
class CarouselViewModel {
    
    // MARK: - Core Data Models
    
    /// Every chore of the house.
    var cardModels: [ChoreModel] = []
    /// Every room of the house.
    var roomModels: [RoomModel] = []
    /// The house members.
    var userModels: [UserModel] = []
    /// Every chore occurrence of the house.
    var dailyAssignments: [RecurrentAssignmentModel] = []
    
    // MARK: - Derived State
    
    /// Today's statistics for ``dashboardUser``, recomputed only when the data changes.
    private(set) var dashboard: DashboardModel?
    
    /// The in-house profile the dashboard is computed for.
    private(set) var dashboardUser: UserModel?
    
    /// Chores and occurrences nobody is responsible for, recomputed only when the data changes.
    private(set) var unassignedItems: [UnassignedItem] = []
    
    /// Bumped on every rebuild, so views can react to "the data changed" with a single
    /// `.task(id:)`
    private(set) var dataVersion: Int = 0
    
    // MARK: - Lookup Indexes
    
    /// Assignments keyed by their own record ID.
    @ObservationIgnored
    private var assignmentsByID: [CKRecord.ID: RecurrentAssignmentModel] = [:]
    
    /// Future assignments per chore, sorted by day, precomputed once per rebuild.
    @ObservationIgnored
    private var futureAssignmentsByChore: [CKRecord.ID: [RecurrentAssignmentModel]] = [:]
    
    /// Next scheduled date per chore, precomputed once per rebuild.
    @ObservationIgnored
    private var nextDateByChore: [CKRecord.ID: Date] = [:]
    
    /// Every in-house record of the signed-in person (matched by `ownerRecordName`, like
    /// ``choresVisible(_:to:among:)``). Empty while the user isn't resolved yet.
    @ObservationIgnored
    private var viewerRecordIDs: Set<CKRecord.ID> = []
    
    // MARK: - UI & Layout State
    
    /// Whether the chores show as a carousel or a list.
    var layoutMode: CardLayoutMode = .grid
    /// `true` while loading the data.
    var isLoading: Bool = false
    /// Whether the first load already happened.
    private var hasFetchedInitially = false
    
    /// The snapshot of ``HouseDataStore`` this view model last showed, so reopening the tab
    /// doesn't rebuild everything when nothing changed.
    @ObservationIgnored
    private var appliedSnapshotID: UUID?
    
    /// Set when ``delete(chore:targetOccurrences:)`` fails, so a view can surface it in an
    /// alert. Left for the view to clear back to `nil` once shown.
    var errorMessage: String?
    
    /// The last day of the division cycle in progress.
    var currentCycleEnd: Date? {
        let today = Calendar.current.startOfDay(for: Date())
        return dailyAssignments.map(\.day).filter { $0 >= today }.max()
    }
    
    // MARK: - Carousel Geometry State
    
    /// The exact index where the carousel is currently resting.
    var snappedItem: Double = 0
    /// The continuous floating point index used during active swipe gestures.
    var draggingItem: Double = 0
    /// The integer index of the most prominent, centered card.
    var activeIndex: Int = 0
    
    // MARK: - Focus & Flip State
    
    /// Position of the card opened in the middle of the screen, or `nil` when none is.
    private var focusedIndex: Int? = nil
    /// Stores the recordID of the focused card, to keep it visible regardless of filters
    private var focusedChoreRecordID: CKRecord.ID? = nil
    
    /// Stores a copy of the focused chore to keep it visible even if not present in cardModels due to filtering.
    private var focusedChoreModel: ChoreModel? = nil
    
    /// Stores the assignment of the focused occurrence so it remains visible
    /// even if it no longer matches the active user filter.
    private var focusedAssignmentRecordID: CKRecord.ID? = nil

    /// A copy of the focused occurrence, kept visible even if it no longer matches the filters.
    private var focusedAssignmentModel: RecurrentAssignmentModel? = nil
    
    /// Tracks which cards are currently in the flipped state (180 degrees).
    private var flippedIndices: Set<Int> = []
    /// Tracks which cards should render their back face based on animation timing.
    private var backVisibleIndices: Set<Int> = []
    /// The occurrence backing the details card in the list layout.
    var focusedOccurrence: ChoreOccurrence? {
        guard let focusedIndex, visibleOccurrences.indices.contains(focusedIndex) else { return nil }
        return visibleOccurrences[focusedIndex]
    }
    
    // Constants for animation tuning
    /// How long a card takes to flip, in seconds.
    private let flipDuration: Double = 0.6
    /// Spring response of the focus animation.
    private let focusSpringResponse: Double = 0.4
    /// Spring damping of the focus animation.
    private let focusSpringDamping: Double = 0.75
    
    // MARK: - Checking for New Users
    
    /// Prefix of the `UserDefaults` key holding the members this device already knows about.
    /// The house ID is appended (see ``allUsersKey(houseID:)``), so each house keeps its own list.
    private static let allUsers = "chores.allUsers"
    
    /// `true` when someone joined the house since the last check. The view sets it back to
    /// `false` when the pop-up closes (the list is already saved by ``checkNewUser(users:)``).
    var showNewUserPopUp = false
    
    /// Whether this device's user created the house (only the admin can redo the division, so
    /// only the admin sees the pop-up). `nil` until resolved; resolved once per view model,
    /// which is rebuilt when the user switches houses.
    @ObservationIgnored
    private var isHouseAdmin: Bool?
    
    // MARK: - Filtering State
    
    /// Whether any filter is active.
    var isFilterOn: Bool = false
    /// The filters the user picked.
    var filterChoices = ChoreFilters()
    
    /// When `true`, occurrences on the same day are ordered most urgent first.
    ///
    /// The list is always ordered by day (nearest first) regardless — that part isn't a user
    /// choice, since the list layout groups occurrences under one header per day.
    var isSortedByUrgency: Bool = false {
        didSet {
            guard oldValue != isSortedByUrgency else { return }
            rebuildDerivedState()
        }
    }
    
    /// The list of chores rendered by the UI, respecting active filters.
    private(set) var visibleChores: [ChoreModel] = []
    
    /// Occurrences rendered by the list layout — one row per scheduled day.
    private(set) var visibleOccurrences: [ChoreOccurrence] = []
    
    /// How many future occurrences of the same chore the list shows.
    private let occurrencesPerChore = 15
    
    /// Everyone responsible for a one-off chore: its current responsible plus its responsible list.
    private func responsibleUserIDs(of chore: ChoreModel) -> Set<CKRecord.ID> {
        var ids = Set((chore.allResponsibleUsersReference ?? []).map(\.recordID))
        if let current = chore.currentResponsibleReference {
            ids.insert(current.recordID)
        }
        return ids
    }
    
    /// Rebuilds the flattened list of occurrences from the currently visible chores.
    ///
    /// Recurring chores contribute one row per future assignment (capped by
    /// `occurrencesPerChore`); one-off chores contribute a single row.
    ///
    /// - Note: This method has been reverted to not enforce forced occurrences from
    ///   focusedChoreAssignments, only from focusedChoreModel and focusedChoreRecordID.
    private func rebuildVisibleOccurrences() {
        let selectedUserIDs = Set(filterChoices.users.compactMap { $0.recordID })
        let today = Calendar.current.startOfDay(for: Date())
        var occurrences: [ChoreOccurrence] = []
        
        for chore in visibleChores {
            let assignments = futureAssignments(for: chore)
            
            if assignments.isEmpty {
                // The list never shows past days: a one-off chore due before today is left
                // out. (Recurring occurrences are already limited to today onward by
                // `futureAssignments(for:)`.)
                if let dueDate = chore.dueDate, dueDate < today { continue }
                
                // One-off chore: filtered by its own responsible and done state
                if isFilterOn {
                    // A one-off chore made in the form only has `allResponsibleUsers` (its
                    // `currentResponsible` stays empty until someone picks it up), so match
                    // against both. Reading only `currentResponsible` let it slip through
                    // every user filter, even for users who aren't responsible for it.
                    if !selectedUserIDs.isEmpty,
                       selectedUserIDs.isDisjoint(with: responsibleUserIDs(of: chore)) { continue }
                    
                    if let state = filterChoices.state, chore.isDone != state { continue }
                }
                occurrences.append(ChoreOccurrence(chore: chore, assignment: nil))
            } else {
                let matching = assignments.filter { assignment in
                    guard isFilterOn else { return true }
                    
                    if !selectedUserIDs.isEmpty {
                        let assignedIDs = Set((assignment.userReferences ?? []).map(\.recordID))
                        guard !assignedIDs.isDisjoint(with: selectedUserIDs) else { return false }
                    }
                    
                    if let state = filterChoices.state, assignment.isCompleted != state {
                        return false
                    }
                    
                    return true
                }
                
                for assignment in matching.prefix(occurrencesPerChore) {
                    occurrences.append(ChoreOccurrence(chore: chore, assignment: assignment))
                }
            }
        }
        
        // Revert forced showing of focused chore occurrences to previous behavior:
        // Keep focused chore occurrences visible even if filtered out by adding one occurrence
        // for the focused chore from focusedChoreModel (no assignments forced).
        if let focusedAssignment = focusedAssignmentModel,
           let focusedAssignmentID = focusedAssignmentRecordID,
           !occurrences.contains(where: {
               $0.assignment?.recordID == focusedAssignmentID
           }),
           let focusedChore = focusedChoreModel {
            occurrences.append(
                ChoreOccurrence(
                    chore: focusedChore,
                    assignment: focusedAssignment
                )
            )
        }
        
        visibleOccurrences = occurrences.sorted(by: self.areInIncreasingOrder)
        
        // Only the list layout indexes into `visibleOccurrences`. The grid focuses by index into
        // `visibleChores` (already restored by `rebuildVisibleChores()`), and a chore can have
        // up to `occurrencesPerChore` occurrences, so the two indexes differ: overwriting it here
        // moved the focus to the wrong card, or dropped it, on every refresh in the grid.
        guard layoutMode == .list else { return }

        if let focusedAssignmentID = focusedAssignmentRecordID,
           let index = visibleOccurrences.firstIndex(where: {
               $0.assignment?.recordID == focusedAssignmentID
           }) {
            focusedIndex = index
        }
        else if let focusedChoreID = focusedChoreRecordID,
           let index = visibleOccurrences.firstIndex(where: {
               $0.chore.recordID == focusedChoreID
           }) {
            focusedIndex = index
        }
        else {
            focusedIndex = nil
        }
    }
    
    // MARK: - Sorting
    
    /// Ordering for the list layout.
    ///
    /// Always by calendar day first — nearest first, undated last — since the list groups
    /// occurrences under one header per day.
    private func areInIncreasingOrder(_ a: ChoreOccurrence, _ b: ChoreOccurrence) -> Bool {
        let dayOrder = compareDay(a, b)
        if dayOrder != .orderedSame { return dayOrder == .orderedAscending }
        
        let doneA = a.assignment?.isCompleted ?? a.chore.isDone
        let doneB = b.assignment?.isCompleted ?? b.chore.isDone
        if doneA != doneB { return !doneA }
        
        if isSortedByUrgency {
            let urgencyOrder = compareUrgency(a, b)
            if urgencyOrder != .orderedSame { return urgencyOrder == .orderedAscending }
        }
        
        if let dateA = a.day, let dateB = b.day, dateA != dateB {
            return dateA < dateB
        }
        return a.chore.name.localizedCaseInsensitiveCompare(b.chore.name) == .orderedAscending
    }
    
    /// Nearest calendar day first (ignoring the time of day); undated occurrences go last.
    private func compareDay(_ a: ChoreOccurrence, _ b: ChoreOccurrence) -> ComparisonResult {
        let calendar = Calendar.current
        let dayA = a.day.map { calendar.startOfDay(for: $0) }
        let dayB = b.day.map { calendar.startOfDay(for: $0) }
        
        switch (dayA, dayB) {
        case let (dayA?, dayB?):
            if dayA == dayB { return .orderedSame }
            return dayA < dayB ? .orderedAscending : .orderedDescending
        case (nil, _?): return .orderedDescending
        case (_?, nil): return .orderedAscending
        case (nil, nil): return .orderedSame
        }
    }
    
    /// Most urgent first.
    private func compareUrgency(_ a: ChoreOccurrence, _ b: ChoreOccurrence) -> ComparisonResult {
        let priorityA = a.chore.priorityTag.intValue
        let priorityB = b.chore.priorityTag.intValue
        if priorityA == priorityB { return .orderedSame }
        return priorityA > priorityB ? .orderedAscending : .orderedDescending
    }
    
    /// Recomputes the visible lists after a local change, without hitting CloudKit.
    @MainActor
    func refreshVisible() {
        rebuildDerivedState()
    }
    
    /// Rebuilds every index and every derived collection, in dependency order.
    private func rebuildDerivedState() {
        rebuildIndexes()
        rebuildLoadByDay()
        rebuildVisibleChores()
        rebuildUnassignedItems()
        rebuildDashboard()
        dataVersion &+= 1
    }
    
    /// Rebuilds ``assignmentsByID``, ``futureAssignmentsByChore`` and ``nextDateByChore``.
    private func rebuildIndexes() {
        if let viewer = dashboardUser {
            let sameOwner = userModels.filter { $0.ownerRecordName == viewer.ownerRecordName }
            viewerRecordIDs = Set((sameOwner + [viewer]).compactMap(\.recordID))
        } else {
            viewerRecordIDs = []
        }
        
        assignmentsByID = Dictionary(
            dailyAssignments.compactMap { assignment in
                assignment.recordID.map { ($0, assignment) }
            },
            uniquingKeysWith: { _, latest in latest }
        )
        
        let today = Calendar.current.startOfDay(for: Date())
        
        futureAssignmentsByChore.removeAll(keepingCapacity: true)
        nextDateByChore.removeAll(keepingCapacity: true)
        
        for chore in cardModels {
            guard let choreID = chore.recordID else { continue }
            
            let future = (chore.dailyAssignmentsReference ?? [])
                .compactMap { assignmentsByID[$0.recordID] }
                .filter { $0.day >= today }
                .sorted { $0.day < $1.day }
            
            futureAssignmentsByChore[choreID] = future
            
            if let next = future.first?.day ?? chore.dueDate {
                nextDateByChore[choreID] = next
            }
        }
    }
    
    /// Recomputes ``dashboard`` from the chores and assignments already in memory.
    private func rebuildDashboard() {
        guard let dashboardUser else {
            dashboard = nil
            return
        }
        
        let model = dashboard ?? DashboardModel(user: dashboardUser)
        model.user = dashboardUser
        model.setup(chores: cardModels, assignments: dailyAssignments)
        dashboard = model
    }
    
    // MARK: - Grid Visibility
    ///
    /// > Note: `1` (tomorrow) is intentional while the schedule is being tested, because
    /// > ``TaskSchedulerEngine/schedule(chores:users:)`` seeds its window starting *tomorrow*,
    /// > so "today" is empty right after a division is generated. Set this to `0` for
    /// > production — and flip ``HardwareDailyChoresViewModel/dayOffsetFromToday`` together with
    /// > it, since the e-paper dashboard has to show the same day the app does. The progress
    /// > cards (``DashboardModel``) read this too, so they follow automatically.
    static let gridDayOffsetFromToday = 0
    
    /// The single day the grid layout renders, normalised to the start of that day.
    /// - Parameter reference: The day to count from. Defaults to now; injectable for tests.
    static func gridTargetDay(from reference: Date = Date()) -> Date {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: reference)
        return calendar.date(byAdding: .day, value: gridDayOffsetFromToday, to: startOfToday)
        ?? startOfToday
    }
    
    /// Whether `chore` belongs in the grid layout, which shows exactly one day at a time.
    ///
    /// 1. *the grid shows a single day* — the original date check; and
    /// 2. *hide a chore once that day's occurrence is done* — added later as an early return:
    ///
    /// - Parameter chore: The chore to test.
    /// - Returns: `true` when the chore has open work on ``gridTargetDay(from:)``.
    ///
    /// 3. *the grid is personal ("Suas Tarefas")* — it shows the viewer's own work for that day:
    ///    the occurrences assigned to them **and** every chore they are responsible for, even on
    ///    days the rotation gave the occurrence to someone else. Before, responsibility was
    ///    ignored, so a responsible user off the current rotation never saw the chore.
    private func isVisibleInGrid(_ chore: ChoreModel) -> Bool {
        guard !chore.isDone else { return false }
        
        let targetDay = Self.gridTargetDay()
        
        if let refs = chore.dailyAssignmentsReference, !refs.isEmpty {
            let openOccurrences = getAssignments(for: chore, on: targetDay).filter { !$0.isCompleted }
            guard !openOccurrences.isEmpty else { return false }
            // Viewer not resolved yet (e.g. offline): keep showing the day's chores.
            guard !viewerRecordIDs.isEmpty else { return true }
            
            let isMyTurn = openOccurrences.contains { assignment in
                let assignedIDs = Set((assignment.userReferences ?? []).map(\.recordID))
                return !assignedIDs.isDisjoint(with: viewerRecordIDs)
            }
            return isMyTurn || isViewerResponsible(for: chore)
        }
        
        guard let dueDate = chore.dueDate,
              Calendar.current.isDate(dueDate, inSameDayAs: targetDay) else { return false }
        guard !viewerRecordIDs.isEmpty else { return true }
        return isViewerResponsible(for: chore)
    }
    
    /// Whether the viewer is in the chore's responsible list (or its current responsible),
    /// regardless of whose turn it is in the rotation.
    func isViewerResponsible(for chore: ChoreModel) -> Bool {
        var responsibleIDs = Set((chore.allResponsibleUsersReference ?? []).map(\.recordID))
        if let current = chore.currentResponsibleReference {
            responsibleIDs.insert(current.recordID)
        }
        return !responsibleIDs.isDisjoint(with: viewerRecordIDs)
    }
    
    /// Rebuilds and caches the list of visible chores based on active filters and sorting rules.
    ///
    /// Force add focused card to visibleChores even if it does not match current filters, to keep details open until user closes.
    private func rebuildVisibleChores() {
        // Whether the focused card is showing its details, captured before the lists change
        // and the card possibly moves to another index. See `reconcileFlipState(...)`.
        let previousFocusedIndex = focusedIndex
        let wasFlipped = previousFocusedIndex.map { flippedIndices.contains($0) } ?? false
        let wasShowingBack = previousFocusedIndex.map { backVisibleIndices.contains($0) } ?? false
        
        // Use focusedChoreRecordID to ensure focused chore remains visible regardless of filters
        let base = layoutMode == .grid
        ? cardModels.filter { isVisibleInGrid($0) }
        : (isFilterOn ? applyFilters(to: cardModels) : cardModels)
        
        // If there is a focused chore recordID, ensure its card appears in the visibleChores,
        // even if not matching filters.
        var result = base
        if let recID = focusedChoreRecordID, !base.contains(where: { $0.recordID == recID }) {
            if let forcedChore = cardModels.first(where: { $0.recordID == recID }) {
                result.append(forcedChore)
            } else if let tempChore = focusedChoreModel, tempChore.recordID == recID {
                result.append(tempChore) // Use local copy if not found in cardModels
            }
        }
        
        visibleChores = result.sorted { a, b in
            let dateA = nextDate(for: a)
            let dateB = nextDate(for: b)
            
            switch (dateA, dateB) {
            case let (dA?, dB?) where dA != dB: return dA < dB
            case (nil, _?): return false
            case (_?, nil): return true
            default: break
            }
            
            return a.priorityTag.intValue > b.priorityTag.intValue
        }
        
        // Restore focus index to the currently focused chore's index if still present; otherwise clear focus.
        if let recID = focusedChoreRecordID, let idx = visibleChores.firstIndex(where: { $0.recordID == recID }) {
            focusedIndex = idx
            
            // The focused card may have moved to another index (a finished chore is re-sorted).
            // Keep the carousel centered on it; otherwise it is left flipped off to the side
            // while another card takes the center.
            if layoutMode == .grid {
                snappedItem = Double(idx)
                draggingItem = Double(idx)
                activeIndex = idx
            }
        } else {
            focusedIndex = nil
            focusedChoreRecordID = nil
            focusedChoreModel = nil
        }
        
        rebuildVisibleOccurrences()
        
        reconcileFlipState(wasFlipped: wasFlipped, wasShowingBack: wasShowingBack)
    }
    
    /// Keeps the details face tied to the focused card.
    ///
    /// ## Bug fix: details visual left behind after completing a chore
    /// `flippedIndices`/`backVisibleIndices` are keyed by *index*, but a rebuild — which
    /// completing a chore triggers — can move the focused card to another index or drop the
    /// focus altogether. The flip state stayed on the old index, so the carousel ended up
    /// with a card still drawn as the details card (`CarouselCardFrame` shows it whenever the
    /// index is flipped) but not focused, which must never happen.
    ///
    /// The details face now follows the focus: it moves to the card's new index, and is
    /// dropped entirely when nothing is focused any more.
    private func reconcileFlipState(wasFlipped: Bool, wasShowingBack: Bool) {
        guard let focusedIndex else {
            flippedIndices.removeAll()
            backVisibleIndices.removeAll()
            return
        }
        
        flippedIndices = wasFlipped ? [focusedIndex] : []
        backVisibleIndices = wasShowingBack ? [focusedIndex] : []
    }
    
    /// Whether a card is open in the middle of the screen.
    var hasFocusedCard: Bool {
        focusedIndex != nil
    }
    
    /// The chore of the open card, or `nil` when no card is open.
    var focusedChoreForDetails: ChoreModel? {
        guard let focusedIndex, visibleChores.indices.contains(focusedIndex) else { return nil }
        return visibleChores[focusedIndex]
    }
    
    // MARK: - Initialization & Data Fetching
    
    /// The refresh currently in flight, if any. See ``requestRefresh(debounce:)``.
    @ObservationIgnored
    private var refreshTask: Task<Void, Never>?
    
    /// Shows the house data held by ``HouseDataStore``.
    func fetchAllData(afterRemoteChange: Bool = false) async {
        let snapshot = afterRemoteChange
            ? await HouseDataStore.shared.refreshAfterRemoteChange()
            : await HouseDataStore.shared.load()
        
        guard !Task.isCancelled else { return }
        guard snapshot.id != appliedSnapshotID else { return }
        
        await MainActor.run {
            self.cardModels = self.choresVisible(snapshot.chores, to: snapshot.houseUser, among: snapshot.users)
            self.userModels = snapshot.users
            self.roomModels = snapshot.rooms
            self.dailyAssignments = snapshot.assignments
            self.dashboardUser = snapshot.houseUser
            
            self.rebuildDerivedState()
            
            self.appliedSnapshotID = snapshot.id
            self.hasFetchedInitially = true
            self.isLoading = false
        }
        
        await resolveHouseAdminIfNeeded()
        checkNewUser(users: self.userModels)
        
        await RoomModel.migrateStoredColorsIfNeeded(snapshot.rooms)
        await ChoreModel.migrateDurationsToMinutesIfNeeded(snapshot.chores)
    }
    
    /// Refreshes the chores and recurrent assignments after a chore or its responsible user has been modified.
    func refreshAfterChoreUpdate() async {
        async let fetchC = CloudKitManager.shared.fetchAll(ChoreModel.self)
        async let fetchA = CloudKitManager.shared.fetchAll(RecurrentAssignmentModel.self)
        
        let (chores, assignments) = await (fetchC, fetchA)
        
        guard !Task.isCancelled else { return }
        
        await MainActor.run {
            self.cardModels = self.choresVisible(chores, to: self.dashboardUser, among: self.userModels)
            self.dailyAssignments = assignments
            self.rebuildDerivedState()
        }
    }
    
    /// Private chores only reach the residents they belong to. The viewer is matched by
    /// `ownerRecordName`, so every record of the same person counts as theirs.
    private func choresVisible(_ chores: [ChoreModel], to viewer: UserModel?, among users: [UserModel]) -> [ChoreModel] {
        guard let viewer else { return chores }
        
        let isViewer: (UserModel) -> Bool = { $0.ownerRecordName == viewer.ownerRecordName }
        let viewerIDs = Set((users.filter(isViewer) + [viewer]).compactMap(\.recordID))
        let otherResidentIDs = Set(users.filter { !isViewer($0) }.compactMap(\.recordID))
        
        return chores.filter { $0.isVisible(viewerIDs: viewerIDs, otherResidentIDs: otherResidentIDs) }
    }
    
    /// Retrieves all assignment records corresponding to a specific chore on a given date.
    /// Every open (not done) occurrence due today in the house, each with who does it and
    /// whether it's the viewer's. Used to suggest the order of the viewer's day (see
    /// ``TodayChoreOrder``), which also needs the others' chores ("lavar a louça" waits for
    /// whoever cooks).
    func openOccurrencesToday() -> [(occurrence: ChoreOccurrence, userIDs: Set<CKRecord.ID>, isMine: Bool)] {
        let today = Calendar.current.startOfDay(for: Date())
        var result: [(occurrence: ChoreOccurrence, userIDs: Set<CKRecord.ID>, isMine: Bool)] = []

        for chore in cardModels {
            if let refs = chore.dailyAssignmentsReference, !refs.isEmpty {
                for assignment in getAssignments(for: chore, on: today) where !assignment.isCompleted {
                    let ids = Set((assignment.userReferences ?? []).map(\.recordID))
                    result.append((ChoreOccurrence(chore: chore, assignment: assignment), ids, !ids.isDisjoint(with: viewerRecordIDs)))
                }
            } else if let due = chore.dueDate, Calendar.current.isDate(due, inSameDayAs: today), !chore.isDone {
                result.append((ChoreOccurrence(chore: chore, assignment: nil), responsibleUserIDs(of: chore), isViewerResponsible(for: chore)))
            }
        }
        return result
    }

    func getAssignments(for chore: ChoreModel, on date: Date?) -> [RecurrentAssignmentModel] {
        guard let date,
              let refs = chore.dailyAssignmentsReference,
              !refs.isEmpty
        else { return [] }
        
        let calendar = Calendar.current
        let target = calendar.startOfDay(for: date)
        
        return refs
            .compactMap { assignmentsByID[$0.recordID] }
            .filter { calendar.isDate($0.day, inSameDayAs: target) }
    }
    
    /// Retrieves the assignment(s) for a chore on the day the *grid* layout currently shows
    /// (``gridTargetDay(from:)``).
    ///
    /// This used to resolve against ``nextDate(for:)`` — the chore's *earliest* future
    /// assignment — which is not always ``gridTargetDay()``: a daily chore, for instance, has
    /// an assignment for today *and* tomorrow, so `nextDate` points at today while
    /// ``isVisibleInGrid(_:)`` (what actually decides whether the card is still shown) checks
    /// tomorrow. Completing the card toggled the wrong day's assignment, so the one gating
    /// visibility never changed and the card stayed in the carousel after being marked done.
    ///
    /// Ordered so `.first` is the right card for the viewer: their own open occurrence first,
    /// then any open one (a responsible user off the rotation), then completed ones.
    func getAssignmentsForActiveContext(for chore: ChoreModel) -> [RecurrentAssignmentModel] {
        let viewerIDs = viewerRecordIDs
        func rank(_ assignment: RecurrentAssignmentModel) -> Int {
            let assignedIDs = Set((assignment.userReferences ?? []).map(\.recordID))
            let isMine = !assignedIDs.isDisjoint(with: viewerIDs)
            
            switch (isMine, assignment.isCompleted) {
            case (true, false): return 0
            case (false, false): return 1
            case (true, true): return 2
            case (false, true): return 3
            }
        }
        return getAssignments(for: chore, on: Self.gridTargetDay())
            .enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }
    
    /// One key per house: switching houses must not compare the new house with the old one.
    private static func allUsersKey(houseID: String) -> String {
        "\(allUsers).\(houseID)"
    }
    
    /// Members (`ownerRecordName`) already known in that house. Empty when nothing was saved yet.
    private func allUsersArray(houseID: String) -> [String] {
        UserDefaults.standard.array(forKey: Self.allUsersKey(houseID: houseID)) as? [String] ?? []
    }

    /// Saves the list of members this device already knows for `houseID` (see ``allUsersKey(houseID:)``).
    func updateAllUsers(users: [String], houseID: String) {
        UserDefaults.standard.set(users, forKey: Self.allUsersKey(houseID: houseID))
    }
    
    /// Finds out once whether the user is the house admin, the same way the rest of the app
    /// does (`HouseModel.isAdmin()`). Needs `await`, so it runs before ``checkNewUser(users:)``,
    /// which stays synchronous.
    private func resolveHouseAdminIfNeeded() async {
        guard isHouseAdmin == nil,
              let house = try? await CloudKitManager.shared.currentHouse()
        else { return }
        isHouseAdmin = await house.isAdmin() == true
    }
    
    /// Opens the "new member" pop-up on demand (from the notification), with the same rule as
    /// the automatic check: only the admin can redo the division, so residents get nothing.
    func presentNewUserPopUp() {
        guard isHouseAdmin == true else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            showNewUserPopUp = true
        }
    }
    
    /// Compares the house members with the ones saved last time and turns ``showNewUserPopUp``
    /// on when someone new shows up and the user is the house admin.
    ///
    /// People are matched by `ownerRecordName` (the iCloud account), not `recordID`: the same
    /// person can have more than one `UserModel`, and that must not look like a new member.
    func checkNewUser(users: [UserModel]) {
        // Nobody came back (e.g. the fetch failed offline): nothing to compare, and saving an
        // empty list would throw away what we know.
        guard !users.isEmpty,
              let houseID = users.first?.houseReference?.recordID.recordName
        else { return }
        
        let savedUsers = Set(allUsersArray(houseID: houseID))
        let currentUsers = Set(users.map { $0.ownerRecordName })
        
        // Always remember who is in the house *now*, after comparing. This also drops whoever
        // left, so if they come back later they show up as new again.
        defer { updateAllUsers(users: Array(currentUsers), houseID: houseID) }
        
        // First check in this house (fresh install, or the user just joined): everyone is
        // already here, so just save the list without showing anything.
        guard !savedUsers.isEmpty else { return }
        
        let newUsers = currentUsers.subtracting(savedUsers)
        
        // Residents still get their list updated (by the `defer` above), they just don't see
        // the pop-up: only the admin can start a new division.
        if !newUsers.isEmpty, isHouseAdmin == true {
            showNewUserPopUp = true
        }
    }
    
    // MARK: - Synchronous Data Helpers
    
    /// The room of `chore`, from the rooms already in memory.
    func getRoom(for chore: ChoreModel) -> RoomModel? {
        guard let refID = chore.roomReference?.recordID else { return nil }
        return roomModels.first { $0.recordID == refID }
    }
    
    /// The members responsible for `chore` (from its occurrences, for a recurring chore).
    func getUsers(for chore: ChoreModel) -> [UserModel] {
        // Recurring: users come from the daily assignments
        if let refs = chore.dailyAssignmentsReference, !refs.isEmpty {
            var userIDs = Set<CKRecord.ID>()
            for ref in refs {
                if let assignment = assignmentsByID[ref.recordID], let userRefs = assignment.userReferences {
                    userIDs.formUnion(userRefs.map(\.recordID))
                }
            }
            return userModels.filter { $0.recordID.map { userIDs.contains($0) } ?? false }
        }
        
        // One-off: explicit rotation list
        guard let refs = chore.allResponsibleUsersReference else { return [] }
        let ids = Set(refs.compactMap { $0.recordID })
        return userModels.filter { $0.recordID.map { ids.contains($0) } ?? false }
    }
    
    // MARK: - Layout Control
    
    /// Switches between the carousel and the list.
    func toggleLayout() {
        layoutMode = layoutMode == .grid ? .list : .grid
        rebuildDerivedState()
    }
    
    // MARK: - isDone Chore Logic
    
    /// Whether `chore` is done: the occurrence's flag when there is one, otherwise the chore's.
    func isDone(for chore: ChoreModel, assignment: RecurrentAssignmentModel?) -> Bool {
        assignment?.isCompleted ?? chore.isDone
    }
    
    /// Toggles the chore's (or, for a recurring chore, this specific day's) completion state
    /// and persists it
    @MainActor
    @discardableResult
    func toggle(chore: ChoreModel) async -> Bool {
        let willBeDone = !chore.isDone
        var doer: UserModel?
        if !willBeDone {
            doer = await chore.userThatHaveDone
        }
        
        guard await chore.toggle() else { return false }
        refreshVisible()
        
        if willBeDone {
            notifyOwnersChoreDone(chore, assignment: nil)
            return await ScoreManager.shared.assignScoreForMyUser(chore: chore)
        }
        if let doer {
            return await ScoreManager.shared.removeScore(chore: chore, for: doer)
        }
        return await ScoreManager.shared.removeScoreForMyUser(chore: chore)
    }

    /// Checks or unchecks one occurrence and gives or takes back the points.
    /// - Returns: `false` when the change couldn't be saved.
    @MainActor
    @discardableResult
    func toggle(assignment: RecurrentAssignmentModel) async -> Bool {
        let willBeDone = !assignment.isCompleted
        var doer: UserModel?
        if !willBeDone {
            doer = await assignment.userThatHaveDone
        }
        
        guard await assignment.toggle() else { return false }
        refreshVisible()
        
        if willBeDone {
            if let choreID = assignment.choreReference?.recordID,
               let chore = cardModels.first(where: { $0.recordID == choreID }) {
                notifyOwnersChoreDone(chore, assignment: assignment)
            }
            return await ScoreManager.shared.assignScoreForMyUser(assignment: assignment)
        }
        if let doer {
            return await ScoreManager.shared.removeScore(assignment: assignment, for: doer)
        }
        return await ScoreManager.shared.removeScoreForMyUser(assignment: assignment)
    }
    
    /// Tells the members a chore was assigned to that someone else did it. Does nothing when
    /// nobody has it or the current user is one of them.
    private func notifyOwnersChoreDone(_ chore: ChoreModel, assignment: RecurrentAssignmentModel?) {
        var ownerRefs = assignment?.userReferences ?? []
        if assignment == nil {
            ownerRefs = chore.allResponsibleUsersReference ?? []
            if let current = chore.currentResponsibleReference,
               !ownerRefs.contains(where: { $0.recordID == current.recordID }) {
                ownerRefs.append(current)
            }
        }
        
        let ownerIDs = Set(ownerRefs.map(\.recordID))
        guard !ownerIDs.isEmpty, !viewerRecordIDs.isEmpty,
              ownerIDs.isDisjoint(with: viewerRecordIDs),
              let doer = dashboardUser else { return }
        
        let owners = userModels.filter { user in user.recordID.map(ownerIDs.contains) ?? false }
        guard !owners.isEmpty else { return }
        
        Task {
            await NotificationManager.shared.notifyChoreDone(
                chore, assignment: assignment, by: doer.name, for: owners
            )
        }
    }
    
    // MARK: - Postpone
    
    /// "Adiar": moves the occurrence being shown `days` forward.
    ///
    /// Before, the details card called `ChoreModel.postpone`, which only changes `dueDate` —
    /// ignored by recurring chores, whose days live in their assignments — and then re-fetched
    /// everything from CloudKit, whose queries can still return the old record right after a
    /// save. Now the right record is moved (the occurrence for recurring chores, the chore for
    /// one-offs) and the lists are rebuilt from memory.
    ///
    /// - Parameters:
    ///   - assignment: The occurrence shown by the card, if already known.
    /// - Returns: `true` when the new date was saved.
    @MainActor
    func postpone(chore: ChoreModel, assignment: RecurrentAssignmentModel?, byDays days: Int) async -> Bool {
        // Daily chores already have an occurrence every day; postponing would only stack two
        // occurrences on the same day.
        guard chore.frequency != .daily else { return false }
        
        let isRecurring = !(chore.dailyAssignmentsReference ?? []).isEmpty
        
        if isRecurring {
            guard let occurrence = assignment ?? getAssignmentsForActiveContext(for: chore).first,
                  await occurrence.postpone(byDays: days) else { return false }
            refreshVisible()
            await syncSingleAssignmentToCalendar(for: occurrence, chore: chore)
        } else {
            guard await chore.postpone(byDays: days) else { return false }
            refreshVisible()
            await syncSingleChoreToCalendar(chore)
        }
        return true
    }
    
    // MARK: - Delete
    
    /// What ``removeOccurrenceLocally(chore:targetOccurrences:)`` took out of the in-memory
    /// state, kept around so a failed CloudKit delete can restore it exactly.
    struct RemovedOccurrenceSnapshot {
        let cardModels: [ChoreModel]
        let assignments: [RecurrentAssignmentModel]
    }
    
    /// Removes the given occurrence(s) from ``cardModels``/``dailyAssignments`` right away,
    /// with no `await` and no network round trip, and refreshes every derived list to match.
    ///
    /// This has to run synchronously, *before* the actual CloudKit delete, because `List`'s
    /// native swipe-to-delete expects its backing data to have already changed by the time
    /// the swipe animation finishes: if the data only changes later (after an `await` on the
    /// network), the row disappears, flashes back once SwiftUI notices nothing really
    /// changed yet, then disappears again once the delete eventually completes.
    ///
    /// See ``ChoreModel/delete(targetOccurrences:)`` for the exact rule this follows: no
    /// occurrences (or a non-recurring chore) removes the whole chore; one or more removes
    /// just those days.
    @MainActor
    @discardableResult
    func removeOccurrenceLocally(chore: ChoreModel, targetOccurrences: [RecurrentAssignmentModel]) -> RemovedOccurrenceSnapshot {
        let deletesWholeChore = chore.frequency == .none || targetOccurrences.isEmpty
        
        var removedCardModels: [ChoreModel] = []
        var removedAssignments: [RecurrentAssignmentModel] = []
        
        if deletesWholeChore {
            removedCardModels = cardModels.filter { $0.recordID == chore.recordID }
            removedAssignments = dailyAssignments.filter { $0.choreReference?.recordID == chore.recordID }
            cardModels.removeAll { $0.recordID == chore.recordID }
            dailyAssignments.removeAll { $0.choreReference?.recordID == chore.recordID }
        } else {
            let deletedIDs = Set(targetOccurrences.compactMap { $0.recordID })
            removedAssignments = dailyAssignments.filter { assignment in
                guard let id = assignment.recordID else { return false }
                return deletedIDs.contains(id)
            }
            dailyAssignments.removeAll { assignment in
                guard let id = assignment.recordID else { return false }
                return deletedIDs.contains(id)
            }
        }
        
        if focusedOccurrence?.chore.recordID == chore.recordID {
            clearFocusedDetails()
        }
        
        refreshVisible()
        
        return RemovedOccurrenceSnapshot(cardModels: removedCardModels, assignments: removedAssignments)
    }
    
    /// Persists a deletion already applied locally by
    /// ``removeOccurrenceLocally(chore:targetOccurrences:)``. On failure, restores exactly
    /// what that call removed and sets ``errorMessage``.
    @MainActor
    @discardableResult
    func persistDelete(
        chore: ChoreModel,
        targetOccurrences: [RecurrentAssignmentModel],
        restoring snapshot: RemovedOccurrenceSnapshot
    ) async -> Bool {
        guard await chore.delete(targetOccurrences: targetOccurrences) else {
            cardModels.append(contentsOf: snapshot.cardModels)
            dailyAssignments.append(contentsOf: snapshot.assignments)
            refreshVisible()
            
            errorMessage = CloudKitManager.shared.errorMessage ?? L10n.tr("Não foi possível excluir a tarefa.")
            return false
        }
        
        return true
    }
    
    /// Deletes a chore, or — for a recurring chore — just the given occurrence(s), and
    /// refreshes every derived list immediately.
    ///
    /// Combines ``removeOccurrenceLocally(chore:targetOccurrences:)`` and
    /// ``persistDelete(chore:targetOccurrences:restoring:)`` for callers — like the edit
    /// screen's delete button — that don't need to control the timing between them. The
    /// chores list's swipe-to-delete calls the two halves directly instead, so the local
    /// removal happens synchronously, in step with `List`'s own delete animation, before the
    /// network call runs in the background.
    ///
    /// - Returns: `true` on success. On failure, `errorMessage` is set and `false` is
    ///   returned.
    @discardableResult
    func delete(chore: ChoreModel, targetOccurrences: [RecurrentAssignmentModel] = []) async -> Bool {
        let snapshot = await removeOccurrenceLocally(chore: chore, targetOccurrences: targetOccurrences)
        return await persistDelete(chore: chore, targetOccurrences: targetOccurrences, restoring: snapshot)
    }
    
    // MARK: - Filtering Logic
    
    /// Applies the active filters to a list of chores.
    private func applyFilters(to chores: [ChoreModel]) -> [ChoreModel] {
        var result = chores
        
        if !filterChoices.tags.isEmpty {
            result = result.filter { filterChoices.tags.contains($0.priorityTag) }
        }
        
        if !filterChoices.frequencies.isEmpty {
            result = result.filter { filterChoices.frequencies.contains($0.frequency) }
        }
        
        if !filterChoices.rooms.isEmpty {
            let roomIDs = Set(filterChoices.rooms.compactMap { $0.recordID })
            result = result.filter { chore in
                guard let roomID = chore.roomReference?.recordID else { return false }
                return roomIDs.contains(roomID)
            }
        }
        
        return result
    }
    
    /// Changes the filter option
    func addOrRemoveFilter(user: UserModel? = nil, tag: PriorityTag? = nil, frequency: Recurrence? = nil, room: RoomModel? = nil, state: Bool? = nil) {
        if let user {
            if filterChoices.users.contains(user) {
                filterChoices.users.removeAll { $0 == user }
            } else {
                filterChoices.users.append(user)
            }
        }
        
        if let tag = tag {
            if !filterChoices.tags.contains(tag) {
                filterChoices.tags.append(tag)
            } else {
                filterChoices.tags.removeAll { $0 == tag }
            }
        }
        
        if let frequency = frequency {
            if !filterChoices.frequencies.contains(frequency) {
                filterChoices.frequencies.append(frequency)
            } else {
                filterChoices.frequencies.removeAll { $0 == frequency }
            }
        }
        
        if let room {
            if !filterChoices.rooms.contains(room) {
                filterChoices.rooms.append(room)
            } else {
                filterChoices.rooms.removeAll { $0 == room }
            }
        }
        
        if let state = state {
            if filterChoices.state != state {
                filterChoices.state = state
            } else {
                filterChoices.state = nil
            }
        }
        
        isFilterOn = !filterChoices.users.isEmpty
        || !filterChoices.tags.isEmpty
        || !filterChoices.frequencies.isEmpty
        || !filterChoices.rooms.isEmpty
        || filterChoices.state != nil
        
        // Rebuild visible chores after changing filters.
        rebuildDerivedState()
    }
    
    /// Clears every filter.
    func resetFilter() {
        isFilterOn = false
        filterChoices = ChoreFilters()
        
        //Rebuild visible chores after resetting filters.
        rebuildDerivedState()
    }
    
    /// Every future assignment of a chore, sorted by day.
    /// Returns an empty array for one-off chores, which have no assignments.
    func futureAssignments(for chore: ChoreModel) -> [RecurrentAssignmentModel] {
        guard let choreID = chore.recordID else { return [] }
        return futureAssignmentsByChore[choreID] ?? []
    }
    
    /// The next scheduled date for a chore, whether it comes from a daily
    /// assignment (recurring) or from its own due date (one-off).
    func nextDate(for chore: ChoreModel) -> Date? {
        guard let choreID = chore.recordID else { return chore.dueDate }
        return nextDateByChore[choreID] ?? chore.dueDate
    }
    
    // MARK: - Focus & Flip Interactions
    
    /// Whether the card at `index` is the open one.
    func isFocused(_ index: Int) -> Bool {
        focusedIndex == index
    }
    
    /// Opens the card at `index` right away (no closing animation for the previous one).
    func focusImmediately(_ index: Int) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            focusedIndex = index
            // Store the focused chore's recordID to keep it visible regardless of filtering
            if visibleChores.indices.contains(index) {
                let chore = visibleChores[index]
                focusedChoreRecordID = chore.recordID
                focusedChoreModel = chore // Keep a local copy for visibility
            } else {
                focusedChoreRecordID = nil
                focusedChoreModel = nil
            }
        }
    }
    
    /// Opens the card at `index`, closing the open one first.
    func focus(_ index: Int) {
        guard focusedIndex != index else { return }
        
        if focusedIndex != nil {
            withAnimation(.easeOut(duration: 0.15)) {
                focusedIndex = nil
                focusedChoreRecordID = nil
                focusedChoreModel = nil
            }
        }
        
        withAnimation(.spring(response: focusSpringResponse, dampingFraction: focusSpringDamping)) {
            snappedItem = Double(index)
            draggingItem = Double(index)
            activeIndex = index
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + focusSpringResponse) { [weak self] in
            guard let self, self.activeIndex == index else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                self.focusedIndex = index
                if self.visibleChores.indices.contains(index) {
                    let chore = self.visibleChores[index]
                    self.focusedChoreRecordID = chore.recordID
                    self.focusedChoreModel = chore // Keep a local copy
                } else {
                    self.focusedChoreRecordID = nil
                    self.focusedChoreModel = nil
                }
            }
        }
    }
    
    /// Opens the card at `index` and flips it to show its details.
    func focusAndFlip(_ index: Int) {
        if let old = focusedIndex, old != index {
            if flippedIndices.contains(old) {
                flip(old)
            }
        }
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            snappedItem = Double(index)
            draggingItem = Double(index)
            activeIndex = index
            focusedIndex = index
            // Store focused chore recordID for visibility during filters
            if visibleChores.indices.contains(index) {
                let chore = visibleChores[index]
                focusedChoreRecordID = chore.recordID
                focusedChoreModel = chore // Keep a local copy
            } else {
                focusedChoreRecordID = nil
                focusedChoreModel = nil
            }
        }
        
        flip(index)
    }
    
    /// Closes the open card, flipping it back if needed.
    func clearFocus() {
        if let old = focusedIndex {
            if flippedIndices.contains(old) {
                flip(old)
            }
            withAnimation(.easeOut(duration: 0.2)) {
                focusedIndex = nil
                focusedChoreRecordID = nil
                focusedChoreModel = nil
                focusedAssignmentRecordID = nil
                focusedAssignmentModel = nil
            }
        }
    }
    
    /// Opens the card at `index` already showing its details (back face).
    func focusDetailsImmediately(_ index: Int) {
        flippedIndices.insert(index)
        backVisibleIndices.insert(index)

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            focusedIndex = index

            guard visibleOccurrences.indices.contains(index) else {
                focusedChoreRecordID = nil
                focusedChoreModel = nil
                focusedAssignmentRecordID = nil
                focusedAssignmentModel = nil
                return
            }

            let occurrence = visibleOccurrences[index]

            focusedChoreRecordID = occurrence.chore.recordID
            focusedChoreModel = occurrence.chore

            focusedAssignmentRecordID = occurrence.assignment?.recordID
            focusedAssignmentModel = occurrence.assignment
        }
    }
    
    /// Closes the card opened by ``focusDetailsImmediately(_:)``.
    func clearFocusedDetails() {
        if let index = focusedIndex {
            flippedIndices.remove(index)
            backVisibleIndices.remove(index)
        }
        
        withAnimation(.easeOut(duration: 0.2)) {
            focusedIndex = nil
            focusedChoreRecordID = nil
            focusedChoreModel = nil
            focusedAssignmentRecordID = nil
            focusedAssignmentModel = nil
        }
    }
    
    /// The card's flip angle: `180` when flipped, `0` otherwise.
    func flipRotation(_ index: Int) -> Double {
        flippedIndices.contains(index) ? 180 : 0
    }
    
    /// Whether the card at `index` shows its back face.
    func isShowingBack(_ index: Int) -> Bool {
        backVisibleIndices.contains(index)
    }
    
    /// Flips the card at `index`, switching faces halfway through the animation.
    func flip(_ index: Int) {
        let isFlipping = !flippedIndices.contains(index)
        
        withAnimation(.easeInOut(duration: flipDuration)) {
            if isFlipping {
                flippedIndices.insert(index)
            } else {
                flippedIndices.remove(index)
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + flipDuration / 2) { [weak self] in
            guard let self else { return }
            if isFlipping {
                // Skipped when the card lost its flip meanwhile (a refresh moved or cleared it).
                if self.flippedIndices.contains(index) {
                    self.backVisibleIndices.insert(index)
                }
            } else {
                self.backVisibleIndices.remove(index)
            }
        }
    }
    
    // MARK: - Carousel Geometry Math
    
    /// Whether the card at `index` is the one in the middle of the carousel.
    func isCentered(_ index: Int) -> Bool {
        abs(distance(index)) < 0.5
    }
    
    /// How far the card at `index` is from the middle, in cards (negative to the left).
    func distance(_ index: Int) -> Double {
        guard !visibleChores.isEmpty else { return 0 }
        return (draggingItem - Double(index)).remainder(dividingBy: Double(visibleChores.count))
    }
    
    /// Horizontal offset of the card at `index` on the carousel's circle.
    func xOffset(_ index: Int) -> Double {
        let fixedVisualCount: Double = 5.0
        let angle = (Double.pi * 2 / fixedVisualCount) * distance(index)
        let fixedRadius: Double = 130.0
        return sin(angle) * fixedRadius
    }
    
    /// Vertical offset of the card at `index`: cards far from the middle go lower (or off screen).
    func yOffset(_ index: Int) -> Double {
        let dist = abs(distance(index))
        let hideThreshold = hideThreshold()
        if dist > hideThreshold { return 1000 }
        return pow(dist * 17, 2) / 10
    }
    
    /// Size of the card at `index`: smaller the farther it is from the middle.
    func scaleEffect(_ index: Int) -> Double {
        let dist = abs(distance(index))
        return max(1 - dist * 0.18, 0.7)
    }
    
    /// Tilt of the card at `index`, in degrees.
    func rotationEffect(_ index: Int) -> Double {
        let dist = distance(index)
        return dist * 22
    }
    
    /// Drawing order of the card at `index`: the middle card is on top.
    func zIndex(_ index: Int) -> Double {
        1.0 - abs(distance(index)) * 0.1
    }
    
    /// Opacity of the card at `index`: cards too far from the middle are hidden.
    func opacity(_ index: Int) -> Double {
        let dist = abs(distance(index))
        return dist > hideThreshold() ? 0.0 : 1.0
    }
    
    /// How far from the middle (in cards) a card can be before it is hidden.
    private func hideThreshold() -> Double {
        return 1.5
    }
    
    // MARK: - Gesture Handling
    
    /// How many points of drag move the carousel by one card.
    private static var dragPointsPerGroup: Double { UIScreen.main.bounds.width * 0.5 }
    
    /// Moves the carousel while the user drags.
    func onDragChanged(value: DragGesture.Value) {
        clearFocus()
        draggingItem = snappedItem + value.translation.width / Self.dragPointsPerGroup
    }
    
    /// Snaps the carousel to the nearest card when the drag ends, using the drag's speed.
    func onDragEnded(value: DragGesture.Value) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            guard !visibleChores.isEmpty else { return }
            
            let velocity = value.predictedEndTranslation.width - value.translation.width
            let nudge = min(max(velocity / 700, -1), 1)
            
            let count = visibleChores.count
            draggingItem = (draggingItem + nudge)
                .rounded()
                .remainder(dividingBy: Double(count))
            
            snappedItem = draggingItem
            
            let rounded = Int(draggingItem)
            activeIndex = rounded >= 0 ? rounded : count + rounded
        }
    }
    
    // MARK: - UnassignedItem
    
    /// A chore (or a single occurrence of a recurring chore) that currently has nobody responsible for it.
    struct UnassignedItem: Identifiable {
        /// Whether the unassigned item is a one-off chore or one day of a recurring chore.
        enum ChoreType {
            /// A one-off chore with no responsible users at all.
            case oneOff
            /// One specific day of a recurring chore that has no user assigned yet.
            case recurring(assignment: RecurrentAssignmentModel)
        }
        
        let id: String
        let chore: ChoreModel
        let choreType: ChoreType
        /// The date to show next to the chore, when there is one.
        let displayDate: Date?
        
        var needsDateSelection: Bool {
            if case .oneOff = choreType, displayDate == nil { return true }
            return false
        }
        
        var isOneOffFresh: Bool {
            if case .oneOff = choreType { return true }
            return false
        }
    }
    
    /// Recomputes ``unassignedItems``.
    ///
    /// Recurring chores are found from their occurrences (each one points at its chore through
    /// ``RecurrentAssignmentModel/choreReference``), the same way the "tarefas a pegar"
    /// notifications do. The chore's own ``ChoreModel/dailyAssignmentsReference`` list is not
    /// trusted for this: it can lag behind the occurrences (the scheduler repairs it), and a chore
    /// that lagged would never show up as free to pick.
    private func rebuildUnassignedItems() {
        let today = Calendar.current.startOfDay(for: Date())
        var items: [UnassignedItem] = []
        
        // Open occurrences (upcoming, nobody responsible) and the chores that have occurrences.
        var openSlotsByChore: [CKRecord.ID: [RecurrentAssignmentModel]] = [:]
        var choresWithOccurrences: Set<CKRecord.ID> = []
        for assignment in dailyAssignments {
            guard let choreID = assignment.choreReference?.recordID else { continue }
            choresWithOccurrences.insert(choreID)
            
            let isUnassigned = assignment.userReferences?.isEmpty ?? true
            if isUnassigned, !assignment.isCompleted, assignment.day >= today {
                openSlotsByChore[choreID, default: []].append(assignment)
            }
        }
        
        // Only chores the viewer can see are offered (private chores of others stay hidden).
        for chore in cardModels {
            let choreID = chore.recordID
            let isRecurring = !(chore.dailyAssignmentsReference ?? []).isEmpty
                || choreID.map(choresWithOccurrences.contains) == true
            
            if isRecurring {
                guard let choreID, let openSlots = openSlotsByChore[choreID], !openSlots.isEmpty else { continue }
                
                if chore.frequency == .daily {
                    let earliest = openSlots.min { $0.day < $1.day }!
                    items.append(
                        UnassignedItem(
                            id: choreID.recordName,
                            chore: chore,
                            choreType: .recurring(assignment: earliest),
                            displayDate: earliest.day
                        )
                    )
                } else {
                    for assignment in openSlots {
                        items.append(
                            UnassignedItem(
                                id: assignment.recordID?.recordName ?? UUID().uuidString,
                                chore: chore,
                                choreType: .recurring(assignment: assignment),
                                displayDate: assignment.day
                            )
                        )
                    }
                }
            } else if !chore.isDone {
                let hasResponsible = chore.currentResponsibleReference != nil
                    || !(chore.allResponsibleUsersReference?.isEmpty ?? true)
                
                if !hasResponsible {
                    items.append(
                        UnassignedItem(
                            id: choreID?.recordName ?? UUID().uuidString,
                            chore: chore,
                            choreType: .oneOff,
                            displayDate: chore.dueDate
                        )
                    )
                }
            }
        }
        
        unassignedItems = items.sorted {
            ($0.displayDate ?? .distantFuture) < ($1.displayDate ?? .distantFuture)
        }
    }
    
    /// Every still-open (unclaimed, upcoming) occurrence of a chore, sorted by day.
    func openAssignments(for chore: ChoreModel) -> [RecurrentAssignmentModel] {
        futureAssignments(for: chore).filter { assignment in
            assignment.userReferences == nil || assignment.userReferences?.isEmpty == true
        }
    }
    
    /// Assigns the current user to an unassigned chore or occurrence, then refreshes local caches.
    @MainActor
    func pickForMyself(_ item: UnassignedItem) async {
        var myUser = dashboardUser
        if myUser == nil {
            myUser = await CloudKitManager.shared.currentHouseUser()
            dashboardUser = myUser
        }
        
        guard let myUserID = myUser?.recordID else { return }
        
        // Whoever holds this chore's coupon is spared it in this cycle.
        if await CouponExemption.isExempt(userID: myUserID, choreID: item.chore.recordID) {
            errorMessage = L10n.tr("Você tem o cupom dessa tarefa e não pode pegá-la neste ciclo.")
            return
        }
        
        let userRef = CKRecord.Reference(recordID: myUserID, action: .none)
        
        switch item.choreType {
        case .oneOff:
            item.chore.currentResponsibleReference = userRef
            var refs = item.chore.allResponsibleUsersReference ?? []
            if !refs.contains(where: { $0.recordID == myUserID }) {
                refs.append(userRef)
            }
            item.chore.allResponsibleUsersReference = refs
            await CloudKitManager.shared.update(item.chore)
            
            await syncSingleChoreToCalendar(item.chore)
            await refreshAfterChoreUpdate()
            
        case .recurring(let assignment):
            assignment.userReferences = [userRef]
            await CloudKitManager.shared.update(assignment)
            
            await syncSingleAssignmentToCalendar(for: assignment, chore: item.chore)
            await refreshAfterChoreUpdate()
        }
    }
    
    // MARK: - Calendar Synchronization
    
    /// Synchronizes a single, non-recurrent chore to the system calendar.
    ///
    /// This method checks if calendar synchronization is enabled in user defaults, verifies access permissions,
    /// retrieves the current user's CloudKit record ID, and upserts or removes the corresponding calendar event.
    ///
    /// - Parameter chore: The `ChoreModel` instance to be synchronized.
    /// - Returns: An asynchronous task that executes on the main actor.
    @MainActor
    func syncSingleChoreToCalendar(_ chore: ChoreModel) async {
        let isSyncEnabled = UserDefaults.standard.bool(forKey: "isCalendarSyncEnabled")
        guard isSyncEnabled else { return }
        guard await CalendarManager.shared.requestAccess() else { return }
        guard let myUser = await CloudKitManager.shared.fetchMyHouseUser(),
              let myUserID = myUser.recordID else { return }
        
        do {
            try await CalendarManager.shared.upsertOneOffEvent(for: chore, currentUserID: myUserID)
        } catch {
            print("Failed to sync single chore: \(error.localizedDescription)")
        }
    }
    
    /// Accurately synchronizes a single day's recurrent assignment.
    ///
    /// Use this method when a specific day's assignment status or assignee changes without altering the global recurrence rule.
    ///
    /// - Parameters:
    ///   - assignment: The `RecurrentAssignmentModel` representing the specific daily instance.
    ///   - chore: The parent `ChoreModel` associated with the assignment.
    /// - Returns: An asynchronous task that executes on the main actor.
    @MainActor
    func syncSingleAssignmentToCalendar(for assignment: RecurrentAssignmentModel, chore: ChoreModel) async {
        let isSyncEnabled = UserDefaults.standard.bool(forKey: "isCalendarSyncEnabled")
        guard isSyncEnabled else { return }
        guard await CalendarManager.shared.requestAccess() else { return }
        guard let myUser = await CloudKitManager.shared.fetchMyHouseUser(),
              let myUserID = myUser.recordID else { return }
        
        do {
            try await CalendarManager.shared.upsertRecurrentEvent(for: assignment, chore: chore, currentUserID: myUserID)
        } catch {
            print("Failed to sync single assignment: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Picking an unassigned chore that has no date
    
    /// The unassigned chore the user is picking a date for, or `nil`.
    var itemAwaitingDate: UnassignedItem?
    
    /// A single slot in the confirmation page: may correspond to an existing assignment or a brand new one to be created.
    struct WeeklyPickSlot: Identifiable {
        let id: UUID = UUID()
        /// nil = The user has not selected yet.
        var date: Date?
        /// An existing assignment (e.g., claiming an empty slot, or another week in a weekly chore). nil = Needs to be created.
        var existingAssignment: RecurrentAssignmentModel?
        /// Whether the date can be edited. Existing slots and "this week" slots are usually locked.
        var isDateEditable: Bool
        /// Whether this slot is checked/included for claiming.
        var included: Bool = true
    }
    
    /// Another assignment within the same weekly chore that is still open (unassigned, incomplete).
    func openSiblingWeeklyAssignment(for chore: ChoreModel, excluding: RecurrentAssignmentModel?) -> RecurrentAssignmentModel? {
        guard chore.frequency == .weekly else { return nil }
        return futureAssignments(for: chore).first { candidate in
            let isUnassigned = candidate.userReferences == nil || candidate.userReferences?.isEmpty == true
            return candidate.recordID != excluding?.recordID
            && isUnassigned
            && !candidate.isCompleted
        }
    }
    
    /// The selectable date range; falls back to "15 days starting today" if no scheduling data is available.
    var pickerWindow: Range<Date> {
        if let selectableWindow { return selectableWindow }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 15, to: today) ?? today
        return today..<end
    }
    
    /// Calculates which slots should initially be displayed based on the item and its frequency when the confirmation page opens.
    func initialPickSlots(for item: UnassignedItem) -> [WeeklyPickSlot] {
        let chore = item.chore
        
        if chore.frequency == .daily {
            let openSlots = openAssignments(for: chore)
            return openSlots.map {
                WeeklyPickSlot(date: $0.day, existingAssignment: $0, isDateEditable: false, included: false)
            }
        }
         
        if case .recurring(let assignment) = item.choreType {
            switch chore.frequency {
            case .weekly, .fortnightly, .monthly:
                return [WeeklyPickSlot(date: assignment.day, existingAssignment: assignment, isDateEditable: true)]
            default: break
            }
        }
         
        return [WeeklyPickSlot(date: nil, existingAssignment: nil, isDateEditable: true)]
    }
    
    // MARK: - Unassigned Item Pick Controls
    
    /// Tapping an item in the list: items requiring a date selection present a confirmation page.
    @MainActor
    func requestPick(_ item: UnassignedItem) {
        var needsSheet = item.needsDateSelection

        if case .recurring = item.choreType {
            switch item.chore.frequency {
            case .weekly, .fortnightly, .monthly, .daily: needsSheet = true
            default: break
            }
        }

        if needsSheet {
            dismissUnassignedList()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                itemAwaitingDate = item
            }
        } else {
            Task { await pickForMyself(item) }
        }
    }

    /// Closes the date picker card for an unassigned chore.
    @MainActor
    func dismissPickCard() {
        withAnimation(.easeOut(duration: 0.2)) {
            itemAwaitingDate = nil
        }
    }
    
    // MARK: - Unassigned List Popover Controls
        
    /// Whether the "unassigned chores" popup is currently visible.
    var isShowingUnassignedList: Bool = false
    
    /// Shows or hides the list of unassigned chores.
    @MainActor
    func toggleUnassignedList() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isShowingUnassignedList.toggle()
        }
    }
    
    /// Hides the list of unassigned chores.
    @MainActor
    func dismissUnassignedList() {
        withAnimation(.easeOut(duration: 0.2)) {
            isShowingUnassignedList = false
        }
    }
    
    /// Called after tapping "Confirm" on the confirmation page. Only slots where `included && date != nil` will be saved.
    @MainActor
    func confirmPick(_ item: UnassignedItem, slots: [WeeklyPickSlot]) async -> Bool {
        let included = slots.filter { $0.included && $0.date != nil }
        guard !included.isEmpty else { return false }
        
        var myUser = dashboardUser
        if myUser == nil {
            myUser = await CloudKitManager.shared.currentHouseUser()
            dashboardUser = myUser
        }
        guard let myUserID = myUser?.recordID else { return false }
        
        // Whoever holds this chore's coupon is spared it in this cycle.
        if await CouponExemption.isExempt(userID: myUserID, choreID: item.chore.recordID) {
            errorMessage = L10n.tr("Você tem o cupom dessa tarefa e não pode pegá-la neste ciclo.")
            return false
        }
        
        let userRef = CKRecord.Reference(recordID: myUserID, action: .none)
        let chore = item.chore
        
        // One-off chore: Update due date only
        if chore.frequency == .none {
            let previousDue = chore.dueDate
            let previousCurrent = chore.currentResponsibleReference
            let previousAll = chore.allResponsibleUsersReference
            
            chore.dueDate = included[0].date
            chore.currentResponsibleReference = userRef
            var refs = previousAll ?? []
            if !refs.contains(where: { $0.recordID == myUserID }) { refs.append(userRef) }
            chore.allResponsibleUsersReference = refs
            
            guard await CloudKitManager.shared.update(chore) else {
                chore.dueDate = previousDue
                chore.currentResponsibleReference = previousCurrent
                chore.allResponsibleUsersReference = previousAll
                return false
            }
            await syncSingleChoreToCalendar(chore)
            await refreshAfterChoreUpdate()
            return true
        }
        
        // Recurring chore: Each checked slot corresponds to an assignment (update existing ones, create new ones)
        var toUpdate: [RecurrentAssignmentModel] = []
        var toCreate: [WeeklyPickSlot] = []
        
        for slot in included {
            if let existing = slot.existingAssignment {
                existing.userReferences = [userRef]
                if slot.isDateEditable, let date = slot.date {
                    existing.day = Calendar.current.startOfDay(for: date)
                }
                toUpdate.append(existing)
            } else {
                toCreate.append(slot)
            }
        }
        
        var createdModels: [RecurrentAssignmentModel] = []
        if !toCreate.isEmpty {
            guard let room = chore.room,
                  let houseRef = room.houseReference,
                  let choreID = chore.recordID
            else { return false }
            
            let parent = CKRecord.Reference(recordID: houseRef.recordID, action: .none)
            let choreRef = CKRecord.Reference(recordID: choreID, action: .deleteSelf)
            
            for slot in toCreate {
                guard let date = slot.date else { continue }
                let model = RecurrentAssignmentModel(day: date, users: [userRef], chore: choreRef)
                guard let saved = await CloudKitManager.shared.create(model, zoneID: houseRef.recordID.zoneID, parent: parent) else {
                    let ids = createdModels.compactMap { $0.recordID }
                    if !ids.isEmpty { await CloudKitManager.shared.delete(recordIDs: ids, zoneID: houseRef.recordID.zoneID) }
                    return false
                }
                createdModels.append(saved)
            }
        }
        
        if !toUpdate.isEmpty {
            await CloudKitManager.shared.batchUpdate(toUpdate)
        }
        
        chore.currentResponsibleReference = userRef
        var refs = chore.allResponsibleUsersReference ?? []
        if !refs.contains(where: { $0.recordID == myUserID }) { refs.append(userRef) }
        chore.allResponsibleUsersReference = refs
        
        let newRefs = createdModels.compactMap { $0.recordID.map { CKRecord.Reference(recordID: $0, action: .none) } }
        if !newRefs.isEmpty {
            chore.dailyAssignmentsReference = (chore.dailyAssignmentsReference ?? []) + newRefs
        }
        if chore.frequency == .monthly, !createdModels.isEmpty {
            chore.shouldBeIncluded = false
        }
        await CloudKitManager.shared.update(chore)
        
        for assignment in toUpdate + createdModels {
            await syncSingleAssignmentToCalendar(for: assignment, chore: chore)
        }
        
        await refreshAfterChoreUpdate()
        return true
    }
    
    // MARK: - Custom Calendar
    
    /// Number of uncompleted tasks per day (recurring assignments + one-off chores with a dueDate)
    private(set) var loadByDay: [Date: Int] = [:]
        
    /// From today until the last day of the algorithm window
    var selectableWindow: Range<Date>? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        guard let lastDay = dailyAssignments.map({ calendar.startOfDay(for: $0.day) }).max(),
              lastDay >= today,
              let end = calendar.date(byAdding: .day, value: 1, to: lastDay)
        else { return nil }
        
        return today..<end
    }
    
    /// The two weeks the engine last generated (starts on the cycle's first day, NOT today).
    /// Derived from the last assignment day: engine window = 15 days, so first day = last day - 14.
    /// Falls back to nil when there is no schedule.
    var cycleWindow: Range<Date>? {
        let calendar = Calendar.current
        guard let cycleEnd = currentCycleEnd else { return nil }
        let lastDay = calendar.startOfDay(for: cycleEnd)
        guard let start = calendar.date(byAdding: .day, value: -14, to: lastDay),
              let end = calendar.date(byAdding: .day, value: 1, to: lastDay)
        else { return nil }
        return start..<end
    }
    
    /// Counts the pending occurrences of each day (see ``loadByDay``).
    private func rebuildLoadByDay() {
        let calendar = Calendar.current
        var result: [Date: Int] = [:]
        
        for assignment in dailyAssignments where !assignment.isCompleted {
            result[calendar.startOfDay(for: assignment.day), default: 0] += 1
        }
        
        // One-off chores: no assignment, has a dueDate, and uncompleted
        for chore in cardModels where !chore.isDone && (chore.dailyAssignmentsReference ?? []).isEmpty {
            if let due = chore.dueDate {
                result[calendar.startOfDay(for: due), default: 0] += 1
            }
        }
        
        loadByDay = result
    }
    
    /// 0 (no tasks on that day, no background) ... 1.0 (the busiest day within the window)
    func loadOpacity(on day: Date, in window: Range<Date>) -> Double {
        let count = loadByDay[Calendar.current.startOfDay(for: day)] ?? 0
        guard count > 0 else { return 0 }
        
        let peak = max(loadByDay.filter { window.contains($0.key) }.values.max() ?? 0, 1)
        return 0.25 + 0.75 * Double(count) / Double(peak)   // Days with tasks have at least 0.25 opacity
    }
    
    // MARK: - Change Frequency

    /// Handles updating a chore's frequency during edit flow.
    ///
    /// Removes all remaining future occurrences from today onward under the OLD frequency,
    /// and generates a fresh set under the NEW frequency bound strictly by the original engine cutoff (`cycleEnd`).
    /// Historical/completed occurrences prior to today are left intact.
    @MainActor
    func handleFrequencyChange(
        for chore: ChoreModel,
        from oldFrequency: Recurrence,
        responsibleUsers: [UserModel],
        pickedDate: Date?
    ) async {
        guard oldFrequency != chore.frequency else { return }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Capture the original Engine cycle end date BEFORE deleting any records.
        guard let targetCycleEnd = currentCycleEnd else {
            if chore.frequency == .none {
                chore.dueDate = pickedDate.map { calendar.startOfDay(for: $0) } ?? today
                await CloudKitManager.shared.update(chore)
            }
            return
        }
        
        let cycleEnd = calendar.startOfDay(for: targetCycleEnd)
        
        // Purge only future occurrences (from today onward) belonging to the old frequency.
        if oldFrequency != .none {
            let existing = await chore.dailyAssignments
            let toDelete = existing.filter { calendar.startOfDay(for: $0.day) >= today }
            
            if !toDelete.isEmpty {
                let deleteIDs = toDelete.compactMap { $0.recordID }
                if let zoneID = deleteIDs.first?.zoneID {
                    await CloudKitManager.shared.delete(recordIDs: deleteIDs, zoneID: zoneID)
                }
                let deletedSet = Set(deleteIDs)
                
                // Sync local in-memory state
                chore.dailyAssignmentsReference = (chore.dailyAssignmentsReference ?? [])
                    .filter { !deletedSet.contains($0.recordID) }
                
                self.dailyAssignments.removeAll { assignment in
                    guard let id = assignment.recordID else { return false }
                    return deletedSet.contains(id)
                }
            }
        }
        
        // Handle switching to a non-recurring chore (.none)
        if chore.frequency == .none {
            chore.dueDate = pickedDate.map { calendar.startOfDay(for: $0) } ?? today
            await CloudKitManager.shared.update(chore)
            return
        }
        
        chore.dueDate = nil
        guard let choreID = chore.recordID else { return }
        
        // Determine start date for the new frequency
        let start: Date
        if chore.frequency == .daily {
            start = today
        } else {
            let candidate = pickedDate.map { calendar.startOfDay(for: $0) } ?? today
            start = max(candidate, today)
        }
        
        // Generate dates bounded strictly between `start` and `cycleEnd` with zero time component
        let days = occurrenceDays(for: chore.frequency, from: start, through: cycleEnd)
        
        guard !days.isEmpty else {
            await CloudKitManager.shared.update(chore)
            return
        }
        
        // Map each normalized day date to exactly ONE assignment, rotating across responsible users
        let rotation = responsibleUsers.compactMap { $0.recordID }
        let choreRef = CKRecord.Reference(recordID: choreID, action: .deleteSelf)
        
        let newAssignments = days.enumerated().map { index, day -> RecurrentAssignmentModel in
            let userRefs: [CKRecord.Reference]? = rotation.isEmpty
                ? nil
                : [CKRecord.Reference(recordID: rotation[index % rotation.count], action: .none)]
            
            return RecurrentAssignmentModel(day: day, isCompleted: false, users: userRefs, chore: choreRef)
        }
        
        // Persist and apply new schedule results to CloudKit and local state
        await commitScheduleResults(
            [ScheduleResult(chore: chore, newAssignments: newAssignments)],
            users: responsibleUsers,
            houseZoneID: choreID.zoneID
        )
    }
}
