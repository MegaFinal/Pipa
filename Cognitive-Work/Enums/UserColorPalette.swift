//
//  UserColorPalette.swift
//  Cognitive-Work
//
//  Created by anshu Li on 24/08/26.
//

import Foundation
import SwiftUI

/// The colors used to tell house members apart (in charts, tags and avatars).
enum UserColorPalette {
    /// The palette, in the order members receive their colors.
    private static let colors: [Color] = [.choreBlue, .choreGreen, .choreOrange, .chorePurple, .choreYellow]

    /// The color of the member at `index`.
    ///
    /// The palette repeats when there are more members than colors.
    /// - Parameter index: The member's position in the house's member list.
    /// - Returns: One of the palette's colors.
    static func color(for index: Int) -> Color {
        colors[index % colors.count]
    }
}
