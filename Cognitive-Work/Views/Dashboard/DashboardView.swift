//
//  DashboardView.swift
//  Cognitive-Work
//
//  Created by Isabela Hissa Pinto on 01/10/26.
//

import SwiftUI

/// The progress tab: today's ring, the points, how the house's work is split, the current
/// division and the chores nobody owns.
struct DashboardView: View {
    /// Builds every card from the house's data.
    @State var viewModel = DashboardViewModel()
    @State private var carouselViewModel: CarouselViewModel
    @State private var clotheslineViewModel: ClotheslineViewModel
    /// Whether the app is active (the data reloads when it comes back).
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        let carouselViewModel = CarouselViewModel()
        _carouselViewModel = State(initialValue: carouselViewModel)
        _clotheslineViewModel = State(initialValue: ClotheslineViewModel(carouselViewModel: carouselViewModel))
    }
    
    var body: some View {
        NavigationStack {
            
            ScrollView {
                VStack(spacing: 16) {
                    
                    // MARK: - Title and current division dates
                    header
                    
                    // MARK: - Today ring and points
                    HStack(spacing: 16) {
                        DoughnutChart(viewModel: $viewModel)
                        PointsComponent(
                            points: viewModel.myCognitiveLoad
                        )
                    }
                    // Both cards take the height of the taller one.
                    .fixedSize(horizontal: false, vertical: true)
                    
                    // MARK: - How the house's work is split
                    BarPercentageComponent(viewModel: viewModel)
                    
                    // MARK: - Current division
                    UserCurrentDivisionComponent(
                        periodStart: viewModel.periodStart,
                        sharedViewModel: viewModel.schedule
                    )
                        .padding(.horizontal, 16)
                    
                    // MARK: - Chores nobody owns
                    UnassignedChoresCard(viewModel: clotheslineViewModel)
                }
                // Same width as the screen, so the side margins stay what they were
                // when the title sat outside the scroll.
                .containerRelativeFrame(.horizontal)
                // Keeps the last card off the tab bar.
                .padding(.bottom, 24)
                // New content version = new identity: the charts are recreated and draw the
                // rebuilt data. Applied inside the ScrollView so the scroll position is kept.
                .id(viewModel.contentVersion)
            }
            .refreshable {
                await reloadAfterRemoteChange()
            }
            // MARK: - Hidden while loading, with a spinner
            .disabled(viewModel.isLoading)
            .opacity(viewModel.isLoading ? 0 : 1)
            // Invisible while loading, so VoiceOver must not reach it either.
            .accessibilityHidden(viewModel.isLoading)
            // Only on a cold start without data in memory; otherwise the cards draw at once.
            .overlay {
                if viewModel.isLoading { ProgressView() }
            }
        }
        .overlay { PickUnassignedChoreOverlay(carouselViewModel: carouselViewModel) }
        // MARK: - Reloading on local changes, pushes and returning to the app
        // Local changes: `markDataChanged()` bumps `dataRevision`.
        .task(id: CloudKitManager.shared.dataRevision) {
            await viewModel.loadIfNeeded()
            await carouselViewModel.fetchAllData()
        }
        // Changes made on another device (the CKDatabaseSubscription push posts this).
        .onReceive(NotificationCenter.default.publisher(for: .cloudKitDidChange)) { _ in
            Task { await reloadAfterRemoteChange() }
        }
        // Pushes can be missed while the app is suspended, and "today" may have rolled over.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await reloadAfterRemoteChange() }
            }
        }
    }
    
    private func reloadAfterRemoteChange() async {
        await viewModel.reloadAfterRemoteChange()
        await carouselViewModel.fetchAllData()
    }
    
    /// "Seu progresso" and the current division's dates.
    private var header: some View {
        VStack(alignment: .leading) {
            Text("Seu progresso")
                .font(.custom("Alan Sans", size: 34))
                .fontWeight(.bold)
                .padding(.top, 20)
                .accessibilityAddTraits(.isHeader)
            
            DateDivisionComponent(viewModel: $viewModel)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    HouseDataStore.shared.seed(.preview)
    return DashboardView()
}
