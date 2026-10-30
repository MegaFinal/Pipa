//
//  DashboardViewModel.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 29/09/26.
//

import SwiftUI
import CloudKit

/// Builds every card of the progress tab (Dashboard) for the signed-in member: today's ring,
/// rooms, points, the week chart and the chores nobody owns.
///
/// Works on data already loaded by ``HouseDataStore``, so switching weeks needs no request.
@Observable
class DashboardViewModel {
    
    // MARK: - Chart Data Types
    
    /// One room inside a chart (a bar segment or a legend item).
    struct RoomSlice: Identifiable {
        let id: String
        let name: String
        let color: Color
        let choreCount: Int
    }
    
    /// One column of the daily chart: one day, split by room.
    struct DaySlice: Identifiable {
        let day: Date
        let rooms: [RoomSlice]
        var id: Date { day }
    }
    
    // MARK: - Cache
    
    /// The signed-in member.
    private var user: UserModel?
    /// The house members.
    private var houseMembers: [UserModel] = []
    /// Every chore of the house.
    private var chores: [ChoreModel] = []
    /// Every chore occurrence of the house.
    private var assignments: [RecurrentAssignmentModel] = []
    /// Every room of the house.
    private var rooms: [RoomModel] = []
    
    /// "Current division" card data. Loaded in the same pass as everything else,
    /// from the data already fetched here (no second round of CloudKit requests).
    let schedule = CurrentScheduleViewModel()
    
    // MARK: - Period
    
    /// Monday of the selected week. The chart always goes from Monday to Sunday.
    var periodStart: Date = DashboardViewModel.mondayOfWeek(containing: .now)
    /// The last day of the selected period.
    var periodFinish: Date = DashboardViewModel.mondayOfWeek(containing: Calendar.current.date(byAdding: .day, value: 13, to: .now) ?? Date())
    
    /// Monday of the week that contains `date` (weeks run Monday → Sunday).
    static func mondayOfWeek(containing date: Date) -> Date {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // 1 = Sunday, 2 = Monday
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start
        ?? calendar.startOfDay(for: date)
    }
    
    // MARK: - 1. Daily Completion Ring
    
    /// Today's chores the member already did.
    var completedToday: Int = 0
    /// Today's chores of the member.
    var totalToday: Int = 0
    /// Fraction of today's chores done, from `0` to `1`.
    var completionProgress: Double = 0.0
    /// ``completionProgress`` as text (e.g. `"75%"`).
    var completionText: String = "0%"
    
    // MARK: - 2. Room Distribution (legend)
    
    /// Rooms that appear in the period, with their total chore count.
    var roomDistribution: [RoomSlice] = []
    
    // MARK: - 3. Cognitive Load
    
    /// The user's points (also used by the "42 pontos" card).
    var myCognitiveLoad: Int = 0
    /// Points of every member added up.
    var houseCognitiveLoad: Int = 0
    /// The member's share of the house's points, from `0` to `1`.
    var myCognitiveShare: Double = 0.0
    /// The fair share if everyone did the same (1 ÷ number of members).
    var idealCognitiveShare: Double = 0.0
    /// ``myCognitiveShare`` as text.
    var myCognitiveShareText: String = "0%"
    /// ``idealCognitiveShare`` as text.
    var idealCognitiveShareText: String = "0%"
    
    // MARK: - 4. Daily Distribution by Room
    
    /// The member's chores per day of the selected week, split by room.
    var dailyRoomDistribution: [DaySlice] = []
    
    // MARK: - Load
    
    /// `true` while the data is loading.
    var isLoading: Bool = true
    
    /// Changes every time the cards are rebuilt from a new snapshot. The view uses it as an
    /// `.id(_:)` so the charts are recreated and always draw the freshly built data.
    var contentVersion: Int = 0
    
    /// The ``HouseDataStore`` snapshot the cached data was built from. `nil` until the first load.
    private var loadedSnapshotID: UUID?
    
    /// Day the cached data was built for. "Today" cards go stale at midnight
    private var loadedDay: Date?
    
    /// Whether the cards were built from an older snapshot, or for another day.
    private func needsRebuild(for snapshot: HouseSnapshot) -> Bool {
        guard let loadedSnapshotID, let loadedDay else { return true }
        return loadedSnapshotID != snapshot.id
            || !Calendar.current.isDateInToday(loadedDay)
    }
    
    /// Rebuilds the cards only when the house data changed or the day rolled over.
    func loadIfNeeded() async {
        await load()
    }
    
    /// Brings the cards up to date after CloudKit reported a change (push, app back in the
    /// foreground, pull to refresh). Always asks the store for fresh data.
    func reloadAfterRemoteChange() async {
        await load(afterRemoteChange: true)
    }
    
    /// Builds every card from ``HouseDataStore``.=
    @MainActor
    func load(afterRemoteChange: Bool = false) async {
        let store = HouseDataStore.shared
        
        if let cached = store.snapshot, needsRebuild(for: cached) {
            await build(from: cached)
            guard !Task.isCancelled else { return }
        }
        
        let snapshot = afterRemoteChange
            ? await store.refreshAfterRemoteChange()
            : await store.loadLatest()
        guard !Task.isCancelled else { return }
        
        if needsRebuild(for: snapshot) {
            await build(from: snapshot)
        } else {
            isLoading = false
        }
    }
    
