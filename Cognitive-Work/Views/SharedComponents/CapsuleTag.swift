//
//  CapsuleTag.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 25/08/26.
//

import SwiftUI

/// A small colored pill with text, used for a chore's tags (frequency, priority, duration).
struct CapsuleTag: View {
    
    /// The text.
    var tagName: String
    
    /// The pill's color.
    var tagColor: Color
    
    /// Color of the tag's text.
    var textColor: Color = .white
    
    /// Space on the left and right of the text.
    var horizontalPadding: Double
    
    /// Space above and below the text.
    var verticalPadding: Double
    
    var body: some View {
        // MARK: - Text inside a colored capsule
        Text(tagName)
            .font(.system(size: 13))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundColor(textColor)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(tagColor)
            .clipShape(Capsule())
    }
}
