//
//  PieSlice.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 29/09/26.
//

import SwiftUI

/// A filled circle that is "eaten" clockwise from the top, like a pie chart.
/// `progress` is the fraction already removed (0 = full circle, 1 = nothing left).
struct PieSlice: Shape {
    /// Fraction of the circle already removed, from `0` to `1`.
    var progress: Double

    /// Lets SwiftUI animate ``progress``.
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    /// What's left of the circle, as a pie slice.
    func path(in rect: CGRect) -> Path {
        let removed = min(max(progress, 0), 1)
        guard removed < 1 else { return Path() }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        // Nothing removed yet: draw the whole circle. A 360° arc (start == end) can come out
        // empty, which would flash the background behind it.
        guard removed > 0.0001 else {
            return Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                          width: radius * 2, height: radius * 2))
        }
        let startAngle = Angle.degrees(-90 + 360 * removed)
        let endAngle = Angle.degrees(270)

        var path = Path()
        path.move(to: center)
        path.addArc(center: center,
                    radius: radius,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    clockwise: false)
        path.closeSubpath()
        return path
    }
}

#Preview {
    PieSlice(progress: 0.35)
        .foregroundStyle(.purple)
        .frame(width: 250, height: 250)
}
