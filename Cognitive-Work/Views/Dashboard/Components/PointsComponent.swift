//
//  PointsComponent.swift
//  Cognitive-Work
//
//  Created by Isabela Hissa Pinto on 01/10/26.
//

import SwiftUI

/// A small gray card with a piggy bank and the user's points.
struct PointsComponent: View {
    /// The points to show.
    var points: Int
    /// The text under the points.
    var subtitle: LocalizedStringKey = "adquiridos por ter notado algo na casa"
    /// The image shown above the points.
    var piglet: String = "RetroPig"
    
    var body: some View {
        // MARK: - Piggy bank, points and subtitle
        // The card grows with its text (a longer language wraps to more lines) instead of a
        // fixed height the text spilled out of.
        VStack(spacing: 8) {
            Image(piglet)
                .resizable()
                .scaledToFit()
                .frame(width: width * 0.28, height: height * 0.08)
                .accessibilityDecorative()
            
            Text("\(points) pontos")
                .font(.system(size: 20))
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.subTitleGray)
                .fontWeight(.light)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(width: width * 0.437)
        .frame(minHeight: height * 0.21, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .foregroundStyle(Color(.systemGray6).opacity(0.5))
        )
        // "42 pontos, adquiridos por ter notado algo na casa" as one element.
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    PointsComponent(points: 42)
}
