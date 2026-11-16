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
    @AppStorage(NotificationManager.enabledKey) private var areNotificationsEnabled = false
    @AppStorage("didOnboard") private var didOnboard: Bool = true
    /// Saved for the "Microinterações" switch. Nothing in the app reads it yet.
    @AppStorage("microinteractionsEnabled") private var areMicrointeractionsEnabled = true
    /// "Sugestões da IA": read by every suggestion through ``IntelligenceManager/areSuggestionsEnabled``.
    @AppStorage(IntelligenceManager.suggestionsEnabledKey) private var areAISuggestionsEnabled = true
    /// The Premium paywall, opened from the locked "Sugestões da IA" switch on the free plan.
    @State private var paywall: PremiumFeature?
    
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
                    // Nothing that was already scheduled should show up after turning it off.
                    NotificationManager.shared.cancelAll()
                }
            }
        )
    }
    
    /// Asks for system permission; if the user already denied it, offers to open Settings.
    private func enableNotifications() {
        Task {
            let manager = NotificationManager.shared
            switch await manager.authorizationStatus() {
            case .authorized, .provisional, .ephemeral:
                areNotificationsEnabled = true
            case .notDetermined:
                areNotificationsEnabled = await manager.requestAuthorization()
            default:
                areNotificationsEnabled = false
                showNotificationsDeniedAlert = true
            }
            // Plans the reminders (retrospective, chores to pick up, payments) right away.
            if areNotificationsEnabled { await manager.refreshReminders(force: true) }
        }
    }
    
    /// Keeps the switch honest if the user revoked permission in iOS Settings.
    private func syncNotificationsWithSystem() async {
        let status = await NotificationManager.shared.authorizationStatus()
        if status == .denied { areNotificationsEnabled = false }
    }
    
    /// "Sugestões da IA" on the free plan: an off switch with the Premium crown. Turning it on,
    /// or tapping anywhere on the row, opens the paywall; the switch itself stays off.
    ///
    /// Not a `Button` around the `Toggle`: with the toggle's hit testing turned off, a plain
    /// button in a list row had nothing left to tap, so nothing happened.
    private var lockedAISuggestionsToggle: some View {
        Toggle(isOn: Binding(
            get: { false },
            set: { isOn in if isOn { openAIPaywall() } }
        )) {
            HStack(spacing: 6) {
                Text("Sugestões da IA")
                PremiumBadge()
            }
        }
        // The text side of the row opens it too, not only the switch.
        .contentShape(Rectangle())
        .onTapGesture { openAIPaywall() }
        .accessibilityElement(children: .ignore)
        .voiceOverLabel(L10n.tr("Sugestões da IA, Premium"))
        .voiceOverValue(L10n.tr("Desativado"))
        .voiceOverHint(L10n.tr("Toque duas vezes para ver o Premium."))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { openAIPaywall() }
        .voiceControlNames([L10n.tr("Sugestões da IA"), L10n.tr("Sugestões"), L10n.tr("IA"), L10n.tr("Premium")])
    }

    /// Opens the paywall on the AI features (from the locked "Sugestões da IA" switch).
    private func openAIPaywall() {
        guard paywall == nil else { return }
        HapticsManager.selection()
        paywall = .intelligence
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

            // The suggestions are Premium (see ``IntelligenceManager/areSuggestionsEnabled``). On
            // the free plan the switch shows off, with the crown, and opens the paywall.
            Section {
                if PremiumManager.shared.isPremium {
                    Toggle("Sugestões da IA", isOn: $areAISuggestionsEnabled)
                        .voiceControlNames([L10n.tr("Sugestões da IA"), L10n.tr("Sugestões"), L10n.tr("IA")])
                } else {
                    lockedAISuggestionsToggle
                }
            } footer: {
                Text("Ordem sugerida das tarefas, ideias de subtarefas, sugestões do que pode estar faltando na lista de compras e preenchimento automático ao descrever uma tarefa ou um item.")
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

            // MARK: - Delete account button
            // The list's last row, so it scrolls with the settings instead of staying pinned over
            // them. Same look as before: red text on the page background, no cell.
            Section {
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
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .voiceControlNames([L10n.tr("Excluir Perfil"), L10n.tr("Excluir"), L10n.tr("Apagar")])
            }
        }
        .listSectionSpacing(.compact)
        // MARK: - Edit name / Pix key sheets
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .name: EditNameView(viewModel: viewModel)
            case .pix: PixKeySettingsView(viewModel: viewModel)
            }
        }
        .premiumPaywall($paywall)
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
                + Text(verbatim: PremiumManager.shared.leaveWarning.map { "\n\n" + $0 } ?? "")
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
