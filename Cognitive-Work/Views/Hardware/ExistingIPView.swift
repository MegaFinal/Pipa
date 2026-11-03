//
//  ExistingIPView.swift
//  Cognitive-Work
//
//  Created by anshu Li on 02/09/26.
//

import SwiftUI

/// Shown when this phone is already paired: lets the user test the device, disconnect
/// this phone or reset the device for the whole house.
struct ExistingIPView: View {
    /// The device connection's view model.
    @Binding var viewModelHardware: HardwareViewModel
    /// Closes the screen.
    @Environment(\.dismiss) private var dismiss

    /// The user's photo, sent to the device's screen.
    var profileImage: UIImage?

    /// An error to show, or `nil`.
    @State private var errorMessage: String?
    /// Shows the "Resetar o Harvii?" confirmation.
    @State private var showResetConfirmation = false
    
    /// In-flight states: both actions talk to the device over the network and took several
    /// seconds with no feedback, inviting repeated taps.
    @State private var isSendingImage = false
    @State private var isResetting = false

    var body: some View {
        VStack(spacing: 20) {
            // MARK: - Photo that will be sent
            avatarView
                .frame(width: 100, height: 100)
                .accessibilityElement(children: .ignore)
                .voiceOverLabel(L10n.tr("Imagem que será enviada ao Harvii"))
                .accessibilityAddTraits(.isImage)

            // MARK: - "Enviar imagem"
            Button {
                isSendingImage = true
                VoiceOver.announce(L10n.tr("Enviando imagem para o Harvii…"))
                Task {
                    do {
                        try await viewModelHardware.prepareImageForESP32(view: avatarForDevice)
                        HapticsManager.notify(.success)
                        VoiceOver.announce(L10n.tr("Imagem enviada para o Harvii"))
                    } catch {
                        errorMessage = L10n.tr("Não foi possível enviar a imagem para o dispositivo. Verifique a conexão e tente novamente.")
                    }
                    isSendingImage = false
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .frame(width: 150, height: 44)
                        .foregroundStyle(.orange)
                    if isSendingImage {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Enviar imagem")
                            .foregroundStyle(.white)
                            .padding()
                    }
                }
            }
            // Label stays the same while the spinner replaces the text.
            .voiceOverLabel(L10n.tr("Enviar imagem"))
            .voiceOverValue(isSendingImage ? L10n.tr("Enviando") : "")
            .voiceControlNames([L10n.tr("Enviar imagem"), L10n.tr("Enviar")])
            .disabled(isSendingImage || isResetting)

            // MARK: - "Desconectar este celular"
            Button("Desconectar este celular") {
                viewModelHardware.disconnectThisPhone()
                dismiss()
            }
            .voiceControlNames([L10n.tr("Desconectar este celular"), L10n.tr("Desconectar")])

            // MARK: - "Resetar o Harvii"
            Button(role: .destructive) {
                showResetConfirmation = true
            } label: {
                if isResetting {
                    ProgressView()
                } else {
                    Text("Resetar o Harvii")
                }
            }
            .voiceOverLabel(L10n.tr("Resetar o Harvii"))
            .voiceOverValue(isResetting ? L10n.tr("Resetando") : "")
            .voiceControlNames([L10n.tr("Resetar o Harvii"), L10n.tr("Resetar")])
            .disabled(isSendingImage || isResetting)
        }
        // MARK: - Reset confirmation
        .confirmationDialog(
            "Resetar o Harvii?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Resetar", role: .destructive) {
                isResetting = true
                VoiceOver.announce(L10n.tr("Resetando o Harvii…"))
                Task {
                    do {
                        try await viewModelHardware.resetHardware()
                        dismiss()
                    } catch {
                        errorMessage = L10n.tr("Não foi possível falar com o Harvii. Segure o botão BOOT por 5 segundos para resetar direto no dispositivo.")
                    }
                    isResetting = false
                }
            }
        } message: {
            Text("O Harvii vai esquecer o WiFi e todos os celulares da casa precisarão configurar e parear de novo.")
        }
        // MARK: - Error alert
        .alert("Ops", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? L10n.tr("Ocorreu um erro."))
        }
    }

    /// The user's photo in a circle, or a placeholder.
    private var avatarView: some View {
        Group {
            if let profileImage {
                Image(uiImage: profileImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.gray)
                    .background(.white)
            }
        }
        .clipShape(Circle())
    }

    /// The photo at the size it is rendered for the device.
    private var avatarForDevice: some View {
        avatarView
            .frame(width: 100, height: 100)
    }
}
