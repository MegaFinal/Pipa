//
//  RetroViewModel.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 29/09/26.
//


import Foundation

// MARK: - Errors

/// Everything that can go wrong while loading the retrospective.
enum RetroError: Error, Equatable, LocalizedError {
    /// The signed-in user has no profile inside the current house.
    case userNotFound
    /// The device is offline or CloudKit could not be reached.
    case networkUnavailable
    /// Any other failure; carries the localized description of the original error.
    case underlying(String)

    /// A short, user-facing message for the error.
    var errorDescription: String? {
        switch self {
        case .userNotFound:
            return L10n.tr("Não foi possível encontrar o seu perfil na casa.")
        case .networkUnavailable:
            return L10n.tr("Sem conexão com a internet.")
        case .underlying(let message):
            return message
        }
    }
}

// MARK: - Domain input (plain value types, no CloudKit)

/// One thing the user was supposed to do in the period (a daily assignment or a one-off chore).
struct RetroWorkItem: Equatable, Sendable {
    /// The occurrence or chore ID.
    let id: String
    /// The day it was due.
    let day: Date
    /// Whether the user did it.
    let isCompleted: Bool
    /// The ID of the chore's room, if any.
    let roomID: String?
}

/// A room of the house, as the retrospective needs it.
struct RetroRoom: Equatable, Sendable, Identifiable {
    /// The room's record name.
    let id: String
    /// The room's name.
    let name: String
    /// The room's color.
    let color: RoomColor
}

/// Raw data the repository hands to the view model.
struct RetroSnapshot: Equatable, Sendable {
    /// The user's work in the period.
    var items: [RetroWorkItem]
    /// Every room of the house.
    var rooms: [RetroRoom]
    /// Only the house admin may start a new division of chores. Defaults to `false` so a
    /// repository that can't tell never shows the new-division prompt to a resident.
    var isHouseAdmin = false
    /// Whether the current division's period is over (`RetroTriggerPolicy.isDivisionOver`).
    /// `false` for an old retrospective opened while a cycle is still running, and by default.
    var isDivisionOver = false
}

/// Closed interval of days the retrospective covers.
struct RetroPeriod: Equatable, Sendable {
    /// First moment of the period.
    let start: Date
    /// Last moment of the period (now, when it was created).
    let end: Date

    /// Whether `date` is inside the period.
    func contains(_ date: Date) -> Bool { date >= start && date <= end }

    /// The last `days` days, ending at `now` (the start is the beginning of that first day).
    static func last(days: Int, endingAt now: Date, calendar: Calendar) -> RetroPeriod {
        let startOfToday = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: startOfToday) ?? startOfToday
        return RetroPeriod(start: start, end: now)
    }
}

// MARK: - Dependencies

/// Where the retrospective data comes from. `CloudKitRetroRepository` is the production one.
@MainActor
protocol RetroRepository {
    /// Throws `RetroError` (anything else is wrapped as `.underlying`).
    func fetchSnapshot(for period: RetroPeriod) async throws -> RetroSnapshot
}

/// Tunable rules. The coins page has its own (`RetroCoinsContent`).
struct RetroConfiguration: Equatable, Sendable {
    /// How many days the retrospective looks back.
    var periodDays = 15

    /// The configuration the app uses.
    static let `default` = RetroConfiguration()
}

// MARK: - Flow

/// Where the user is in the whole retrospective experience.
enum RetroPhase: Equatable {
    /// "Sua retrospectiva chegou!" (small card)
    case alert
    /// The pager with the retro pages (full-screen card)
    case pages
    /// "Comece a nova divisão de tarefas" (small card)
    case divisionPrompt
    /// The generated schedule (full screen)
    case schedule
    /// Nothing left to show; the host can remove RetroView.
    case dismissed
}

