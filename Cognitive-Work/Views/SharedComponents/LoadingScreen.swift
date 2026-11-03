//
//  LoadingScreen.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 08/10/26.
//

import SwiftUI

/// Full-screen loading state: a hand-drawn animation over its scenery (or a soft texture).
///
/// Shows no text unless a ``message`` is given (the blocking screens use it to say what is
/// happening, e.g. "Excluindo sua casa...").
struct LoadingScreen: View {
    /// Which animation plays (see ``LoadingAnimation``).
    var animation: LoadingAnimation = .kites
    
    /// What VoiceOver reads for the whole screen.
    var accessibilityTitle: String = L10n.tr("Carregando sua casa...")
    
    /// Optional text above the animation. `nil` keeps the screen text-free.
    var message: LocalizedStringKey? = nil
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // MARK: - Message
            if let message {
                Text(message)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
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
    
    /// The scenery (or texture) and, for animations that cover the screen, the animation itself.
    private var background: some View {
        ZStack {
            Color(.systemBackground)
            
            // MARK: - Scenery or texture
            if let backgroundImageName = animation.backgroundImageName {
                filling(Image(backgroundImageName).resizable().scaledToFill())
            } else {
                Image("yellow.sparkles")
                    .resizable()
                    .opacity(0.2)
                    .frame(width: width * 1.6)
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
    LoadingScreen()
}

#Preview("Burst") {
    LoadingScreen(animation: .burst, accessibilityTitle: "Carregando")
}

#Preview("With message") {
    LoadingScreen(accessibilityTitle: "Excluindo sua casa...", message: "Excluindo sua casa...")
}
