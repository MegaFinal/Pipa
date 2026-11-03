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
    
    /// Whether the app is active (re-checks the house and the retrospective when it comes back).
    @Environment(\.scenePhase) private var scenePhase
    
    // MARK: - Body
    
    var body: some View {
        Group {
            // MARK: Loading screen, then the tabs
            if viewModel.isLoading {
                LoadingScreen()
            } else {
                tabs
            }
        }
        .environment(tabBarVisibility)
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
        
        .alert("A casa que você pertencia foi deletada.", isPresented: $viewModel.userHasNoHouse) {
            Button("Ok", role: .confirm) {
                viewModel.accountWithoutHouseReturnToOnboarding()
            }
        } message: {
            Text("Você será redirecionado ao início do aplicativo.")
        }
        
        // MARK: Blocking screens
        .blockingOperation(isPresented: $viewModel.isSwitchingHouse, message: "Trocando de casa...")
        .blockingWhileUnlinkingOrphanedHouse()
        
        // MARK: Loading and refreshing
        .task {
            await viewModel.bootstrap()
            await viewModel.checkRetro()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cloudKitDidChange)) { _ in
            Task { await viewModel.fetchHouse() }
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
    
    // MARK: - Tabs
    
    /// The four tabs: Tarefas, Compras, Recompensas and Perfil. The progress screen is opened from
    /// the progress cards on Tarefas.
    private var tabs: some View {
        TabView {
            ChoresView()
                .tabItem {
                    Label("Tarefas", systemImage: "checklist")
                }
             
            ShopListView()
                .tabItem {
                    Label("Compras", systemImage: "basket")
                }
            
            GamificationView()
                .tabItem {
                    Label("Recompensas", systemImage: "gift")
                }
            
            UserProfileView()
                .tabItem {
                    Label("Perfil", systemImage: "person.fill")
                }
        }
    }
}

#Preview {
    ContentView()
}
