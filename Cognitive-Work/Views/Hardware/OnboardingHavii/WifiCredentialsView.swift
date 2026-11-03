//
//  WifiCredentialsView.swift
//  Cognitive-Work
//
//  Created by Isabela Hissa Pinto on 25/08/26.
//

import SwiftUI

/// Collects the home WiFi credentials and sends them to the ESP32 while the phone is on its network.
struct WifiCredentialsView: View {
    /// The device connection's view model.
    @Bindable var viewModel: HardwareViewModel
    /// Closes the sheet.
    @Environment(\.dismiss) private var dismiss
    
    /// Whether both fields are filled.
    private var canSubmit: Bool {
        !viewModel.userWifiName.isEmpty &&
        !viewModel.userWifiPassord.isEmpty
    }
    
    /// The Wi-Fi was already sent before (the device has a host name), so this step only has to
    /// move on to pairing.
    private var wasWifiSent: Bool { !viewModel.hostName.isEmpty }
    
    /// Whether the continue button can be tapped.
    private var canContinue: Bool { wasWifiSent || canSubmit }
    
    /// Side margin of the whole screen, the same as the onboarding steps.
    private var sideMargin: CGFloat { width * 0.0565 }
    
    var body: some View {
        NavigationStack {
            VStack (spacing: 64) {
                // MARK: - Title and instructions
                OnboardingHeader(
                    title: "Agora, digite o Wi-Fi da sua casa",
                    description: "É por ele que o Harvii vai receber as tarefas.",
                    containerInset: sideMargin
                )
                
                
                VStack(alignment: .leading, spacing: 24) {
                    
                    // MARK: - Skip to pairing (Wi-Fi already sent), or the Wi-Fi fields
                    if wasWifiSent {
                        Button("Já enviei o WiFi, ir para o pareamento") {
                            viewModel.navigateToParingView = true
                        }
                        .voiceControlNames([
                            L10n.tr("Já enviei o WiFi, ir para o pareamento"),
                            L10n.tr("Pareamento"),
                            L10n.tr("Ir para o pareamento")
                        ])
                        .font(.callout)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                    } else {
                        LabeledInput(
                            title: "Nome da sua rede",
                            spokenAlternatives: [L10n.tr("Nome da rede"), L10n.tr("Rede")]
                        ) {
                            TextField("Ex.: Casa da Bela", text: $viewModel.userWifiName)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .characterLimit(TextLimits.wifiName, text: $viewModel.userWifiName)
                        }
                        
                        // TODO: Colocar aquele negócio de olho pra ver a senha ou deixar bolina
                        LabeledInput(
                            title: "Sua senha",
                            spokenAlternatives: [L10n.tr("Senha")]
                        ) {
                            SecureField("Senha do Wi-Fi", text: $viewModel.userWifiPassord)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .characterLimit(TextLimits.wifiPassword, text: $viewModel.userWifiPassord)
                            
                        }
                    }
                }
                
                Spacer()
                
                // MARK: - Continue: sends the Wi-Fi (spinner meanwhile) or goes to pairing
                HStack {
                    Spacer()
                    OnboardingProgressButton(
                        width: width * 0.15,
                        height: width * 0.15,
                        text: "chevron.right",
                        isSystemImage: true,
                        isLoading: viewModel.isSending,
                        isDisabled: !canContinue
                    ) {
                        await continueTapped()
                    }
                }
            }
            .padding(.horizontal, sideMargin)
            .padding(.bottom, height * 0.02)
            .navigationBarTitleDisplayMode(.inline)
            
            // TODO: back button to the previous Harvii step.
            // MARK: - Pairing step, result alert and keyboard
            .navigationDestination(isPresented: $viewModel.navigateToParingView) {
                DevicePairView(hardwareViewModel: viewModel, onClose: { dismiss() })
            }
            .resultAlert($viewModel.wifiResult)
            .dismissKeyboardOnTap()
            // Sending takes a few seconds behind a spinner; the result arrives as an alert.
            .onChange(of: viewModel.isSending) { _, isSending in
                if isSending { VoiceOver.announce(L10n.tr("Enviando dados do WiFi para o Harvii…")) }
            }
        }
    }
}

extension WifiCredentialsView {
    /// Goes straight to pairing when the Wi-Fi was already sent; otherwise sends it to the
    /// device (``HardwareViewModel/sendWifiCredentials()`` opens pairing when it works and
    /// shows the error alert when it doesn't).
    func continueTapped() async {
        if wasWifiSent {
            viewModel.navigateToParingView = true
        } else {
            await viewModel.sendWifiCredentials()
        }
    }
}

/// A form field with its title above it, used for the Wi-Fi name and password.
struct LabeledInput<Content: View>: View {
    /// The field's title (also its accessibility label).
    let title: LocalizedStringKey
    /// Extra Voice Control names after the visible title ("Toque em Senha").
    var spokenAlternatives: [String] = []
    /// The field itself.
    @ViewBuilder var content: () -> Content
    
    /// Voice Control names: the visible title first, then the alternatives.
    private var inputLabelTexts: [Text] {
        var texts: [Text] = [Text(title)]
        for name in spokenAlternatives {
            texts.append(Text(verbatim: name))
        }
        return texts
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // MARK: Title
            Text(title)
                .font(.body)
                .padding(.leading, 12)
            // The field below reads this title as its own label.
                .accessibilityHidden(true)
            
            // MARK: Field in a rounded box
            content()
                .accessibilityLabel(Text(title))
            // Voice Control: the visible title first, then shorter alternatives.
                .accessibilityInputLabels(inputLabelTexts)
                .padding(.horizontal, 16)
                .frame(height: 48)
            // Gray field inside the white card.
                .background(Color(.systemGroupedBackground), in: .rect(cornerRadius: 16))
        }
        // MARK: White card around title and field
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }
}

#Preview {
    WifiCredentialsView(viewModel: HardwareViewModel())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
}
