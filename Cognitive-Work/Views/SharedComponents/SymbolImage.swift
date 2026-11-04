//
//  SymbolImage.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 21/10/26.
//

import SwiftUI

/// An icon by name: the app's own artwork (the `ChoresSymbols` and `ShoppingListSymbols`
/// asset folders) when an asset with that name exists, otherwise the SF Symbol of that name.
///
/// Rooms and shopping categories store only a name, so rooms saved before the custom artwork
/// existed keep working with their SF Symbol. The result is already resizable and scaled to
/// fit, so give it a `.frame` and a `.foregroundStyle` (the artwork is white line art, drawn as
/// a template so it takes the foreground color like an SF Symbol).
struct SymbolImage: View {
    let name: String
    
    var body: some View {
        if UIImage(named: name) != nil {
            Image(name)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: name)
                .resizable()
                .scaledToFit()
        }
    }
}
