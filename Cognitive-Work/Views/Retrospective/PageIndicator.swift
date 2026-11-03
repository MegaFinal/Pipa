//
//  PageIndicator.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 29/09/26.
//

import SwiftUI

/// The row of dots under the retrospective's pages: one dot per page, the current one highlighted.
///
/// Tapping a dot opens that page. VoiceOver reads it as one adjustable element ("Página 2 de 4");
/// Voice Control users can say "Próxima" or "Anterior".
struct PageIndicator: View {
    /// How many pages there are.
    let count: Int
    /// The current page (0-based).
    @Binding var current: Int
    /// VoiceOver pages with the adjustable action; everyone else (Voice Control) gets
    /// the invisible "Anterior" / "Próxima" elements next to the dots.
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    var body: some View {
        HStack(spacing: 8) {
            // MARK: - Dots
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? Color.primary : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .onTapGesture { current = i }
            }
        }
        .animation(.spring(duration: 0.3), value: current)
        // MARK: - Accessibility: one adjustable element with next/previous actions
        // One adjustable element: swipe up/down to change page.
        .accessibilityElement(children: .ignore)
        .voiceOverLabel(L10n.tr("Página"))
        .voiceOverValue(L10n.tr("\(current + 1) de \(count)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                if current < count - 1 { current += 1 }
            case .decrement:
                if current > 0 { current -= 1 }
            @unknown default:
                break
            }
        }
        .voiceControlNames([L10n.tr("Página")])
        .accessibilityActions {
            Button(L10n.tr("Próxima")) { if current < count - 1 { current += 1 } }
            Button(L10n.tr("Anterior")) { if current > 0 { current -= 1 } }
        }
        // Voice Control can't use adjustable actions: "Toque em Próxima" / "Toque em Anterior".
        // MARK: - Voice Control: invisible previous/next buttons beside the dots
        .overlay(alignment: .leading) {
            if !voiceOverEnabled && current > 0 {
                DashboardVoiceControlButton(
                    labels: [L10n.tr("Anterior"), L10n.tr("Voltar")],
                    action: { current -= 1 }
                )
                .offset(x: -32)
            }
        }
        .overlay(alignment: .trailing) {
            if !voiceOverEnabled && current < count - 1 {
                DashboardVoiceControlButton(
                    labels: [L10n.tr("Próxima"), L10n.tr("Avançar")],
                    action: { current += 1 }
                )
                .offset(x: 32)
            }
        }
    }
}

/// An invisible element that only exists for Voice Control (and VoiceOver) to activate by
/// name. It draws nothing and lets touches through, so the visual design is unchanged.
struct DashboardVoiceControlButton: View {
    /// Spoken names; the first is also the accessibility label.
    let labels: [String]
    /// Runs when the element is activated.
    let action: () -> Void

    var body: some View {
        // MARK: - Invisible, touch-transparent element
        Color.clear
            .frame(width: 28, height: 28)
            .allowsHitTesting(false)
            .accessibilityElement()
            .voiceOverLabel(labels.first ?? "")
            .voiceControlNames(labels)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}


#Preview {
    @Previewable @State var current = 1
    PageIndicator(count: 4, current: $current)
}
