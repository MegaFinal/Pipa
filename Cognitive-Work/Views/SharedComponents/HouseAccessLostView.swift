//
//  HouseAccessLostView.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 05/11/26.
//

import SwiftUI

/// Full-screen notice for a member who no longer belongs to their house: the admin removed them
/// (``CloudKitManager/removeMember(ownerRecordName:from:)``) or the house was deleted.
///
/// The device can't tell the two apart (either way the house is simply gone from it), so the
/// text covers both. The button sends the user to the onboarding's "create or enter a house"
/// step; the profile and free time are kept.
struct HouseAccessLostView: View {

    /// Called by the button: leaves the main tabs for the onboarding.
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // MARK: - Icon, title and explanation
            Image(systemName: "door.left.hand.open")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.choreYellow)
                .padding(.bottom, height * 0.04)
                .accessibilityDecorative()

            Text("Você não faz mais parte desta casa")
                .font(.custom("Alan Sans", fixedSize: 32))
                .bold()
                .foregroundStyle(.titleGray)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, height * 0.02)

            Text("O administrador removeu você da casa, ou ela foi excluída. Seu perfil continua salvo: é só entrar em outra casa ou criar a sua.")
                .font(.system(size: 20))
                .foregroundStyle(.subTitleGray)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            // MARK: - Back to the onboarding
            Button {
                onContinue()
            } label: {
                Text("Entrar ou criar uma casa")
                    .frame(minWidth: width * 0.69, minHeight: height * 0.037)
                    .fontWeight(.medium)
                    .font(.system(size: 17))
            }
            .buttonStyle(.glassProminent)
            .voiceControlNames([L10n.tr("Entrar ou criar uma casa"), L10n.tr("Continuar")])
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
    HouseAccessLostView {}
}
