//
//  LoadingScreen.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 08/10/26.
//

import SwiftUI

/// Full-screen loading state: a hand-drawn animation over its scenery or a sky with clouds.
///
/// A ``message`` above the animation says what is loading ("Carregando sua casa...",
/// "Excluindo sua casa..."), in the same type as the onboarding titles (``OnboardingHeader``).
struct LoadingScreen: View {
    /// Which animation plays (see ``LoadingAnimation``).
    var animation: LoadingAnimation = .kites
    
    /// What VoiceOver reads for the whole screen.
    var accessibilityTitle: String = L10n.tr("Carregando sua casa...")
    
    /// What is loading, shown above the animation. `nil` keeps the screen text-free.
    var message: LocalizedStringKey? = nil
    
    var body: some View {
        VStack {
            // MARK: - Message
            if let message {
                // Same type as the onboarding titles (see ``OnboardingHeader``).
                Text(message)
                    .font(.custom("Alan Sans", size: 32, relativeTo: .largeTitle))
                    .bold()
                    .foregroundStyle(.titleGray)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, width * 0.08)
                    // Lower than the top edge, so the text sits closer to the middle of the screen.
                    .padding(.top, height * 0.13)
            }
            
            Spacer()
            
            // MARK: - Animation standing on the ground (when it doesn't fill the screen)
            if !animation.fillsScreen {
                FrameAnimationView(animation: animation)
                    .frame(width: width * 0.75)
            } else {
                Spacer()
            }
        }
        .padding(.bottom, height * animation.groundLevel)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { background }
        // The ground level is measured from the screen's real bottom, like the background.
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .voiceOverLabel(accessibilityTitle)
        .accessibilityAddTraits(.updatesFrequently)
    }
    
    /// The scenery or the sky and, for animations that cover the screen, the animation itself.
    private var background: some View {
        ZStack {
            Color(.systemBackground)
            
            // MARK: - Scenery or sky with drifting clouds
            switch animation.background {
            case .scenery(let imageName):
                filling(Image(imageName).resizable().scaledToFill())
            case .driftingClouds:
                Color(.lowOpacityBlue.opacity(0.35))
                DriftingClouds()
            }
            
            // MARK: - Full-screen animation
            if animation.fillsScreen {
                filling(FrameAnimationView(animation: animation))
            }
        }
        .accessibilityDecorative()
    }
    
    /// Fills the screen with `content`, cropping its edges instead of pushing the layout past
    /// the screen.
    private func filling(_ content: some View) -> some View {
        Color.clear
            .overlay { content }
            .clipped()
    }
}

#Preview("Kites") {
    LoadingScreen(message: "Carregando sua casa...")
}

#Preview("Burst") {
    LoadingScreen(animation: .burst, accessibilityTitle: "Retomando de onde você parou...", message: "Retomando de onde você parou...")
}

#Preview("With message") {
    LoadingScreen(accessibilityTitle: "Excluindo sua casa...", message: "Excluindo sua casa...")
}
