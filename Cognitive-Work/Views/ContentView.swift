//
//  ContentView.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 07/08/26.
//

import SwiftUI
import CloudKit

/// The app's root screen once onboarding is finished.
///
/// Hosts the main tab bar and handles share invitations that arrive while the
/// user already belongs to a house.
struct ContentView: View {
    
    // MARK: - Properties
    /// Runs the app-level work (loading, house checks, invites, retrospective).
    @State private var viewModel: ContentViewModel = ContentViewModel()
    
    /// Shared by every tab so pushed screens can hide the tab bar and animate it back.
    @State private var tabBarVisibility = TabBarVisibilityController()
    
    /// Which tab is on screen, and what a tapped notification asks each tab to open.
    @State private var navigation = AppNavigation()
    
    /// Whether the app is active (re-checks the house and the retrospective when it comes back).
    @Environment(\.scenePhase) private var scenePhase
    
    // MARK: - Body
    
    var body: some View {
        Group {
            // MARK: No connection: retry (never "você não faz mais parte desta casa")
            if let problem = viewModel.connectionError, !viewModel.isRetryingConnection {
                ConnectionErrorView(message: problem) {
                    Task { await viewModel.retryConnection() }
                }
                .transition(.opacity)
            // MARK: Loading screen, then the tabs
            } else if viewModel.isLoading || viewModel.isRetryingConnection {
                LoadingScreen(message: "Carregando sua casa...")
            } else {
                tabs
            }
        }
        .environment(tabBarVisibility)
        .environment(navigation)
        // Over the whole TabView (tab bar included) once the last division's period is over.
        // MARK: Retrospective over everything
        .overlay {
            if viewModel.showRetro {
                RetroView {
                    withAnimation(.easeInOut) { viewModel.showRetro = false }
                }
                .transition(.opacity)
            }
        }
        // MARK: No house anymore (removed by the admin, or the house was deleted)
        .overlay {
            if viewModel.userHasNoHouse {
                HouseAccessLostView {
                    viewModel.accountWithoutHouseReturnToOnboarding()
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: viewModel.userHasNoHouse)
        .animation(.easeInOut, value: viewModel.connectionError)
        // MARK: Invite while already in a house
        .onReceive(NotificationCenter.default.publisher(for: .notAcceptShare)) { cloudMetadata in
            viewModel.showInviteAcceptAlert = true
            viewModel.shareMetadata = cloudMetadata.object as? CKShare.Metadata
        }
        .alert("Não é possivel estar em duas casas ao mesmo tempo", isPresented: $viewModel.showInviteAcceptAlert) {
            Button("Trocar de casa",role: .destructive) {
                viewModel.isSwitchingHouse = true
                Task {
                    if let sm = viewModel.shareMetadata {
                        await viewModel.switchHouse(to: sm)
                    }
                    viewModel.isSwitchingHouse = false
                }
            }
        } message: {
            Text("Se você aceitar, você sairá da sua casa atual todos os seus dados serão perdidos")
                + Text(verbatim: PremiumManager.shared.leaveWarning.map { "\n\n" + $0 } ?? "")
        }
        // MARK: Errors and deleted house
        .alert("Ops", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? L10n.tr("Deu algum erro."))
        }
        
        // MARK: Blocking screens
        .blockingOperation(isPresented: $viewModel.isSwitchingHouse, message: "Trocando de casa...")
        .blockingWhileUnlinkingOrphanedHouse()
        
        // MARK: Loading and refreshing
        .task {
            await viewModel.bootstrap()
            await viewModel.checkRetro()
            await NotificationManager.shared.enableOnFirstUseIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cloudKitDidChange)) { _ in
            Task { await viewModel.fetchHouse() }
        }
        // MARK: Tapped notification: opens its screen (also once the loading screen goes away,
        // for a notification that opened the app)
        .onChange(of: NotificationManager.shared.pendingDestinationID) { _, _ in
            openPendingDestination()
        }
        .onChange(of: viewModel.isLoading) { _, _ in
            openPendingDestination()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await viewModel.fetchHouse()
                    await viewModel.checkRetro()
                }
            }
        }
    }
    
    // MARK: - Notifications

    /// Opens the screen of the notification the user tapped, once the tabs are on screen.
    private func openPendingDestination() {
        guard !viewModel.isLoading, !viewModel.userHasNoHouse, viewModel.connectionError == nil,
              let destination = NotificationManager.shared.pendingDestination
        else { return }
        NotificationManager.shared.pendingDestination = nil

        if case .retrospective = destination {
            withAnimation(.easeInOut) { viewModel.showRetro = true }
        } else {
            navigation.open(destination)
        }
    }
    
    // MARK: - Tabs
    
    /// The four tabs: Tarefas, Compras, Recompensas and Perfil. The progress screen is opened from
    /// the progress cards on Tarefas.
    private var tabs: some View {
        TabView(selection: $navigation.selectedTab) {
            ChoresView()
                .tabItem {
                    Label("Tarefas", systemImage: "checklist")
                }
                .tag(AppTab.chores)
             
            ShopListView()
                .tabItem {
                    Label("Compras", systemImage: "basket")
                }
                .tag(AppTab.shopping)
            
            GamificationView(viewModel: viewModel.gamification)
                .tabItem {
                    Label("Recompensas", systemImage: "gift")
                }
                .tag(AppTab.rewards)
            
            UserProfileView()
                .tabItem {
                    Label("Perfil", systemImage: "person.fill")
                }
                .tag(AppTab.profile)
        }
    }
}

#Preview {
    ContentView()
}
