//
//  ProfileHeroShape.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 21/10/26.
//

import SwiftUI

/// A rectangle whose bottom edge dips into a smooth curve
struct ProfileHeroShape: Shape {
    var curveDepth: CGFloat = 65
    
    /// - Returns: A path that describes the profile banner outline.
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let sideY = h - curveDepth
        
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: sideY))
        
        path.addCurve(
            to: CGPoint(x: rect.midX, y: h),
            control1: CGPoint(x: w * 0.78, y: sideY),
            control2: CGPoint(x: w * 0.70, y: h)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX, y: sideY),
            control1: CGPoint(x: w * 0.30, y: h),
            control2: CGPoint(x: w * 0.22, y: sideY)
        )
        path.closeSubpath()
        return path
    }
}

#Preview {
    ProfileHeroShape()
        .fill(.orange)
        .frame(height: 280)
}
