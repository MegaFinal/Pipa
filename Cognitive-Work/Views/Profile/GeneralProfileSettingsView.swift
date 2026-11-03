//
//  GeneralProfileSettingsView.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 03/09/26.
//

import SwiftUI
import UserNotifications

/// The "Configurações Gerais" screen: name, Pix key, notifications, language, haptics, microinteractions,
/// calendar sync and deleting the profile.
struct GeneralProfileSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var viewModel: UserProfileViewModel
    @Bindable var houseViewModel: HouseEditViewModel
    @State private var showNotificationsDeniedAlert = false
    @State private var showDeleteConfirmation = false
    @State private var showAdminDeleteConfirmation = false
    @State private var isDeletingAccount = false
    /// The sheet open on top of the screen, or `nil`.
    @State private var activeSheet: SettingsSheet?
        
    @AppStorage(HapticsManager.storageKey) private var areHapticsEnabled = true
    @AppStorage("notificationsEnabled") private var areNotificationsEnabled = false
    @AppStorage("didOnboard") private var didOnboard: Bool = true
    /// Saved for the "Microinterações" switch. Nothing in the app reads it yet.
    @AppStorage("microinteractionsEnabled") private var areMicrointeractionsEnabled = true
    
    private let languageManager = LanguageManager.shared
    private var languageSelection: Binding<AppLanguage> {
        Binding(
            get: { languageManager.current },
            set: { languageManager.setLanguage($0) }
        )
    }
    
    /// The notifications switch: turning it on asks for permission first.
    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { areNotificationsEnabled },
            set: { isOn in
                if isOn {
                    enableNotifications()
                } else {
                    areNotificationsEnabled = false
                }
            }
        )
    }
    
    /// Asks for system permission; if the user already denied it, offers to open Settings.
    private func enableNotifications() {
        Task {
            let center = UNUserNotificationCenter.current()
            let status = await center.notificationSettings().authorizationStatus
            switch status {
            case .authorized, .provisional, .ephemeral:
                areNotificationsEnabled = true
            case .notDetermined:
                let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
                areNotificationsEnabled = granted
            default:
                areNotificationsEnabled = false
                showNotificationsDeniedAlert = true
            }
        }
    }
    
    /// Keeps the switch honest if the user revoked permission in iOS Settings.
    private func syncNotificationsWithSystem() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if status == .denied { areNotificationsEnabled = false }
    }
    
    var body: some View {
        List {
            // MARK: - Perfil do usuário
            Section("Perfil do usuário") {
                DisclosureButton("Seu nome", value: viewModel.privateUser?.name ?? viewModel.user?.name ?? "") {
                    activeSheet = .name
                }
                .voiceControlNames([L10n.tr("Seu nome"), L10n.tr("Nome")])
            }
            
            Section {
                DisclosureButton("Chave Pix") { activeSheet = .pix }
            }
            
            Section {
                Toggle("Permitir notificações", isOn: notificationsBinding)
            }
            
            // MARK: - Personalização da experiência
            Section("Personalização da experiência") {
                Picker("Idioma", selection: languageSelection) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(verbatim: language.nativeName)
                            .tag(language)
                    }
                }
                .pickerStyle(.menu)
                .voiceControlNames([languageManager.current.nativeName, L10n.tr("Idioma"), L10n.tr("Língua")])
            }
            
            Section {
                Toggle("Haptics", isOn: $areHapticsEnabled)
                    .voiceControlNames([L10n.tr("Haptics"), L10n.tr("Vibração")])
                    .onChange(of: areHapticsEnabled) { _, isOn in
                        if isOn { HapticsManager.impact(.medium) }
                    }
            } footer: {
                Text("Vibrações ao concluir uma tarefa.")
            }
            
            Section {
                Toggle("Microinterações", isOn: $areMicrointeractionsEnabled)
            } footer: {
                Text("Pequenos efeitos e animações que servem como um retorno visual.")
            }
            
            Section {
                Toggle(isOn: $viewModel.isCalendarSyncEnabled) {
                    HStack {
                        Text("Sincronizar com Apple Calendar")
                        if viewModel.isSyncingCalendar {
                            ProgressView()
                                .controlSize(.small)
                                .voiceOverLabel(L10n.tr("Sincronizando"))
                        }
                    }
                }
                .disabled(viewModel.isSyncingCalendar)
                .voiceControlNames([L10n.tr("Sincronizar com Apple Calendar"), L10n.tr("Calendário")])
            } footer: {
                Text("Adicionar automaticamente as suas tarefas ao Apple Calendar (Pipa).")
            }
        }
        .listSectionSpacing(.compact)
        // MARK: - Delete account button (pinned to the bottom of the screen)
        .safeAreaInset(edge: .bottom) {
            Button("Excluir perfil", role: .destructive) {
                Task {
                    let isAdmin = await houseViewModel.checkAdminStatus()
                    if isAdmin {
                        showAdminDeleteConfirmation = true
                    } else {
                        showDeleteConfirmation = true
                    }
                }
            }
            .voiceControlNames([L10n.tr("Excluir Perfil"), L10n.tr("Excluir"), L10n.tr("Apagar")])
            .padding(.vertical, 12)
        }
        // MARK: - Edit name / Pix key sheets
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .name: EditNameView(viewModel: viewModel)
            case .pix: PixKeySettingsView(viewModel: viewModel)
            }
        }
        .navigationTitle("Configurações Gerais")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBar()
        
        // MARK: - Keeps the notifications switch in sync with iOS Settings
        .task { await syncNotificationsWithSystem() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await syncNotificationsWithSystem() } }
        }
        
        // MARK: - Alerts
        .alert("Notificações desativadas", isPresented: $showNotificationsDeniedAlert) {
            Button("Cancelar", role: .cancel) {}
            Button("Abrir Ajustes") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("Para receber notificações, permita-as nos Ajustes do iPhone.")
        }
        .alert("Excluir Perfil?", isPresented: $showDeleteConfirmation) {
            Button("Cancelar", role: .cancel) {}
            Button("Excluir", role: .destructive) {
                isDeletingAccount = true
                Task {
                    await viewModel.deleteAccount()
                    await houseViewModel.getOutOfTheHouse()
                    if viewModel.errorMessage == nil {
                        didOnboard = false
                    } else {
                        isDeletingAccount = false
                    }
                }
            }
        } message: {
            Text("Ao apagar seu perfil, você também sairá da casa e perderá o acesso às tarefas e ao histórico. A casa continuará existindo para os outros moradores. Essa ação não pode ser desfeita.")
        }
        
        .alert("Excluir Perfil?", isPresented: $showAdminDeleteConfirmation) {
            Button("Cancelar", role: .cancel) {}
            Button("Excluir", role: .destructive) {
                isDeletingAccount = true
                Task {
                    await viewModel.deleteAccount()
                    await houseViewModel.deleteHouse()
                    if viewModel.errorMessage == nil {
                        didOnboard = false
                    } else {
                        isDeletingAccount = false
                    }
                }
            }
        } message: {
            Text("Você é o administrador desta casa. Ao apagar seu perfil, a casa também será apagada para todos os moradores, junto com as tarefas. Essa ação não pode ser desfeita.")
        }
        // MARK: - Blocking loading screen
        .blockingOperation(isPresented: $isDeletingAccount, message: "Excluindo seu perfil...")
    }
}

/// The sheets opened from the "Configurações Gerais" rows.
private enum SettingsSheet: Identifiable {
    case name, pix
    var id: Self { self }
}

#Preview {
    let mockUser = UserModel(
        name: "Preview User",
        tier: .tier1,
        ownerRecordName: "preview-owner"
    )
    let mockViewModel = UserProfileViewModel(user: mockUser)
    let mockHouseViewModel = HouseEditViewModel()

    NavigationStack {
        GeneralProfileSettingsView(viewModel: mockViewModel, houseViewModel: mockHouseViewModel)
    }
}
