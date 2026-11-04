//
//  PriceInputModifier.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 09/10/26.
//

import SwiftUI

extension View {

    /// Makes a text field take a price the way banking apps do: a number pad with digits only,
    /// filling in from the cents ("1", "5", "0" → "1,50"), so nobody types the comma.
    func priceInput(text: Binding<String>) -> some View {
        modifier(PriceInputModifier(text: text))
    }
}

/// Keeps a text field's text formatted as a price while the user types. See ``SwiftUI/View/priceInput(text:)``.
private struct PriceInputModifier: ViewModifier {

    /// The field's text.
    @Binding var text: String

    /// Number pad, and reformats the text on every change.
    func body(content: Content) -> some View {
        content
            .keyboardType(.numberPad)
            .onChange(of: text) { _, newValue in
                let formatted = ShopListViewModel.formatPriceInput(newValue)
                if formatted != newValue { text = formatted }
            }
    }
}
