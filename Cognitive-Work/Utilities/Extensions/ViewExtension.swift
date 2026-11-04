//
//  TextFieldExtension.swift
//  Cognitive-Work
//
//  Created by Isabela Hissa Pinto on 15/09/26.
//

import SwiftUI

/// Maximum length of every free-text field in the app, in one place so layouts that display the
/// text (cards, tags, e-paper) can rely on it and never overflow.
enum TextLimits {
    /// User display name (profile, onboarding).
    static let userName = 20
    /// Chore title — the carousel card and e-paper columns are sized for this.
    static let choreName = 18
    /// Chore description.
    static let choreDescription = 250
    /// What can be typed in the chore name field when the AI fills the form from it
    /// ("lavar a louça toda semana, eu e Ana"); the AI then shortens it to ``choreName``.
    static let choreNameDescription = 120
    /// One checklist item.
    static let checklistItem = 40
    /// Room names (onboarding cards and the custom-room sheet share it).
    static let roomName = 16
    /// Shopping list item name.
    static let shopItemName = 18
    /// What can be typed in the item name field when the AI fills the form from it
    /// ("2kg de arroz 10 reais para mim"); the AI then shortens it to ``shopItemName``.
    static let shopItemDescription = 120
    /// Price text, e.g. "99999,99".
    static let price = 9
    /// IEEE 802.11 SSID maximum.
    static let wifiName = 32
    /// WPA2 passphrase maximum.
    static let wifiPassword = 63
}

/// Cuts the bound text to `limit` characters as the user types. Use ``SwiftUI/View/characterLimit(_:text:)``.
struct CharacterLimit: ViewModifier {
    /// The text being limited.
    @Binding var text: String
    /// The maximum number of characters.
    let limit: Int
    
    /// Watches the text and trims it when it gets too long.
    func body(content: Content) -> some View {
        content.onChange(of: text) { _, newValue in
            if newValue.count > limit {
                text = String(newValue.prefix(limit))
            }
        }
    }
}

extension View {
    /// Stops `text` from going over `limit` characters (see ``TextLimits``).
    /// - Parameters:
    ///   - limit: The maximum number of characters.
    ///   - text: The text field's text.
    func characterLimit(_ limit: Int, text: Binding<String>) -> some View {
        modifier(CharacterLimit(text: text, limit: limit))
    }

    /// Dismisses the keyboard when the user taps anywhere else on the screen.
    ///
    /// Uses `simultaneousGesture` (not `.onTapGesture`, which would consume the tap) so it
    /// never blocks buttons, steppers, pickers or other controls underneath — it just also
    /// resigns first responder alongside whatever else that tap does.
    func dismissKeyboardOnTap() -> some View {
        simultaneousGesture(
            TapGesture().onEnded {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )
            }
        )
    }
}

extension View {
    /// The screen's width. Layouts use it to size views in proportion to the device.
    var width: CGFloat {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return .zero
            }
        return windowScene.screen.bounds.size.width
    }
    /// The screen's height. Layouts use it to size views in proportion to the device.
    var height: CGFloat {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return .zero
            }
        return windowScene.screen.bounds.size.height
    }
}
