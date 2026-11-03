//
//  onboardingProgressButton.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 19/08/26.
//

import SwiftUI

/// A primary action button that can display a loading spinner
///
/// While ``isLoading`` is `true`, the button shows a `ProgressView` instead of
/// ``text`` and disables itself, preventing duplicate taps during an in-flight
/// asynchronous action (e.g. a CloudKit save).
///
/// Used throughout the onboarding flow as the primary "continue" action
struct OnboardingProgressButton: View {
    /// The button's width; the default is 60% of the screen.
    var width: CGFloat?
    /// The button's height; the default is 6% of the screen.
    var height: CGFloat?

    /// The button's text (a localization key), or an SF Symbol name when ``isSystemImage`` is `true`.
    var text: String
    /// Whether ``text`` is an SF Symbol name.
    var isSystemImage: Bool = false

    /// Shows a spinner and disables the button while `true`.
    var isLoading: Bool = false
    /// Grays out and disables the button while `true`.
    var isDisabled: Bool = false
    /// Runs when tapped.
    var action: () async -> Void

    // `width`/`height` shadow the View extension's properties of the same
    // name, so casting to `any View` is needed to reach the extension's
    // default (screen-based) value when no override was passed in.
    /// ``width`` or the default.
    private var resolvedWidth: CGFloat { width ?? (self as any View).width * 0.6 }
    /// ``height`` or the default.
    private var resolvedHeight: CGFloat { height ?? (self as any View).height * 0.06 }

    /// What VoiceOver reads: icon-only buttons get a word for their symbol.
    private var accessibilityText: String {
        guard isSystemImage else { return L10n.tr(key: text) }
        switch text {
        case "checkmark": return L10n.tr("Salvar")
        default: return L10n.tr("Continuar")
        }
    }

    /// Voice Control names: the visible text first; icon-only buttons get short words to say.
    private var inputLabels: [String] {
        guard isSystemImage else { return [L10n.tr(key: text)] }
        switch text {
        case "checkmark": return [L10n.tr("Confirmar"), L10n.tr("Salvar"), L10n.tr("OK")]
        default: return [L10n.tr("Continuar"), L10n.tr("Próximo"), L10n.tr("Avançar")]
        }
    }

    var body: some View {
        Button {
            Task {
                await action()
            }
        } label: {
            // MARK: - Label: spinner, icon or text
            ZStack {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    if isSystemImage {
                        Image(systemName: text)
                            .font(.system(size: resolvedHeight * 0.4))
                    } else {
                        Text(LocalizedStringKey(text))
                    }
                }
            }
            .frame(width: resolvedWidth, height: resolvedHeight)
            .foregroundColor(.white)
            .fontWeight(.medium)
            // MARK: - Blue (or gray) glass capsule
            .background(
                Capsule()
                    .foregroundColor(isDisabled ? .gray : .blue)
                    .glassEffect()
            )
        }
        .disabled(isLoading || isDisabled)
        .accessibilityLabel(Text(accessibilityText))
        .voiceControlNames(inputLabels)
        .voiceOverValue(isLoading ? L10n.tr("Carregando") : "")
    }
}

#Preview {
    OnboardingProgressButton( text: "Continuar", action: {})
}