/// Pager pages, in the order they are shown. Raw values are the TabView tags, so they must
/// follow the same order as the views inside RetroView's TabView.
enum RetroPage: Int, CaseIterable, Equatable, Sendable {
    /// Share of the user's chores done.
    case percentage = 0
    /// Completed chores per room.
    case rooms = 1
    /// Rank reached in the cycle (`RetroRankView`, fed by `RetroCoinsViewModel`).
    case rank = 2
    /// Coins earned in the cycle (`RetroCoinsView`, fed by `RetroCoinsViewModel`).
    /// Last page: its button redeems the coins and then concludes the retrospective.
    case coins = 3
    /// Placeholder: RetroStreakView is developed later. It does not occupy a slot in the pager yet.
//    case streak

    /// The page the retrospective opens on.
    static var first: RetroPage { allCases[0] }

    /// Whether this is the last page (its button concludes instead of continuing).
    var isLast: Bool { self == RetroPage.allCases.last }
}

/// Whether the retrospective's data is loaded.
enum RetroLoadState: Equatable {
    /// Nothing was loaded yet.
    case idle
    /// Loading.
    case loading
    /// Loaded; the page contents are ready.
    case loaded
    /// Loading failed with this error.
    case failed(RetroError)
}

/// Things other parts of the app can react to without knowing any View.
enum RetroEvent: Equatable {
    /// The data finished loading.
    case loaded
    /// Loading failed.
    case loadFailed(RetroError)
    /// The user moved to another page.
    case pageChanged(RetroPage)
    /// The user left the pages without finishing them ("ver depois").
    case retrospectiveSkipped
    /// The user finished the last page.
    case retrospectiveCompleted
    /// The admin asked for the automatic division.
    case divisionRequested
    /// The admin chose to divide later.
    case divisionDeferred
    /// The admin confirmed the generated schedule.
    case divisionConfirmed
    /// The experience is over and the host should remove it (always the last event of a flow).
    case finished
}

// MARK: - Per-page content

/// What `RetroPercentageOfDoneView` needs.
struct RetroPercentageContent: Equatable {
    /// Chores (and occurrences) the user did in the period.
    let completedChores: Int
    /// Chores (and occurrences) the user had in the period.
    let totalChores: Int
    /// 0...100
    let percentage: Double
    /// "Você realizou X de Y tarefas da sua escala".
    let summary: String
    /// A short comment on the result.
    let subtitle: String
    /// The big cheering word at the bottom.
    let closing: String

    /// Shown before the data loads.
    static let empty = RetroPercentageContent(
        completedChores: 0, totalChores: 0, percentage: 0,
        summary: "", subtitle: "", closing: ""
    )
}

/// What `RetroRoomsView` needs.
struct RetroRoomsContent: Equatable {
    /// One bar of the chart: a room and how many chores the user did there.
    struct Bar: Equatable, Identifiable {
        let id: String
        let roomName: String
        let color: RoomColor
        let choreCount: Int
    }

    /// "N cômodos".
    let title: String
    /// Names the room the user worked on most.
    let subtitle: String
    /// Sorted by chore count, highest first.
    let bars: [Bar]
    /// The longest bar's count, to scale the others.
    var maxChoreCount: Int { bars.map(\.choreCount).max() ?? 0 }

    /// Shown before the data loads.
    static let empty = RetroRoomsContent(title: "", subtitle: "", bars: [])
}

// MARK: - Calculator (pure business rules)

/// All transformations from raw data to screen content. Pure and stateless, so it is trivial to test.
enum RetroCalculator {

