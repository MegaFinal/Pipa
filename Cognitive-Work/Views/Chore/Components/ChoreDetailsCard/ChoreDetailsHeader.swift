//
//  ChoreDetailsHeader.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 26/10/26.
//

import SwiftUI

/// Top of the details card: the room's icon, the chore's name and its tags.
struct ChoreDetailsHeader: View {
    let chore: ChoreModel
    /// Name of the icon to draw (the room's, or the chore's own).
    let symbol: String
    let tagsAccessibilityLabel: String
    
    var body: some View {
        VStack(spacing: 15) {
            SymbolImage(name: symbol)
                .frame(width: width * 0.25, height: height * 0.106)
                .accessibilityHidden(true)
            
            Text(chore.localizedName)
                .font(.custom("Alan Sans", size: 28))
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .frame(width: width * 0.7)
                .accessibilityAddTraits(.isHeader)
            
            ChoreTagsRow(chore: chore, spacing: 12, horizontalPadding: 10.0, verticalPadding: 1.5)
                .accessibilityElement(children: .ignore)
                .voiceOverLabel(tagsAccessibilityLabel)
        }
        .foregroundColor(.black)
    }
}
