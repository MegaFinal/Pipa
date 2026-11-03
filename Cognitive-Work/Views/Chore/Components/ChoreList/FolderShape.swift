//
//  FolderShape.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 26/08/26.
//

import SwiftUI

/// A custom shape that draws a folder profile with a raised tab on the top-left side.
///
/// Use `FolderShape` to create UI elements that resemble a physical file folder.
struct FolderShape: Shape {
    
    /// The radius used to round the outer corners of the folder.
    var cornerRadius: CGFloat = 28
    
    /// The width of the highest part of the folder (the top-left tab).
    var tabWidth: CGFloat = 110
    
    /// The vertical depth by which the right side of the folder drops relative to the top edge of the tab.
    var topCutoutHeight: CGFloat = 48

    /// Describes this shape as a path within a rectangular frame of reference.
    ///
    /// - Parameter rect: The frame of reference for describing this shape.
    /// - Returns: A path that describes the folder shape.
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let w = rect.width
        let h = rect.height
        let r = cornerRadius
        let tabW = tabWidth
        let cutH = topCutoutHeight

        // Define the sharp corner points of our base polygon
        let topLeft = CGPoint(x: 0, y: 0)
        let topTabRight = CGPoint(x: tabW, y: 0)
        let innerCorner = CGPoint(x: tabW, y: cutH) // The inverted inner corner
        let topRight = CGPoint(x: w, y: cutH)
        let bottomRight = CGPoint(x: w, y: h)
        let bottomLeft = CGPoint(x: 0, y: h)

        // Start drawing the path below the top-left corner
        path.move(to: CGPoint(x: 0, y: r))

        // `addArc` draws the line towards the corner and rounds it using the given radius
        path.addArc(tangent1End: topLeft, tangent2End: topTabRight, radius: r)
        path.addArc(tangent1End: topTabRight, tangent2End: innerCorner, radius: r)
        
        path.addArc(tangent1End: innerCorner, tangent2End: topRight, radius: r - 8)
        
        path.addArc(tangent1End: topRight, tangent2End: bottomRight, radius: r)
        path.addArc(tangent1End: bottomRight, tangent2End: bottomLeft, radius: r)
        path.addArc(tangent1End: bottomLeft, tangent2End: topLeft, radius: r)

        path.closeSubpath()

        return path
    }
}
