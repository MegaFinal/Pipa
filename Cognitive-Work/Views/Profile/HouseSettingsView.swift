//
//  HouseSettingsView.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 03/09/26.
//

import SwiftUI

/// The "Ajustes da Casa" screen: invite members, manage rooms, reset the chore division (admin)
/// and delete the house (admin) or leave it (other members).
struct HouseSettingsView: View {
    @Bindable var viewModel: HouseEditViewModel
    @State var showChoreResetConfirmation = false
    @State private var isResetting = false
    @State private var showDeleteConfirmation = false
    @State private var isDeletingHouse = false
    @State private var showLeaveConfirmation = false
    @State private var isLeavingHouse = false
    @State private var leaveErrorMessage: String?
    @State private var deleteErrorMessage: String?
    /// The Premium paywall (re-dividing mid-cycle is Premium).
    @State private var paywall: PremiumFeature?
    
    /// `true` while we still don't know if the user is the admin.
    private var isCheckingAdmin: Bool { !viewModel.isAdminResolved }
    
    /// Set to `false` after deleting or leaving, which sends the user back to onboarding.
    @AppStorage("didOnboard") private var didOnboard: Bool = true
    
    /// Kept in `@State` so the invite screen keeps one instance (and its polling/share state)
    @State private var inviteViewModel = OnboardingViewModel()
    
    var body: some View {
        confirmations
            // MARK: - Error alerts, blocking overlays and admin check
            .alert(
                "Não foi possível sair",
                isPresented: Binding(
                    get: { leaveErrorMessage != nil },
                    set: { if !$0 { leaveErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(leaveErrorMessage ?? "")
            }
            .alert(
                "Não foi possível excluir",
                isPresented: Binding(
                    get: { deleteErrorMessage != nil },
                    set: { if !$0 { deleteErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteErrorMessage ?? "")
            }
            .blockingOperation(isPresented: $isLeavingHouse, message: "Saindo da casa...")
            .blockingOperation(isPresented: $isDeletingHouse, message: "Excluindo sua casa...")
            .task {
                await viewModel.checkAdminStatus()
            }
            .navigationDestination(isPresented: $isResetting) {
                FortnightlyScheduleView(shouldGenerate: true) {
                    isResetting = false
                }
            }
            .premiumPaywall($paywall)
    }
    
    // MARK: - View
    
    /// The settings list, with the delete / leave button pinned to the bottom.
    private var settingsList: some View {
        List {
            // MARK: - Add roommates
            Section {
                NavigationLink("Adicionar moradores") {
                    InviteAndWaitUsersFreeTimeOnboardingView(viewModel: $inviteViewModel, isFromSettings: true)
                        .padding(.bottom, 30)
                        .onAppear {
                            inviteViewModel.currentHouse = viewModel.house
                        }
                }
                .voiceControlNames([L10n.tr("Adicionar moradores"), L10n.tr("Convidar"), L10n.tr("Moradores")])
            }
            
            // MARK: - Rooms CRUD
            Section {
                NavigationLink("Cômodos") {
                    RoomsManagementView(house: viewModel.house)
                }
                .voiceControlNames([L10n.tr("Cômodos")])
            }
            
            // MARK: - Spinner while checking admin status
            if isCheckingAdmin {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .voiceOverLabel(L10n.tr("Verificando permissões"))
                    .listRowBackground(Color.clear)
            }
            
            // MARK: - Reset chores assignments
            if viewModel.isUserAdmin {
                Section {
                    DisclosureButton(
                        "Reiniciar divisão de tarefas",
                        value: PremiumManager.shared.isPremium ? nil : L10n.tr("Premium")
                    ) {
                        // Free plan: the division is redone automatically once per cycle.
                        if PremiumManager.shared.allows(.rebalanceDivision) {
                            showChoreResetConfirmation = true
                        } else {
                            paywall = .rebalanceDivision
                        }
                    }
                    .voiceControlNames([L10n.tr("Reiniciar divisão de tarefas"), L10n.tr("Reiniciar divisão"), L10n.tr("Reiniciar")])
                }
            }
        }
        .listSectionSpacing(.compact)
        .safeAreaInset(edge: .bottom) { bottomButton }
        .navigationTitle("Ajustes da Casa")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBar()
    }
    
    /// "Excluir Casa" for the admin; "Sair da Casa" for every other member.
    @ViewBuilder
    private var bottomButton: some View {
        if viewModel.isUserAdmin {
            Button("Excluir Casa", role: .destructive) {
                showDeleteConfirmation = true
            }
            .voiceControlNames([L10n.tr("Excluir Casa"), L10n.tr("Excluir"), L10n.tr("Apagar")])
            .padding(.vertical, 12)
        } else if !isCheckingAdmin {
            // Only the admin can delete the house; every other member can just leave it.
            Button("Sair da Casa", role: .destructive) {
                showLeaveConfirmation = true
            }
            .voiceControlNames([L10n.tr("Sair da Casa"), L10n.tr("Sair")])
            .padding(.vertical, 12)
        }
    }
    
    /// The screen with the delete, leave and reset confirmations.
    private var confirmations: some View {
        settingsList
        .alert("Excluir Casa?", isPresented: $showDeleteConfirmation) {
            Button("Cancelar", role: .cancel) {}
            Button("Excluir", role: .destructive) {
                guard viewModel.isAdminResolved, viewModel.isUserAdmin else { return }
                isDeletingHouse = true
                Task {
                    let success = await viewModel.deleteHouse()
                    if success {
                        didOnboard = false
                    } else {
                        deleteErrorMessage = L10n.tr("Não foi possível excluir a casa. Verifique sua conexão e tente novamente.")
                        isDeletingHouse = false
                    }
                }
            }
        } message: {
            Text("Esta ação é permanente. Todos os dados desta casa serão apagados do iCloud.")
        }
        .alert("Sair da Casa?", isPresented: $showLeaveConfirmation) {
            Button("Cancelar", role: .cancel) {}
            Button("Sair", role: .destructive) {
                isLeavingHouse = true
                Task {
                    if await viewModel.leaveHouse() {
                        didOnboard = false
                    } else {
                        leaveErrorMessage = L10n.tr("Não foi possível sair da casa. Verifique sua conexão e tente novamente.")
                        isLeavingHouse = false
                    }
                }
            }
        } message: {
            Text("Você deixará de ver as tarefas desta casa. Os outros moradores continuam nela e você poderá entrar de novo com um convite.")
        }
        // MARK: - Reset division alert and new division screen
        .alert("Deseja reiniciar a divisão de tarefas?", isPresented: $showChoreResetConfirmation) {
            Button("Cancelar", role: .cancel) {}
            Button("Reiniciar", role: .destructive) {
                isResetting = true
            }
        } message: {
            Text("Ao clicar em \"Reiniciar\" a divisão de tarefas atual será excluída.")
        }
    }
}

#Preview {
    let house = HouseModel(name: "Casa", description: "Casa para o preview")
    let viewModel = HouseEditViewModel(house: house)
    viewModel.isUserAdmin = true
    
    return NavigationStack {
        HouseSettingsView(viewModel: viewModel)
    }
}
