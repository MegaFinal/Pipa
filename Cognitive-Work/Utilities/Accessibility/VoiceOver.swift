//
//  VoiceOver.swift
//  Cognitive-Work
//

import SwiftUI
import UIKit

/// Small helpers shared by every screen's VoiceOver support.
enum VoiceOver {

    /// Whether VoiceOver is on right now. Use it only to change *behaviour* (for example, skipping
    /// an auto-dismiss timer); the labels themselves are always set.
    static var isRunning: Bool { UIAccessibility.isVoiceOverRunning }

    /// Speaks `message` without moving the focus, e.g. "Item comprado" after a toggle, or an error
    /// that appears outside the focused element.
    static func announce(_ message: String) {
        guard !message.isEmpty else { return }
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    /// Tells VoiceOver the screen's layout changed a lot (a popup opened, a list was replaced), so
    /// it re-reads the screen.
    static func screenChanged() {
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    /// A Brazilian-real amount written so VoiceOver reads it naturally ("55 reais e 50 centavos").
    static func currency(_ value: Double) -> String {
        value.formatted(.currency(code: "BRL").locale(L10n.locale))
    }
}

extension View {

    /// Marks a purely decorative view (textures, sparkles, divider lines) so VoiceOver skips it.
    func accessibilityDecorative() -> some View {
        accessibilityHidden(true)
    }

    /// The names Voice Control accepts for this element ("Toque em <nome>"), visible text first.
    ///
    /// A thin, non-overloaded wrapper around `accessibilityInputLabels`: that modifier has several
    /// generic overloads, and resolving them inside long view bodies made the compiler give up
    /// ("unable to type-check this expression in reasonable time"). With a concrete `[String]`
    /// parameter each call type-checks instantly.
    func voiceControlNames(_ names: [String]) -> some View {
        accessibilityInputLabels(names)
    }

    /// `accessibilityLabel` / `Value` / `Hint` with a concrete `String`. The originals are
    /// overloaded (Text, LocalizedStringKey, any StringProtocol); combined with ternaries and the
    /// two `L10n.tr` overloads that made long view bodies too slow to type-check. An empty string
    /// means "no value/hint", as with the originals.
    func voiceOverLabel(_ label: String) -> some View {
        accessibilityLabel(Text(verbatim: label))
    }

    /// `accessibilityValue` with a plain `String` (see ``voiceOverLabel(_:)``).
    func voiceOverValue(_ value: String) -> some View {
        accessibilityValue(Text(verbatim: value))
    }

    /// `accessibilityHint` with a plain `String` (see ``voiceOverLabel(_:)``).
    func voiceOverHint(_ hint: String) -> some View {
        accessibilityHint(Text(verbatim: hint))
    }

    /// Adds `traits` only while `condition` holds (e.g. `.isSelected` on the chosen option).
    /// Typed on purpose, for the same compile-time reason as ``voiceControlNames(_:)``.
    func voiceOverTraits(_ traits: AccessibilityTraits, when condition: Bool) -> some View {
        let applied: AccessibilityTraits = condition ? traits : []
        return accessibilityAddTraits(applied)
    }
}
