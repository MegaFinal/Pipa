//
//  RetroView.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 29/09/26.
//

import SwiftUI

/// The retrospective, shown over the whole app: the alert card, the pages, the new-division
/// prompt and the generated schedule, one after the other.
///
/// It owns no flow state: `RetroViewModel.phase` and `pageIndex` decide what shows, and every
/// page reads only its own content from the same view model.
struct RetroView: View {
    /// Drives the whole retrospective.
    @State private var viewModel: RetroViewModel
    
    /// Rank and coins of the cycle, for the rank and coins pages. The presenting screen may pass one it already loaded.
    @State private var coinsViewModel: RetroCoinsViewModel
    
    /// Presentation-only: the card expands first (with the alert still on it), then the pages fade in.
    @State private var pagesVisible = false
    
    /// Called when the flow ends (schedule confirmed, or "Dividir mais tarde").
    var onFinish: () -> Void
    
    /// - Parameters:
    ///   - viewModel: Inject one for previews/tests. `nil` builds the production one.
    ///   - coinsViewModel: Coins already loaded by the presenting screen. `nil` builds (and loads) a new one.
    init(
        viewModel: RetroViewModel? = nil,
        coinsViewModel: RetroCoinsViewModel? = nil,
        onFinish: @escaping () -> Void = {}
    ) {
        _viewModel = State(initialValue: viewModel ?? RetroViewModel(
            repository: CloudKitRetroRepository()
        ))
        _coinsViewModel = State(initialValue: coinsViewModel ?? RetroCoinsViewModel())
        self.onFinish = onFinish
    }
    
    var body: some View {
        @Bindable var viewModel = viewModel
        
        // Group (not the ZStack) carries the tasks: they must outlive `.dismissed`
        // so the final event still reaches `onFinish`.
        Group {
            if viewModel.phase != .dismissed {
                ZStack {
                    ZStack {
                        Color.black.opacity(0.45)
                            .contentShape(Rectangle())
                            .onTapGesture { }
                            .accessibilityDecorative()
                        
                        RoundedRectangle(cornerRadius: 32)
                        // Real sizes (not .infinity), so SwiftUI can interpolate the size in both directions.
                            .frame(width: viewModel.isCardExpanded ? width : width * 0.877,
                                   height: viewModel.isCardExpanded ? height : height * 0.596)
                            .foregroundStyle(.white)
                            .overlay {
                                // Same branch for "alert" and "pages not visible yet": the alert must keep its
                                // identity while the card expands, otherwise it is recreated and the animation is lost.
                                if showsAlert {
                                    RetroAlert(viewModel: viewModel)
                                        .transition(.opacity)
                                } else if viewModel.phase == .pages {
                                    VStack(spacing: 12) {
                                        TabView(selection: $viewModel.pageIndex) {
                                            RetroPercentageOfDoneView(viewModel: viewModel)
                                                .tag(RetroPage.percentage.rawValue)
                                            
                                            RetroRoomsView(viewModel: viewModel)
                                                .tag(RetroPage.rooms.rawValue)
                                            
                                            RetroRankView(viewModel: viewModel, coinsViewModel: coinsViewModel)
                                                .tag(RetroPage.rank.rawValue)
                                            
                                            RetroCoinsView(viewModel: viewModel, coinsViewModel: coinsViewModel)
                                                .tag(RetroPage.coins.rawValue)
                                        }
                                        .tabViewStyle(.page(indexDisplayMode: .never))
                                        PageIndicator(count: RetroPage.allCases.count, current: $viewModel.pageIndex)
                                        // Clears the home indicator, now that the card reaches the screen edge.
                                            .padding(.bottom, 16)
                                        
                                    }
                                    .transition(.opacity)
                                } else if viewModel.phase == .divisionPrompt && viewModel.canStartNewDivision {
                                    // Only the admin, and only once the current division is over.
                                    RetroNewChoresDivision(
                                        onAutomaticDivision: { withAnimation { viewModel.requestAutomaticDivision() } },
                                        onLater: { withAnimation { viewModel.deferDivision() } }
                                    )
                                }
                            }
                    }
                    .ignoresSafeArea()
                    .frame(width: width, height: height)
                    
                    // MARK: - Generated schedule (admin only)
                    if viewModel.phase == .schedule && viewModel.canStartNewDivision {
                        NavigationStack {
                            FortnightlyScheduleView(shouldGenerate: true) {
                                viewModel.confirmSchedule()
                            }
                        }
                        .background(Color(.systemBackground).ignoresSafeArea())
                        .transition(.opacity)
                    }
                }
            }
        }
        // MARK: - Accessibility: close by voice or escape gesture
        // Voice Control has no escape gesture: an invisible, touch-transparent "Fechar"
        // element in the top corner lets the user say "Toque em Fechar".
        .overlay(alignment: .topTrailing) {
            if viewModel.phase != .dismissed && viewModel.phase != .schedule {
                DashboardVoiceControlButton(
                    labels: [L10n.tr("Fechar"), L10n.tr("Sair")],
                    action: close
                )
            }
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { close() }
        // MARK: - Loading and events
        .task { await viewModel.load() }
        // Idempotent: reuses the load the presenting screen may have started.
        .task { await coinsViewModel.load() }
        .task {
            for await event in viewModel.makeEventStream() {
                switch event {
                case .finished: onFinish()
                default: break
                }
            }
        }
        // MARK: - VoiceOver and the delayed fade-in of the pages
        // Each step swaps the whole content: let VoiceOver re-read it from the top.
        .onChange(of: viewModel.currentPage) { VoiceOver.screenChanged() }
        .onChange(of: viewModel.phase) { _, phase in
            VoiceOver.screenChanged()
            guard phase == .pages, !pagesVisible else { return }
            Task {
                try? await Task.sleep(for: .seconds(0.5))
                withAnimation(.easeInOut(duration: 0.3)) { pagesVisible = true }
            }
        }
    }
    
    /// Escape gesture / "Fechar": leaves the current step the same way its "later" button does.
    private func close() {
        withAnimation {
            switch viewModel.phase {
            case .alert, .pages: viewModel.skipRetrospective()
            case .divisionPrompt: viewModel.deferDivision()
            case .schedule, .dismissed: break
            }
        }
    }
    
    /// Whether the alert card shows: in the alert phase, and while the card expands before the pages fade in.
    private var showsAlert: Bool {
        viewModel.phase == .alert || (viewModel.phase == .pages && !pagesVisible)
    }
    
    /// Lets `RetroStreakView` (not migrated yet) keep its `isRetroDone` contract:
    /// setting it to `true` means "ver depois".
    private var isRetroDoneBinding: Binding<Bool> {
        Binding(
            get: { viewModel.phase != .pages },
            set: { if $0 { viewModel.skipRetrospective() } }
        )
    }
}

#if DEBUG
// MARK: - Preview support

/// Repository that returns fixed data, for previews.
struct PreviewRetroRepository: RetroRepository {
    /// How many chores are done in the sample.
    var completed = 3
    /// How many chores the sample has.
    var total = 4
    /// Previews show the admin's flow (with the new-division prompt) by default.
    var isHouseAdmin = true
    /// `false` previews an old retrospective (no new-division prompt, even for the admin).
    var isDivisionOver = true
    
