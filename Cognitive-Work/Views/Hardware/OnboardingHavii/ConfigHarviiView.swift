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
    /// Erasing couldn't reach the Harvii: offers to forget it for the whole house anyway.
    @State private var showsForceEraseAlert = false
    /// Changing the Wi-Fi couldn't reach the Harvii: offers to set it up anyway (it may already be
    /// waiting on its HARVII network, after a wrong password).
    @State private var showsSetUpAnywayAlert = false
    
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
        .alert("Trocar o Wi-Fi do Harvii?", isPresented: $showsEditWifiConfirmation) {
            Button("Trocar Wi-Fi") {
                resetHarvii(thenSetUpAgain: true)
            }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("O Harvii vai esquecer o Wi-Fi atual e você vai configurá-lo de novo. Os outros celulares da casa também precisarão parear de novo.")
        }
        .alert("Apagar o Wi-Fi do Harvii?", isPresented: $showsEraseConfirmation) {
            Button("Apagar", role: .destructive) {
                resetHarvii(thenSetUpAgain: false)
            }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("O Harvii vai esquecer o WiFi e todos os celulares da casa precisarão configurar e parear de novo.")
        }
        .alert("Não foi possível falar com o Harvii", isPresented: $showsSetUpAnywayAlert) {
            Button("Configurar o Wi-Fi") {
                hardwareViewModel.resetNavigation()
                isShowingSetup = true
            }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("Se a tela do Harvii mostrar “Não consegui conectar ao WiFi”, ele já está esperando um Wi-Fi novo. Se não, segure o botão BOOT dele por 5 segundos e depois configure o Wi-Fi.")
        }
        .alert("Não foi possível falar com o Harvii", isPresented: $showsForceEraseAlert) {
            Button("Apagar mesmo assim", role: .destructive) {
                forgetHarviiForHouse()
            }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("Você pode apagar as configurações do Harvii da casa mesmo assim: alguém deverá parear novamente e todos os moradores vão precisar configurá-lo de novo. O aparelho só esquece o Wi-Fi quando alguém segura o botão BOOT dele por 5 segundos.")
        }
        .alert("Celular desconectado", isPresented: $disconectThisPhone) {
            Button("OK") { onClose() }
        } message: {
            Text("Este celular não recebe mais as atualizações do Harvii. Você pode parear de novo quando quiser.")
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
                if thenSetUpAgain {
                    // "Edite seu Wi-Fi": the Harvii may already be on its HARVII network.
                    showsSetUpAnywayAlert = true
                } else {
                    // "Apagar seu Wi-Fi do Harvii": offer to forget it for the house anyway.
                    showsForceEraseAlert = true
                }
            }
            isResetting = false
        }
    }
    
    /// Forgets the Harvii for the whole house without reaching it, then closes the screen.
    private func forgetHarviiForHouse() {
        isResetting = true
        Task {
            await hardwareViewModel.forgetHardwareForHouse()
            isResetting = false
            onClose()
        }
    }
}

#Preview {
    NavigationStack {
        ConfigHarviiView(hardwareViewModel: HardwareViewModel(), onClose: {})
    }
}
