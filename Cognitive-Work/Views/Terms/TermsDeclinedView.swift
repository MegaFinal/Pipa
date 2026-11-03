//
//  TermsDeclinedView.swift
//  Cognitive-Work
//

import SwiftUI

/// Shown instead of the app when the Terms of Use were declined: a friendly goodbye in the app's
/// style, with a way to review the terms again. Rendering only.
struct TermsDeclinedView: View {

    /// The goodbye title.
    let title: String
    /// The goodbye message.
    let message: String
    /// Runs on "Rever os Termos de Uso" (shows the terms again).
    let onReviewTerms: () -> Void

    /// Drives the mascot's rocking and the sparkles' pulse.
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            // MARK: - Mascot with sparkles
            ZStack {
                Circle()
                    .fill(RoomColor.yellow.lowOpacityColor.opacity(0.3))

                Image("loadingIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 112)
                    .rotationEffect(.degrees(isAnimating ? 6 : -6))
            }
            .frame(width: 176, height: 176)
            .clipShape(Circle())
            .overlay(alignment: .topTrailing) {
                sparkle(size: 24).offset(x: 4, y: 6)
            }
            .overlay(alignment: .bottomLeading) {
                sparkle(size: 16).offset(x: 2, y: -10)
            }
            .accessibilityHidden(true)

            // MARK: - Title and message
            VStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.titleGray)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text(message)
                    .font(.system(size: 16))
                    .foregroundStyle(.subTitleGray)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            // MARK: - "Rever os Termos de Uso" button
            Button(action: onReviewTerms) {
                Text("Rever os Termos de Uso")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .voiceControlNames([L10n.tr("Rever os Termos de Uso"), L10n.tr("Rever termos"), L10n.tr("Termos")])
            .glassEffect(.regular.interactive().tint(.black), in: .capsule)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.ignoresSafeArea())
        .onAppear {
            isAnimating = true
            // Replaces the whole app: VoiceOver starts reading from the goodbye title.
            VoiceOver.screenChanged()
        }
        .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: isAnimating)
    }

    /// A sparkle that pulses with the mascot.
    private func sparkle(size: CGFloat) -> some View {
        Image(systemName: "sparkle")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(.choreYellow)
            .scaleEffect(isAnimating ? 1.15 : 0.85)
    }
}

#Preview("Recusou os termos") {
    let viewModel = TermsViewModel(defaults: UserDefaults(suiteName: "preview-terms")!)
    TermsDeclinedView(title: viewModel.farewellTitle, message: viewModel.farewellMessage, onReviewTerms: {})
}