    /// The percentage page's content: how many of the user's chores in `period` were done.
    static func percentage(items: [RetroWorkItem], period: RetroPeriod) -> RetroPercentageContent {
        let inPeriod = items.filter { period.contains($0.day) }
        let total = inPeriod.count
        let completed = inPeriod.filter(\.isCompleted).count
        let percentage = total > 0
            ? min(max(Double(completed) / Double(total) * 100, 0), 100)
            : 0

        let subtitle: String
        let closing: String
        switch percentage {
        case _ where total == 0:
            subtitle = L10n.tr("Você não teve tarefas na escala nesse período")
            closing = L10n.tr("bora na próxima!")
        case 100:
            subtitle = L10n.tr("Você fez tudo o que era seu")
            closing = L10n.tr("parabéns!")
        case 50...:
            subtitle = L10n.tr("Foi por pouco, na próxima você chega lá")
            closing = L10n.tr("quase lá!")
        default:
            subtitle = L10n.tr("Vamos tentar de novo na próxima")
            closing = L10n.tr("você consegue!")
        }

        return RetroPercentageContent(
            completedChores: completed,
            totalChores: total,
            percentage: percentage,
            summary: L10n.tr("Você realizou **\(completed) de \(total)** \n tarefas da sua escala"),
            subtitle: subtitle,
            closing: closing
        )
    }

    /// Counts the chores the user actually completed per room.
    static func rooms(items: [RetroWorkItem], rooms: [RetroRoom], period: RetroPeriod) -> RetroRoomsContent {
        var counts: [String: Int] = [:]
        for item in items where item.isCompleted && period.contains(item.day) {
            if let roomID = item.roomID { counts[roomID, default: 0] += 1 }
        }

        let bars = rooms
            .compactMap { room -> RetroRoomsContent.Bar? in
                guard let count = counts[room.id], count > 0 else { return nil }
                return .init(id: room.id, roomName: room.name, color: room.color, choreCount: count)
            }
            .sorted { $0.choreCount != $1.choreCount ? $0.choreCount > $1.choreCount : $0.roomName < $1.roomName }

        guard let top = bars.first else {
            return RetroRoomsContent(
                title: L10n.tr("\(0) cômodos"),
                subtitle: L10n.tr("Nenhuma tarefa concluída nesse período."),
                bars: []
            )
        }
        return RetroRoomsContent(
            title: L10n.tr("\(bars.count) cômodos"),
            subtitle: L10n.tr("Seu cômodo mais trabalhado: \(top.roomName)."),
            bars: bars
        )
    }
}

// MARK: - Event bus

/// Fan-out of `RetroEvent`s to any number of `AsyncStream` subscribers.
/// Each subscription is removed automatically when its consuming task ends or is cancelled.
@MainActor
final class RetroEventBus {
    /// One continuation per open stream.
    private var continuations: [UUID: AsyncStream<RetroEvent>.Continuation] = [:]

    /// A new stream that receives every event sent from now on.
    func makeStream() -> AsyncStream<RetroEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(
            of: RetroEvent.self, bufferingPolicy: .bufferingNewest(32)
        )
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.continuations[id] = nil }
        }
        return stream
    }

    /// Sends `event` to every open stream.
    func send(_ event: RetroEvent) {
        for continuation in continuations.values { continuation.yield(event) }
    }

    /// Ends every open stream.
    func finish() {
        continuations.values.forEach { $0.finish() }
        continuations.removeAll()
    }
}

// MARK: - ViewModel

/// Orchestrates the whole retrospective: loading, flow between phases/pages, and the content of each page.
///
/// Views never compute anything: they read the `*Content` properties and call the intent methods.
@MainActor
@Observable
final class RetroViewModel {

    // MARK: Overall state

    /// Loading status of the retrospective data. `RetroAlert`/pages can show a spinner or an error from it.
    private(set) var loadState: RetroLoadState = .idle

    /// Which screen of the experience is showing. Single source of truth for RetroView's old
    /// `showPages`, `isRetroDone` and `showSchedule` flags.
    private(set) var phase: RetroPhase = .alert

    /// Whether the signed-in user is the house admin (`HouseModel.isAdmin()`). Only the admin gets
    /// the new-division prompt; everyone else goes straight from the retrospective to the end.
    private(set) var isHouseAdmin = false

    /// Whether this retrospective may lead to a new division: only the admin, and only once the
    /// current division is over. An old retrospective (opened from the notifications while the
    /// next cycle runs) just closes, so it can't replace the running division.
    private(set) var canStartNewDivision = false