    /// Rebuilds every card from `snapshot`.
    @MainActor
    private func build(from snapshot: HouseSnapshot) async {
        // `snapshot.houseUser` comes from CloudKitManager's per-session cache, which is never
        // refreshed (only its points are, from `UserScoreModel`). The same record inside
        // `userRecords` was fetched in this very pass.
        let freshUser = snapshot.userRecords.first { $0.recordID == snapshot.houseUser?.recordID }
        user = freshUser ?? snapshot.houseUser
        houseMembers = snapshot.users
        chores = snapshot.chores
        assignments = snapshot.assignments
        rooms = snapshot.rooms
        
        refresh()
        await schedule.setup(users: snapshot.users, chores: snapshot.chores,
                             assignments: snapshot.assignments, rooms: snapshot.rooms,
                             me: user)
        guard !Task.isCancelled else { return }
        
        loadedSnapshotID = snapshot.id
        loadedDay = Calendar.current.startOfDay(for: .now)
        contentVersion &+= 1
        isLoading = false
    }
    /// Rebuilds every card from the data in memory.
    func refresh() {
        loadCompletionRing()
        loadCognitiveLoad()
        loadDailyRoomDistribution()
        loadRoomDistribution()
    }
    
    /// Moves the selected week by `offset` weeks (negative goes back) and rebuilds the charts.
    func changePeriod(by offset: Int) {
        guard let newStart = Calendar.current.date(
            byAdding: .day,
            value: offset * 7,
            to: periodStart
        )
        else {
            return
        }
        
        periodStart = newStart
        loadDailyRoomDistribution()
        loadRoomDistribution() }
    
    // MARK: - 1. Completion Ring
    
    /// Fills today's ring from the member's chores of today.
    func loadCompletionRing() {
        guard let user else { return }
        
        // Same filter as the chores screen
        let today = DashboardModel(user: user)
        today.setup(chores: chores, assignments: assignments)
        
        totalToday = today.todayChores.count
        completedToday = totalToday - today.toDoList.count
        completionProgress = fraction(completedToday, of: totalToday)
        completionText = percentText(completionProgress)
    }
    
    // MARK: - 2. Room Distribution
    
    /// Sums the daily chart per room — must run after `loadDailyRoomDistribution()`.
    func loadRoomDistribution() {
        var totals: [String: RoomSlice] = [:]
        for slice in dailyRoomDistribution.flatMap(\.rooms) {
            let previous = totals[slice.id]?.choreCount ?? 0
            totals[slice.id] = RoomSlice(
                id: slice.id,
                name: slice.name,
                color: slice.color,
                choreCount: previous + slice.choreCount
            )
        }
        roomDistribution = totals.values.sorted { $0.choreCount > $1.choreCount }
    }
    
    // MARK: - 3. Cognitive Load
    
    /// Fills the points card: the member's points, the house's total and the shares.
    func loadCognitiveLoad() {
        guard let user else { return }
        
        myCognitiveLoad = user.points
        houseCognitiveLoad = houseMembers.reduce(0) { $0 + $1.points }
        myCognitiveShare = fraction(myCognitiveLoad, of: houseCognitiveLoad)
        idealCognitiveShare = houseMembers.isEmpty ? 0 : 1.0 / Double(houseMembers.count)
        myCognitiveShareText = percentText(myCognitiveShare)
        idealCognitiveShareText = percentText(idealCognitiveShare)
    }
    
    // MARK: - 4. Daily Room Distribution
    
    /// Fills the week chart: the member's chores per day and room.
    func loadDailyRoomDistribution() {
        guard let userID = user?.recordID else { return }
        let calendar = Calendar.current
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: periodStart) }

        // The user's assignments, by recordID (checking multi-user references)
        let myAssignments = Dictionary(
            assignments
                .filter { assignment in
                    (assignment.userReferences ?? []).contains { $0.recordID == userID }
                }
                .compactMap { a in a.recordID.map { ($0, a) } },
            uniquingKeysWith: { first, _ in first }
        )
        
        // Dates on which each chore falls for the user
        func dates(of chore: ChoreModel) -> [Date] {
            if let refs = chore.dailyAssignmentsReference, !refs.isEmpty {
                return refs.compactMap { myAssignments[$0.recordID]?.day }
            }
            if chore.currentResponsibleReference?.recordID == userID, let due = chore.dueDate {
                return [due]
            }
            return []
        }
        
        dailyRoomDistribution = days.map { day in
            let choresOfDay = chores.filter { chore in
                dates(of: chore).contains { calendar.isDate($0, inSameDayAs: day) }
            }
            let slices: [RoomSlice] = rooms.compactMap { room in
                let count = choresOfDay.filter { $0.roomReference?.recordID == room.recordID }.count
                guard count > 0, let id = room.recordID else { return nil }
                return RoomSlice(id: id.recordName, name: room.name, color: room.color.uiColor, choreCount: count)
            }
            return DaySlice(day: day, rooms: slices)
        }
    }
    
    // MARK: - Helpers
    
    /// `value ÷ total`, or `0` when `total` is `0`.
    private func fraction(_ value: Int, of total: Int) -> Double {
        guard total > 0 else { return 0 }
        return Double(value) / Double(total)
    }
    
    /// `value` (0 to 1) as a whole percentage, e.g. `"45%"`.
    private func percentText(_ value: Double) -> String {
        ChartA11y.percent(value)
    }
}
