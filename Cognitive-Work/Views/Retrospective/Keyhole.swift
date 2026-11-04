//
//  Keyhole.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 29/09/26.
//

import SwiftUI

/// The keyhole shape drawn on the percentage page of the retrospective: a circle on top of a
/// trapezoid that widens towards the bottom.
struct Keyhole: Shape {
    /// The keyhole's outline, scaled to fill `rect`.
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height

        let center = CGPoint(x: rect.minX + w * 0.5013, y: rect.minY + h * 0.2562)
        let radius = w * 0.4734

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + w * 0.2944, y: rect.minY + h * 0.4876))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.7132, y: rect.minY + h * 0.4876))
        path.addArc(center: center,
                    radius: radius,
                    startAngle: .degrees(63.6),
                    endAngle: .degrees(115.8),
                    clockwise: true)
        path.closeSubpath()
        return path
    }
}


#Preview {
    Keyhole()
        .frame(width: 200, height: 300)
        .foregroundStyle(.purple)
}
