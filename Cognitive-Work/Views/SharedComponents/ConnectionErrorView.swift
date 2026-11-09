//
//  ConnectionErrorView.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 09/11/26.
//

import SwiftUI

/// Full-screen notice shown when the app couldn't reach iCloud (no connection, a very slow one,
/// or no iCloud account), with a button to try again.
///
/// Used by the onboarding while it checks whether the account already has a profile and a house:
/// moving on without that answer would send a returning user to create a new profile.
struct ConnectionErrorView: View {

    /// Why it failed, already written for the user (see ``UserFacingError``).
    let message: String

    /// Called by the button.
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // MARK: - Icon, title and explanation
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.choreYellow)
                .padding(.bottom, height * 0.04)
                .accessibilityDecorative()

            Text("Não foi possível conectar")
                .font(.custom("Alan Sans", size: 32, relativeTo: .largeTitle))
                .bold()
                .foregroundStyle(.titleGray)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, height * 0.02)

            Text(verbatim: message)
                .font(.title3)
                .foregroundStyle(.subTitleGray)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            // MARK: - Retry
            Button {
                onRetry()
            } label: {
                Label("Tentar novamente", systemImage: "arrow.clockwise")
                    .frame(minWidth: width * 0.69, minHeight: height * 0.037)
                    .fontWeight(.medium)
                    .font(.system(size: 17))
            }
            .buttonStyle(.glassProminent)
            .voiceControlNames([L10n.tr("Tentar novamente"), L10n.tr("Recarregar")])
            .padding(.bottom, height * 0.05)
        }
        .padding(.horizontal, width * 0.08)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // MARK: - Sky, like the loading screen
        .background {
            ZStack {
                Color(.systemBackground)
                Color(.lowOpacityBlue.opacity(0.35))
                DriftingClouds()
            }
            .ignoresSafeArea()
            .accessibilityDecorative()
        }
    }
}

#Preview {
    ConnectionErrorView(
        message: "Sem conexão com a internet. Verifique sua rede e tente novamente."
    ) {}
}
