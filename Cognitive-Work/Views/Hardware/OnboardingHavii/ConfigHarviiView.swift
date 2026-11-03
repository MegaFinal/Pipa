//
//  ConfigHarviiView.swift
//  Cognitive-Work
//
//  Created by Isabela Hissa Pinto on 03/11/26.
//

import SwiftUI

/// Harvii settings, opened from the gear on ``PairedView``: change its Wi-Fi, forget it on this
/// iPhone, or erase its Wi-Fi.
struct ConfigHarviiView: View {
    /// The device connection's view model.
    @Bindable var hardwareViewModel: HardwareViewModel
    
    /// Closes the whole sheet, not just this step.
    var onClose: () -> Void
    
    /// Asks before resetting the Harvii to set up a new Wi-Fi.
    @State private var showsEditWifiConfirmation = false
    /// Asks before erasing the Harvii's Wi-Fi.
    @State private var showsEraseConfirmation = false
    /// Shows the "Celular desconectado" alert.
    @State private var disconectThisPhone = false
    /// `true` while the Harvii is being reset.
    @State private var isResetting = false
    /// Opens the setup again (from "Entre na rede do Harvii") after the reset.
    @State private var isShowingSetup = false
    /// Error shown in the alert, when the Harvii couldn't be reached.
    @State private var errorMessage: String?
    
    var body: some View {
        List {
            // MARK: - Change Wi-Fi
            Section {
                DisclosureButton("Edite seu Wi-Fi") {
                    showsEditWifiConfirmation = true
                }
                .voiceControlNames([L10n.tr("Edite seu Wi-Fi"), L10n.tr("Wi-Fi")])
            } header: {
                Text("Perfil do usuário")
            } footer: {
                Text("Troque o Wi-Fi ao qual o Harvii está conectado.")
            }
            
            // MARK: - Forget on this iPhone
            Section {
                DisclosureButton("Desconectar o aparelho do Harvii") {
                    hardwareViewModel.disconnectThisPhone()
                    disconectThisPhone = true
                }
                .voiceControlNames([L10n.tr("Desconectar o aparelho do Harvii"), L10n.tr("Desconectar")])
            } footer: {
                Text("Esqueça o Harvii do seu iPhone.")
            }
        }
        .listSectionSpacing(.compact)
        .disabled(isResetting)
        // MARK: - Erase Wi-Fi
        .safeAreaInset(edge: .bottom) {
            eraseButton
        }
        .navigationTitle("Configurações do Harvii")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isResetting)
        .navigationDestination(isPresented: $isShowingSetup) {
            EnterHarviiNetwork(viewModel: hardwareViewModel, onClose: onClose)
        }
        
        // MARK: - Confirmations and alerts
        .confirmationDialog(
            "Trocar o Wi-Fi do Harvii?",
            isPresented: $showsEditWifiConfirmation,
            titleVisibility: .visible
        ) {
            Button("Trocar Wi-Fi") {
                resetHarvii(thenSetUpAgain: true)
            }
        } message: {
            Text("O Harvii vai esquecer o Wi-Fi atual e você vai configurá-lo de novo. Os outros celulares da casa também precisarão parear de novo.")
        }
        .confirmationDialog(
            "Apagar o Wi-Fi do Harvii?",
            isPresented: $showsEraseConfirmation,
            titleVisibility: .visible
        ) {
            Button("Apagar", role: .destructive) {
                resetHarvii(thenSetUpAgain: false)
            }
        } message: {
            Text("O Harvii vai esquecer o WiFi e todos os celulares da casa precisarão configurar e parear de novo.")
        }
        .alert("Celular desconectado.", isPresented: $disconectThisPhone) {
            Button("OK") { onClose() }
        } message: {
            Text("Seu celular foi desconectado com sucesso!")
        }
        .alert("Ops", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? L10n.tr("Ocorreu um erro."))
        }
    }
    
    // MARK: - Erase button
    
    /// Red text button at the bottom; a spinner while resetting.
    private var eraseButton: some View {
        Button(role: .destructive) {
            showsEraseConfirmation = true
        } label: {
            if isResetting {
                ProgressView()
            } else {
                Text("Apagar seu Wi-Fi do Harvii")
            }
        }
        .voiceOverLabel(L10n.tr("Apagar seu Wi-Fi do Harvii"))
        .voiceOverValue(isResetting ? L10n.tr("Resetando") : "")
        .voiceControlNames([L10n.tr("Apagar seu Wi-Fi do Harvii"), L10n.tr("Apagar")])
        .disabled(isResetting)
        .frame(maxWidth: .infinity)
        .padding(.bottom, height * 0.03)
    }
    
    // MARK: - Actions
    
    /// Wipes the Harvii's Wi-Fi (it goes back to its own HARVII network). Then either opens the
    /// setup to pick a new Wi-Fi, or closes the sheet.
    private func resetHarvii(thenSetUpAgain: Bool) {
        isResetting = true
        VoiceOver.announce(L10n.tr("Resetando o Harvii…"))
        Task {
            do {
                try await hardwareViewModel.resetHardware()
                if thenSetUpAgain {
                    hardwareViewModel.resetNavigation()
                    isShowingSetup = true
                } else {
                    onClose()
                }
            } catch {
                errorMessage = L10n.tr("Não foi possível falar com o Harvii. Segure o botão BOOT por 5 segundos para resetar direto no dispositivo.")
            }
            isResetting = false
        }
    }
}

#Preview {
    NavigationStack {
        ConfigHarviiView(hardwareViewModel: HardwareViewModel(), onClose: {})
    }
}