    /// Builds a sample snapshot with `total` chores, `completed` of them done.
    func fetchSnapshot(for period: RetroPeriod) async throws -> RetroSnapshot {
        let day = Date().addingTimeInterval(-3600)
        let rooms = [
            RetroRoom(id: "kitchen", name: "Cozinha", color: .blue),
            RetroRoom(id: "living", name: "Sala", color: .green),
            RetroRoom(id: "bath", name: "Banheiro", color: .orange)
        ]
        let items = (0..<total).map { index in
            RetroWorkItem(id: "\(index)", day: day, isCompleted: index < completed,
                          roomID: rooms[index % rooms.count].id)
        }
        return RetroSnapshot(items: items, rooms: rooms, isHouseAdmin: isHouseAdmin, isDivisionOver: isDivisionOver)
    }
}

/// Loads a preview view model, optionally jumps to the pages, then shows `content`.
struct RetroPreviewHost<Content: View>: View {
    /// The view model, filled with the sample data.
    @State private var viewModel: RetroViewModel
    /// Whether to skip the intro and open the pages.
    private let startOnPages: Bool
    /// The page to open.
    private let page: RetroPage
    /// The view shown once loaded.
    private let content: (RetroViewModel) -> Content
    
    init(
        completed: Int = 3, total: Int = 4,
        startOnPages: Bool = true,
        page: RetroPage = .first,
        @ViewBuilder content: @escaping (RetroViewModel) -> Content
    ) {
        _viewModel = State(initialValue: RetroViewModel(
            repository: PreviewRetroRepository(completed: completed, total: total)
        ))
        self.startOnPages = startOnPages
        self.page = page
        self.content = content
    }
    
    var body: some View {
        content(viewModel)
            .task {
                await viewModel.load()
                if startOnPages {
                    viewModel.startRetrospective()
                    viewModel.goToPage(page)
                }
            }
    }
}

#Preview {
    RetroView(
        viewModel: RetroViewModel(repository: PreviewRetroRepository()),
        coinsViewModel: .preview(earned: Tier.protetorDoLar.cycleCoins, tier: .protetorDoLar)
    )
}
#endif
