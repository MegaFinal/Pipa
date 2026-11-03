//
//  OnboardingSkipButton.swift
//  Cognitive-Work
//
//  Created by Carolina Sun on 25/08/26.
//

import SwiftUI

/// The underlined "Pular esta etapa" button of the onboarding steps.
struct OnboardingSkipButton: View {
    /// The button's width; the default is 60% of the screen.
    var width: CGFloat?
    /// The button's height; the default is 6% of the screen.
    var height: CGFloat?

    /// Shows a spinner and disables the button while `true`.
    var isLoading: Bool = false
    /// Runs when tapped.
    var action: () -> Void

    // `width`/`height` shadow the View extension's properties of the same
    // name, so casting to `any View` is needed to reach the extension's
    // default (screen-based) value when no override was passed in.
    /// ``width`` or the default.
    private var resolvedWidth: CGFloat { width ?? (self as any View).width * 0.6 }
    /// ``height`` or the default.
    private var resolvedHeight: CGFloat { height ?? (self as any View).height * 0.06 }

    var body: some View {
        Button {
            action()
        } label: {
            // MARK: - Label: spinner or text
            ZStack {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text("Pular esta etapa")
                        .font(.system(size: 15, weight:.regular))
                        .underline()
                }
            }
            .frame(width: resolvedWidth, height: resolvedHeight)
            .foregroundColor(.gray)
            .fontWeight(.medium)
        }
        .disabled(isLoading)
        .accessibilityLabel(Text(L10n.tr("Pular esta etapa")))
        .voiceControlNames([L10n.tr("Pular esta etapa"), L10n.tr("Pular")])
        .voiceOverValue(isLoading ? L10n.tr("Carregando") : "")
    }
}

#Preview {
    OnboardingSkipButton(width: 300, height: 200, action: {})
}
