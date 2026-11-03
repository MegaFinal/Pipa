//
//  ProfileView.swift
//  Cognitive-Work
//
//  Created by Carolina Sun on 31/08/26.
//

import SwiftUI
import PhotosUI
import CloudKit

/// The profile tab: the user's banner, photo and name, and links to the settings screens.
struct UserProfileView: View {
    /// The signed-in user's profile.
    @State private var viewModelUser: UserProfileViewModel
    /// The house settings and the admin status.
    @State private var viewModelHouse = HouseEditViewModel()
    /// The hardware (Harvii) connection. Its button is hidden for now.
    @State private var viewModelHardware = HardwareViewModel()
    /// Used by the "Alterar Tempo Livre" screen.
    @State private var viewModelOnboarding = OnboardingViewModel()
    /// Whether the edit profile sheet is open.
    @State private var isEditingProfile = false
    
    init(viewModelUser: UserProfileViewModel = UserProfileViewModel()) {
        self._viewModelUser = State(initialValue: viewModelUser)
    }
    
    // MARK: - Banner, photo and name; settings links
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                userInfo
                
                SettingsButtonsSection(
                    viewModelUser: viewModelUser,
                    viewModelHouse: viewModelHouse,
                    viewModelHardware: $viewModelHardware,
                    viewModelOnboarding: $viewModelOnboarding
                )
            }
            .ignoresSafeArea(edges: .top)
            .background(Color.groupedBackground.ignoresSafeArea())
            // MARK: - Edit profile button
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        viewModelUser.startEditing()
                        isEditingProfile = true
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundColor(.black)
                    }
                    .accessibilityLabel(Text("Editar Perfil"))
                    .voiceControlNames([L10n.tr("Editar"), L10n.tr("Editar Perfil")])
                    .disabled(viewModelUser.user == nil)
                }
            }
            .tabBarVisibilityRoot()
        }
        // MARK: - Edit profile sheet
        .sheet(isPresented: $isEditingProfile, onDismiss: discardUnsavedEdits) {
            ProfileBannerSheet(
                banner: viewModelUser.editedBanner,
                image: viewModelUser.displayedImageData.flatMap(UIImage.init(data:)),
                photoSelection: $viewModelUser.selectedPhotoItem,
                photoPickerStyle: .pencilButton
            ) { banner in
                viewModelUser.editedBanner = banner
                Task { await viewModelUser.saveChanges() }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        // MARK: - Loads the user, the hardware and the admin status
        .task {
            async let loadUserTask: () = viewModelUser.loadUser()
            async let loadIpTask: () = viewModelHardware.fetchHostName()
            async let loadAdminTask: Bool = viewModelHouse.checkAdminStatus()
            
            _ = await (loadUserTask, loadIpTask, loadAdminTask)
        }
        // MARK: - Save error alert and saving spinner
        .alert(
            "Não foi possível salvar",
            isPresented: Binding(
                get: { viewModelUser.errorMessage != nil },
                set: { if !$0 { viewModelUser.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        }
        message: {
            Text(viewModelUser.errorMessage ?? "")
        }
        .overlay {
            if viewModelUser.isSaving {
                ProgressView()
                    .voiceOverLabel(L10n.tr("Salvando"))
            }
        }
    }
    
    private func discardUnsavedEdits() {
        guard viewModelUser.isEditing, !viewModelUser.isSaving else { return }
        viewModelUser.cancelEditing()
    }
    
    /// The banner with the photo in its curve, and the name below.
    private var userInfo: some View {
        VStack(spacing: 12) {
            ProfileHero(
                banner: viewModelUser.displayedBanner,
                image: viewModelUser.displayedImageData.flatMap(UIImage.init(data:))
            )
            
            Text(viewModelUser.user?.name ?? "")
                .font(.system(size: 22))
                .bold()
        }
        .accessibilityElement(children: .ignore)
        .voiceOverLabel(viewModelUser.accessibilityProfileSummary)
        .voiceControlNames(viewModelUser.accessibilityProfileInputLabels)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The list of settings links, plus the hardware sheet.
private struct SettingsButtonsSection: View {
    var viewModelUser: UserProfileViewModel
    var viewModelHouse: HouseEditViewModel
    @Binding var viewModelHardware: HardwareViewModel
    @Binding var viewModelOnboarding: OnboardingViewModel
    
    @State private var hardwareSheet: HardwareSheet?
    /// Shows ``PremiumView`` (plans or subscription status).
    @State private var isShowingPremium = false

    var body: some View {
        List {
            // MARK: - Premium
            Section {
                DisclosureButton(
                    "Pipa Premium",
                    value: PremiumManager.shared.isPremium ? L10n.tr("Ativo") : nil
                ) {
                    isShowingPremium = true
                }
                .voiceControlNames([L10n.tr("Premium"), L10n.tr("Assinatura")])
            }

            // MARK: - Settings
            Section {
                NavigationLink("Configurações Gerais") {
                    GeneralProfileSettingsView(viewModel: viewModelUser, houseViewModel: viewModelHouse)
                }
                .voiceControlNames([L10n.tr("Configurações Gerais"), L10n.tr("Configurações"), L10n.tr("Ajustes")])
                
                NavigationLink("Ajustes da Casa") {
                    HouseSettingsView(viewModel: viewModelHouse)
                }
                .voiceControlNames([L10n.tr("Ajustes da Casa"), L10n.tr("Casa")])
                
                NavigationLink("Alterar Tempo Livre") {
                    SelectFreeTimeOnboardingView(viewModel: $viewModelOnboarding, isFromSettings: true)
                }
                .voiceControlNames([L10n.tr("Alterar Tempo Livre"), L10n.tr("Tempo livre")])
                
                NavigationLink("Sobre nós") {
                    AboutUsView()
                }
            }
            
            // MARK: - Hardware connection
            Section {
                Button("Conectar com Hardware") {
                    if viewModelHardware.isPaired {
                        hardwareSheet = .existing
                    } else if !viewModelHardware.hostName.isEmpty {
                        hardwareSheet = .pair
                    } else {
                        hardwareSheet = .wifi
                    }
                }
            }
            .listRowBackground(Color.clear)
        }
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .sheet(isPresented: $isShowingPremium) {
            PremiumView()
        }
        // MARK: - Hardware sheet
        .sheet(item: $hardwareSheet) { sheet in
            Group {
                switch sheet {
                case .existing:
                    ExistingIPView(
                        viewModelHardware: $viewModelHardware,
                        profileImage: viewModelUser.displayedImageData.flatMap { UIImage(data: $0) }
                    )
                case .pair:
                    NavigationStack {
                        DevicePairView(
                            hardwareViewModel: viewModelHardware,
                            onClose: { hardwareSheet = nil }
                        )
                    }
                case .wifi:
                    WifiCredentialsView(viewModel: viewModelHardware)
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }
}

/// Which hardware screen the sheet shows, decided when the button is tapped.
private enum HardwareSheet: Identifiable {
    /// Already paired; connected Wi-Fi; needs Wi-Fi.
    case existing, pair, wifi
    /// The case itself, for `sheet(item:)`.
    var id: Self { self }
}

// MARK: - Preview

#Preview {
    let mockUser = UserModel(
        name: "Dayô Araújo",
        tier: .tier1,
        ownerRecordName: "preview-owner"
    )
    mockUser.banner = ProfileBanner(color: .purple, pattern: .stars)
    
    return UserProfileView(viewModelUser: UserProfileViewModel(user: mockUser))
}
