//
//  FloatingActionButton.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 16/10/26.
//

import SwiftUI

/// Round glass button that floats over the bottom-right corner of a tab root (for example, "+" to
/// add a chore). Place it with ``SwiftUI/View/floatingActionPlacement()``.
struct FloatingActionButton: View {
    /// The button's size.
    static let diameter: CGFloat = 70
    /// Distance from the right edge of the screen.
    static let trailingInset: CGFloat = 22
    /// premium badge
    var showsPremiumBadge: Bool = false
    /// SF Symbol of the icon.
    let systemImage: String
    /// The icon's size.
    var symbolSize: CGFloat = 28
    /// The icon's color.
    var foreground: Color = .white
    /// The glass tint, or `nil` for plain glass.
    var tint: Color? = .black
    /// Runs when tapped.
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // MARK: - Icon inside a glass circle
            Image(systemName: systemImage)
                .font(.system(size: symbolSize))
                .foregroundColor(foreground)
                .frame(width: Self.diameter, height: Self.diameter)
                .contentShape(Circle())
            // if its a premium feature
                .overlay(alignment: .topTrailing) {
                    if showsPremiumBadge {
                        PremiumBadge()
                            .padding(6)
                    }
                }
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive().tint(tint), in: .circle)
    }
}

extension View {
    /// Positions a ``FloatingActionButton`` at the bottom-right corner, with the standard spacing.
    func floatingActionPlacement() -> some View {
        self
            .padding(.trailing, FloatingActionButton.trailingInset)
            .padding(.bottom)
    }
}

#Preview {
    HStack {
        FloatingActionButton(systemImage: "hand.tap", symbolSize: 32, foreground: .black, tint: nil) {}
        FloatingActionButton(systemImage: "plus") {}
    }
}
