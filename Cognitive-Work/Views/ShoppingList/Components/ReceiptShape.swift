//
//  ReceiptShape.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 08/10/26.
//

import SwiftUI

/// A card with a half-circle bite out of each side at `notchY`, like a torn receipt. With
/// ``tornBottom`` the bottom edge is a zigzag, like the end of a thermal paper roll.
struct ReceiptShape: Shape {

    var cornerRadius: CGFloat = 22
    var notchRadius: CGFloat = 12

    /// Distance from the top edge to the center of the bites.
    var notchY: CGFloat

    var tornBottom = false
    var toothWidth: CGFloat = 16
    var toothHeight: CGFloat = 7

    /// Lets SwiftUI animate ``notchY``.
    var animatableData: CGFloat {
        get { notchY }
        set { notchY = newValue }
    }

    /// The card's outline with the bites (and the zigzag) cut out.
    func path(in rect: CGRect) -> Path {
        let card: Path
        if tornBottom {
            card = UnevenRoundedRectangle(
                topLeadingRadius: cornerRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: cornerRadius,
                style: .continuous
            ).path(in: rect)
        } else {
            card = Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
        }

        let y = rect.minY + notchY
        var cuts = Path()
        for x in [rect.minX, rect.maxX] {
            cuts.addEllipse(in: CGRect(
                x: x - notchRadius,
                y: y - notchRadius,
                width: notchRadius * 2,
                height: notchRadius * 2
            ))
        }

        if tornBottom {
            let count = max(1, Int((rect.width / toothWidth).rounded()))
            let width = rect.width / CGFloat(count)
            for index in 0..<count {
                let x = rect.minX + CGFloat(index) * width
                cuts.move(to: CGPoint(x: x, y: rect.maxY + 1))
                cuts.addLine(to: CGPoint(x: x + width / 2, y: rect.maxY - toothHeight))
                cuts.addLine(to: CGPoint(x: x + width, y: rect.maxY + 1))
                cuts.closeSubpath()
            }
        }

        return card.subtracting(cuts)
    }
}

/// A rounded card with a bite out of each side at a fraction of its height, like a coupon.
struct TicketShape: Shape {

    /// How round the card's corners are.
    var cornerRadius: CGFloat = 22
    /// Size of each side bite.
    var notchRadius: CGFloat = 9
    /// Where the bites are, from 0 (top) to 1 (bottom).
    var notchFraction: CGFloat = 0.5

    func path(in rect: CGRect) -> Path {
        ReceiptShape(
            cornerRadius: cornerRadius,
            notchRadius: notchRadius,
            notchY: rect.height * notchFraction
        ).path(in: rect)
    }
}
