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
    
    /// Whether ``PremiumWelcomeView`` is on screen (once per house, see ``PremiumWelcome``).
    @State private var showPremiumWelcome = false
    
    /// Whether the app is active (re-checks the house and the retrospective when it comes back).
    @Environment(\.scenePhase) private var scenePhase

    /// Text shared from another app (Share Extension), shown in ``SharedImportView``.
    @State private var sharedEntry: SharedInbox.Entry?
    
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
        .alert("Trocar de casa?", isPresented: $viewModel.showInviteAcceptAlert) {
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
            Text("Você só pode participar de uma casa por vez. Ao aceitar o convite, você sai da casa atual e perde as suas tarefas, pontos e moedas nela.")
                + Text(verbatim: PremiumManager.shared.leaveWarning.map { "\n\n" + $0 } ?? "")
        }
        // MARK: Errors and deleted house
        .alert(viewModel.errorTitle ?? L10n.tr("Algo não funcionou"), isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? L10n.tr("Verifique sua conexão e tente novamente."))
        }
        
        // MARK: Premium welcome, the first time in a Premium house
        .sheet(isPresented: $showPremiumWelcome, onDismiss: {
            // Something shared while the welcome was open shows next.
            openSharedText()
        }) {
            PremiumWelcomeView()
        }
        .onChange(of: premiumWelcomeCheckID, initial: true) { _, _ in
            showPremiumWelcomeIfNeeded()
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
            openSharedText()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                openSharedText()
                Task {
                    await viewModel.fetchHouse()
                    await viewModel.checkRetro()
                }
            }
        }
        // MARK: Text shared from another app: opened by the extension (pipa://import), or found
        // waiting when the app comes to the front.
        .onOpenURL { url in
            if SharedInbox.isImportURL(url) { openSharedText() }
        }
        .sheet(item: $sharedEntry, onDismiss: {
            // Several texts shared while the app was closed: one after the other.
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                openSharedText()
            }
        }) { entry in
            SharedImportView(entry: entry)
        }
    }
    
    // MARK: - Shared text

    /// Shows the next text shared from another app, once the tabs are on screen. It leaves the
    /// inbox as soon as it's shown, so it never opens twice (cards already saved would repeat).
    private func openSharedText() {
        // Waits for the Premium welcome: one sheet at a time.
        guard sharedEntry == nil, !showPremiumWelcome, !viewModel.isLoading, !viewModel.userHasNoHouse,
              viewModel.connectionError == nil,
              let next = SharedInbox.next
        else { return }
        SharedInbox.remove(next.id)
        sharedEntry = next
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
    
    // MARK: - Premium welcome

    /// Changes whenever the Premium welcome may have become due: the house or its Premium
    /// status loaded, or the screens it waits for went away.
    private var premiumWelcomeCheckID: String {
        let premium = PremiumManager.shared
        return [
            premium.currentHouseToken?.uuidString ?? "",
            "\(premium.isPremium)",
            "\(viewModel.isLoading)",
            "\(viewModel.showRetro)",
            "\(viewModel.userHasNoHouse)"
        ].joined(separator: "|")
    }

    /// Opens ``PremiumWelcomeView`` the first time this device opens a Premium house, once the
    /// tabs are on screen and the retrospective is closed.
    private func showPremiumWelcomeIfNeeded() {
        guard !viewModel.isLoading, !viewModel.showRetro, !viewModel.userHasNoHouse,
              viewModel.connectionError == nil, !showPremiumWelcome,
              PremiumWelcome.isDue else { return }
        PremiumWelcome.markShown()
        showPremiumWelcome = true
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
