//
//  ProfileBanner.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 08/10/26.
//

import Foundation

/// The look of a user's profile banner: a color with a texture over it, picked from the same
/// colors and textures as the rooms (``RoomColor`` and ``RoomTexturePattern``).
struct ProfileBanner: Equatable, Hashable {
    /// The banner's background color.
    var color: RoomColor
    /// The texture drawn over the color.
    var pattern: RoomTexturePattern
    
    /// The banner used when the user never picked one: orange with clouds.
    static let `default` = ProfileBanner(color: .orange, pattern: .clouds)
    
    /// Creates a banner from the values saved in CloudKit.
    ///
    /// Missing or unknown values fall back to ``default``.
    init(storedColor: String?, storedPattern: String?) {
        let color = RoomColor(storedValue: storedColor) ?? Self.default.color
        let pattern = storedPattern.flatMap(RoomTexturePattern.init(rawValue:)) ?? Self.default.pattern
        self.init(color: color, pattern: pattern)
    }
    
    /// Creates a banner. If `pattern` doesn't exist in `color`, the fallback pattern is used.
    init(color: RoomColor, pattern: RoomTexturePattern) {
        self.color = color
        self.pattern = pattern.resolved(for: color)
    }
}