    /// Current page of the pager.
    private(set) var currentPage: RetroPage = .first

    /// Period covered (set on every load).
    private(set) var period: RetroPeriod

    // MARK: Per-screen content (each View reads only its own)

    /// For `RetroPercentageOfDoneView`.
    private(set) var percentageContent: RetroPercentageContent = .empty
    /// For `RetroRoomsView`.
    private(set) var roomsContent: RetroRoomsContent = .empty

    // MARK: Derived state

    /// Whether the white card fills the screen (replaces `isExpanded`).
    var isCardExpanded: Bool { phase == .pages || phase == .schedule }

    /// True while the rooms page is the visible one, so its bars grow each time it appears
    /// (replaces `isActive: page == 3`).
    var isRoomsPageActive: Bool { isPageActive(.rooms) }

    /// Whether `page` is the one on screen. The paged TabView builds the neighbouring pages
    /// before they are visible, so pages use this (not `onAppear`/`task`) to start their animations.
    func isPageActive(_ page: RetroPage) -> Bool { phase == .pages && currentPage == page }

    /// Whether the current page is the last one (its button concludes the retrospective).
    var isLastPage: Bool { currentPage == RetroPage.allCases.last }

    /// Two-way bridge for `TabView(selection:)`. Use with `@Bindable`: `$viewModel.pageIndex`.
    var pageIndex: Int {
        get { currentPage.rawValue }
        set { if let page = RetroPage(rawValue: newValue) { goToPage(page) } }
    }

    // MARK: Dependencies

    /// Where the data comes from.
    private let repository: RetroRepository
    /// Tunable rules (period length).
    private let configuration: RetroConfiguration
    /// Gives the current date (fixed in tests).
    private let clock: () -> Date
    /// The calendar used for days.
    private let calendar: Calendar
    /// Delivers ``RetroEvent``s to listeners.
    private let eventBus: RetroEventBus

    /// The last loaded data.
    private var snapshot: RetroSnapshot?
    /// The load started by ``reload()``.
    private var loadTask: Task<Void, Never>?
    /// Incremented on every load; a finished load only applies its result if it is still the latest.
    private var loadGeneration = 0

    /// - Parameters:
    ///   - repository: Where the data comes from.
    ///   - configuration: Tunable rules.
    ///   - calendar: The calendar used for days.
    ///   - clock: Gives the current date.
    ///   - eventBus: Delivers events; a new one by default.
    init(
        repository: RetroRepository,
        configuration: RetroConfiguration = .default,
        calendar: Calendar = .current,
        clock: @escaping () -> Date = { Date() },
        eventBus: RetroEventBus? = nil
    ) {
        self.repository = repository
        self.configuration = configuration
        self.calendar = calendar
        self.clock = clock
        self.eventBus = eventBus ?? RetroEventBus()
        self.period = .last(days: configuration.periodDays, endingAt: clock(), calendar: calendar)
    }

    // MARK: - Events (View ↔ View, ViewModel ↔ app, without direct coupling)

    /// A new stream of events. Each caller gets its own; it ends when the consuming task is cancelled.
    ///
    ///     .task { for await event in viewModel.makeEventStream() { ... } }
    func makeEventStream() -> AsyncStream<RetroEvent> { eventBus.makeStream() }

    // MARK: - Loading

    /// Loads and publishes all page content. Safe to call repeatedly: only the latest call wins.
    /// Use from `.task { await viewModel.load() }` so SwiftUI cancels it with the view.
    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        let hadData = snapshot != nil
        loadState = .loading
        period = .last(days: configuration.periodDays, endingAt: clock(), calendar: calendar)
        let requestedPeriod = period

