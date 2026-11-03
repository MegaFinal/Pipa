//
//  EnterHarviiNetwork.swift
//  Cognitive-Work
//
//  Created by Carolina Sun on 28/10/26.
//

import SwiftUI

/// Harvii setup step 1 : leave the home Wi-Fi and join the Harvii's own network, using the
/// password shown here.
///
/// Laid out like the onboarding steps: one `VStack` with the side margin applied once, the
/// shared ``OnboardingHeader`` and the round "continue" button at the bottom.
struct EnterHarviiNetwork: View {
    
    /// Password of the Wi-Fi network the Harvii creates while it isn't configured.
    private let harviiPassword = "12345678"
    
    /// `true` for a moment after the password is copied.
    @State private var isPasswordCopied = false
    
    @Environment(\.openURL) private var openURL
    
    /// Side margin of the whole screen, the same as the onboarding steps.
    private var sideMargin: CGFloat { width * 0.0565 }
    
    var body: some View {
        NavigationStack{
            VStack(alignment: .center, spacing: 45) {
                
                OnboardingHeader(
                    title: "Entre na rede do Harvii",
                    description: "Nos ajustes do celular, saia do Wi-Fi da sua casa e escolha a rede do Harvii.",
                    containerInset: sideMargin
                )
                .padding(.bottom)
                
                WifiListExample(isHarviiNetwork: true)
                passwordCard
                
                Spacer()
                
                openConfigurationButton
                
            }
            .padding(.horizontal, sideMargin)
            .padding(.bottom, height * 0.02)
            .overlay(alignment: .bottomTrailing) {
                OnboardingProgressButton(
                    width: width * 0.15,
                    height: width * 0.15,
                    text: "chevron.right",
                    isSystemImage: true
                ) {
                    // TODO: go to the next Harvii step.
                }
                .padding(.bottom, height * 0.02)
                .padding(.trailing, width * 0.061)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
    
    // MARK: - Password
    
    /// The Harvii network password, with a button that copies it.
    private var passwordCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Senha da rede do Harvii")
                .font(.subheadline.weight(.semibold))
            
            HStack {
                Text(verbatim: harviiPassword)
                    .font(.title2.weight(.semibold))
                Spacer()
                
                Button(isPasswordCopied ? LocalizedStringKey("Copiado") : LocalizedStringKey("Copiar")) {
                    copyPassword()
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .voiceControlNames([L10n.tr("Copiar")])
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGroupedBackground), in: .rect(cornerRadius: 20))
        }
    }
    
    // MARK: openConfigurationButton
    
    /// "Abrir Ajustes" and the round "continue" button.
    private var openConfigurationButton: some View {
        
        Button {
            // iOS doesn't let apps open the Wi-Fi page directly; this opens Settings.
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        }label:{
            Text("Abrir ajustes")
                .frame(width: width * 0.45, height: height * 0.05)
            
            
        }
        .buttonStyle(.borderedProminent)
        .glassEffect()
        .tint(.black)
    }
    
    // MARK: - Actions
    
    /// Copies the password and shows "Copiado" for two seconds.
    private func copyPassword() {
        UIPasteboard.general.string = harviiPassword
        HapticsManager.notify(.success)
        VoiceOver.announce(L10n.tr("Copiado"))
        isPasswordCopied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            isPasswordCopied = false
        }
    }
}

#Preview {
    EnterHarviiNetwork()
}
