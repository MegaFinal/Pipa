//
//  PairedView.swift
//  Cognitive-Work
//
//  Created by Isabela Hissa Pinto on 28/10/26.
//

import SwiftUI

/// The Harvii screen once its Wi-Fi is set up: shows whether this phone is paired with it, and
/// pairs or unpairs it.
struct PairedView: View {
    /// The device connection's view model.
    @Bindable var hardwareViewModel: HardwareViewModel
    /// Shows the "Celular desconectado" alert.
    @State private var disconectThisPhone = false
    /// Closes the whole sheet, not just this step.
    var onClose: () -> Void
    /// Opens ``ConfigHarviiView`` (the gear).
    @State private var isShowingConfig = false
    
    /// Whether this phone is paired with the Harvii; the screen switches as soon as it changes.
    private var isPaired: Bool { hardwareViewModel.isPaired }
    
    var body: some View {
        VStack(alignment: .leading) {
            titleText
                .padding(.bottom, height * 0.014)
            
            descriptionText
            
            networkBox
                .padding(.top, height * 0.02)
            
            Spacer()
            
            actionButton
                .padding(.bottom, height * 0.14)
        }
        .padding(.horizontal, height * 0.028)
        .navigationTitle("Harvii")
        .navigationBarTitleDisplayMode(.inline)
        // MARK: - Toolbar: back (closes the sheet) and settings
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .voiceOverLabel(L10n.tr("Voltar"))
                .voiceControlNames([L10n.tr("Voltar"), L10n.tr("Fechar")])
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingConfig = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .voiceOverLabel(L10n.tr("Configurações do Harvii"))
                .voiceControlNames([L10n.tr("Configurações"), L10n.tr("Ajustes")])
            }
        }
        .navigationDestination(isPresented: $isShowingConfig) {
            ConfigHarviiView(hardwareViewModel: hardwareViewModel, onClose: onClose)
        }
        // Another resident may have set up the Harvii: get its host name to pair.
        .task {
            await hardwareViewModel.fetchHostName()
        }
        // The button only shows a spinner while pairing: say it out loud.
        .onChange(of: hardwareViewModel.isPairing) { _, isPairing in
            if isPairing { VoiceOver.announce(L10n.tr("Pareando com o Harvii…")) }
        }
        // The title switches to "pareado": tell VoiceOver too.
        .onChange(of: isPaired) { _, isPaired in
            VoiceOver.announce(isPaired ? L10n.tr("Pareamento completo!") : L10n.tr("Celular desconectado."))
        }
        
        // MARK: - Alerts
        .alert("Celular desconectado.", isPresented: $disconectThisPhone) {
            // Stays here: the screen now shows "despareado" and the "Parear" button.
            Button("OK") { }
        } message: {
            Text("Seu celular foi desconectado com sucesso!")
        }
        .alert(
            HardwareViewModel.ConectionResult.failureParing.title,
            isPresented: Binding(
                get: { hardwareViewModel.conectionResult == .failureParing },
                set: { if !$0 { hardwareViewModel.conectionResult = nil } }
            )
        ) {
            Button("OK") { hardwareViewModel.conectionResult = nil }
        } message: {
            Text(hardwareViewModel.pairingErrorDetail ?? HardwareViewModel.ConectionResult.failureParing.message)
        }
    }
}

// MARK: - Subviews

private extension PairedView {
    
    /// "Seu Harvii está pareado!" in green, or "despareado!" in orange.
    var titleText: some View {
        Group {
            if isPaired {
                Text("Seu Harvii está\n\(Text("pareado").foregroundStyle(.choreGreen))!")
            } else {
                Text("Seu Harvii está\n\(Text("despareado").foregroundStyle(.choreOrange))!")
            }
        }
        .font(.custom("Alan Sans", fixedSize: 32))
        .bold()
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
    }
    
    /// What the pairing means right now.
    var descriptionText: some View {
        Group {
            if isPaired {
                Text("Harvii está recebendo as atualizações das tarefas da sua casa em tempo real!\nQuando alguém completar alguma tarefa no celular, o Harvii atualizará sozinho.")
            } else {
                Text("Este celular não está pareado com o Harvii, então ele não recebe as atualizações feitas por aqui.\nConecte-se à rede da sua casa e toque em Parear.")
            }
        }
        .font(.system(size: 17))
        .fixedSize(horizontal: false, vertical: true)
    }
    
    /// The home Wi-Fi the Harvii uses.
    var networkBox: some View {
        let wifiName = hardwareViewModel.wifiName.isEmpty
            ? L10n.tr("Sem WiFi armazenado")
            : hardwareViewModel.wifiName
        
        return VStack(alignment: .leading, spacing: 8) {
            Text("Nome da sua rede")
                .font(.system(size: 15).weight(.semibold))
            
            Text(wifiName)
                .font(.system(size: 17))
                .foregroundStyle(.subTitleGray)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGroupedBackground), in: .rect(cornerRadius: 20))
        }
        // Read as one element: "Nome da sua rede, Casa da Bela".
        .accessibilityElement(children: .combine)
    }
    
    /// "Desparear" (gray) when paired, "Parear" (blue, with a spinner while pairing) when not.
    @ViewBuilder
    var actionButton: some View {
        if isPaired {
            Button {
                hardwareViewModel.disconnectThisPhone()
                disconectThisPhone = true
            } label: {
                Text("Desparear")
                    .font(.system(size: 17).weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(.systemGray5), in: .capsule)
            }
            .voiceControlNames([L10n.tr("Desparear este celular"), L10n.tr("Desparear")])
            .buttonStyle(.plain)
        } else {
            Button {
                Task { await hardwareViewModel.pair() }
            } label: {
                ZStack {
                    // Keeps the height while the spinner shows.
                    Text("Parear")
                        .font(.system(size: 17).weight(.semibold))
                        .opacity(hardwareViewModel.isPairing ? 0 : 1)
                    if hardwareViewModel.isPairing {
                        ProgressView()
                            .tint(.white)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.blue, in: .capsule)
            }
            .voiceOverLabel(L10n.tr("Parear"))
            .voiceOverValue(hardwareViewModel.isPairing ? L10n.tr("Pareando com o Harvii…") : "")
            .voiceControlNames([L10n.tr("Parear"), L10n.tr("Parear este celular")])
            .buttonStyle(.plain)
            .disabled(hardwareViewModel.isPairing || hardwareViewModel.hostName.isEmpty)
        }
    }
}

#Preview {
    let vm = HardwareViewModel()
    vm.wifiName = "Rede maneira"
    return NavigationStack {
        PairedView(hardwareViewModel: vm, onClose: {})
    }
}