        do {
            let result = try await repository.fetchSnapshot(for: requestedPeriod)
            guard generation == loadGeneration, !Task.isCancelled else {
                if generation == loadGeneration { loadState = hadData ? .loaded : .idle }
                return
            }
            snapshot = result
            isHouseAdmin = result.isHouseAdmin
            canStartNewDivision = result.isHouseAdmin && result.isDivisionOver
            publishContent(from: result, period: requestedPeriod)
            loadState = .loaded
            eventBus.send(.loaded)
        } catch is CancellationError {
            if generation == loadGeneration { loadState = hadData ? .loaded : .idle }
        } catch {
            guard generation == loadGeneration else { return }
            let retroError = (error as? RetroError) ?? .underlying(error.localizedDescription)
            loadState = .failed(retroError)
            eventBus.send(.loadFailed(retroError))
        }
    }

    /// Fire-and-forget version of `load()` for buttons ("tentar de novo"). Cancels a load in flight.
    func reload() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in await self?.load() }
    }

    /// Cancels any load in flight. Call from `onDisappear` if the VM outlives the view.
    func cancelLoading() {
        loadTask?.cancel()
        loadTask = nil
    }

    /// Builds every page's content from `snapshot`.
    private func publishContent(from snapshot: RetroSnapshot, period: RetroPeriod) {
        percentageContent = RetroCalculator.percentage(items: snapshot.items, period: period)
        roomsContent = RetroCalculator.rooms(items: snapshot.items, rooms: snapshot.rooms, period: period)
    }

    // MARK: - Intents: alert → pages

    /// "Ver minha retrospectiva". Only valid on the alert. The View keeps its own fade timing.
    func startRetrospective() {
        guard phase == .alert else { return }
        currentPage = .first
        phase = .pages
    }

    // MARK: - Intents: pager

    /// The page's main button: "Continuar" on every page, "Concluir" on the last one.
    /// Pages call this instead of choosing, so reordering `RetroPage` needs no change in them.
    func advance() {
        if isLastPage {
            finishRetrospective()
        } else {
            continueToNextPage()
        }
    }

    /// "Continuar". On the last page it does nothing (the last page uses `finishRetrospective()`).
    func continueToNextPage() {
        guard phase == .pages,
              let next = RetroPage(rawValue: currentPage.rawValue + 1) else { return }
        goToPage(next)
    }

    /// Also called by swipes through `pageIndex`.
    func goToPage(_ page: RetroPage) {
        guard phase == .pages, page != currentPage else { return }
        currentPage = page
        eventBus.send(.pageChanged(page))
    }

    // MARK: - Intents: leaving the pages

    /// "ver depois" (pages) or "Pular para a nova divisão" (alert): jumps straight to the
    /// new-division prompt. Does not reset the points baseline.
    func skipRetrospective() {
        guard phase == .alert || phase == .pages else { return }
        eventBus.send(.retrospectiveSkipped)
        leaveRetrospective()
    }

    /// "Concluir" on the last page. Goes to the division prompt.
    func finishRetrospective() {
        guard phase == .pages else { return }
        eventBus.send(.retrospectiveCompleted)
        leaveRetrospective()
    }

    // MARK: - Intents: new division

    /// "Divisão automática de tarefas".
    func requestAutomaticDivision() {
        guard phase == .divisionPrompt, canStartNewDivision else { return }
        phase = .schedule
        eventBus.send(.divisionRequested)
    }

    /// "Dividir mais tarde".
    func deferDivision() {
        guard phase == .divisionPrompt else { return }
        eventBus.send(.divisionDeferred)
        dismiss()
    }

    /// The user confirmed the generated schedule (replaces RetroView's `onFinish`).
    func confirmSchedule() {
        guard phase == .schedule else { return }
        eventBus.send(.divisionConfirmed)
        dismiss()
    }

    // MARK: - Flow helpers

    /// After the retrospective: the admin is offered the new division if the current one is over;
    /// otherwise (residents, or an old retrospective) it is done.
    private func leaveRetrospective() {
        if canStartNewDivision {
            phase = .divisionPrompt
        } else {
            dismiss()
        }
    }

    /// Ends the experience and tells the host to remove it.
    private func dismiss() {
        phase = .dismissed
        eventBus.send(.finished)
    }
}
