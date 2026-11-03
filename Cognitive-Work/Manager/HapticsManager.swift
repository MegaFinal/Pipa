//
//  HapticsManager.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 30/09/26.
//

import UIKit

/// Single entry point for haptic feedback, so the "Haptics" switch in
/// ``GeneralProfileSettingsView`` is honored everywhere, in real time.
///
/// The setting is read from `UserDefaults` on every call (the same key the settings screen binds
/// with `@AppStorage`), so flipping the switch takes effect on the very next vibration without
/// relaunching or re-rendering anything.
enum HapticsManager {

    /// `@AppStorage` key of the "Haptics" switch. Defaults to on.
    static let storageKey = "hapticsEnabled"

    /// Whether the user left haptics on in the settings.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: storageKey) as? Bool ?? true
    }

    /// A tap-like vibration (for example, when a card snaps or a button is pressed).
    /// - Parameters:
    ///   - style: How strong the tap feels.
    ///   - intensity: From `0` to `1`.
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium, intensity: CGFloat = 1.0) {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred(intensity: intensity)
    }

    /// A success, warning or error vibration.
    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    /// A light tick, used when a selection changes (pickers, sliders).
    static func selection() {
        guard isEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
