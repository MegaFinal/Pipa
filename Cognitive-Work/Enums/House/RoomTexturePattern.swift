//
//  RoomTexturePattern.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 28/09/26.
//

import Foundation
import UIKit

/// The texture drawn over a room's color on its cards.
enum RoomTexturePattern: String, CaseIterable {
    /// Soft cloud shapes. The only pattern that exists in every color.
    case clouds
    /// Half circles.
    case halfCircle
    /// Small sparkles.
    case sparkles
    /// Stars.
    case stars
    /// Short rounded sticks.
    case worms
    
    /// Used for rooms that aren't one of the default types (custom rooms). Must exist in every
    /// ``RoomColor``: `clouds` is the only pattern the asset catalog has for all five colors.
    static let fallback: RoomTexturePattern = .clouds
    
    /// Name of the texture image in the asset catalog for a room of `color`.
    ///
    /// Falls back to ``fallback`` when the catalog has no image of this pattern in that color,
    /// so a card never renders without a texture.
    func assetName(for color: RoomColor) -> String {
        let pattern = resolved(for: color)
        return "\(color.rawValue).\(pattern.rawValue)"
    }
    
    /// Whether the asset catalog has this pattern in `color` (not every combination exists,
    /// e.g. there is no green half circle).
    func isAvailable(for color: RoomColor) -> Bool {
        UIImage(named: "\(color.rawValue).\(rawValue)") != nil
    }
    
    /// This pattern when it exists in `color`, otherwise ``fallback``.
    func resolved(for color: RoomColor) -> RoomTexturePattern {
        isAvailable(for: color) ? self : .fallback
    }
    
    /// Name shown in the pattern picker.
    var displayName: String {
        switch self {
        case .clouds: L10n.tr("Nuvens")
        case .halfCircle: L10n.tr("Meia-lua")
        case .sparkles: L10n.tr("Brilhos")
        case .stars: L10n.tr("Estrelas")
        case .worms: L10n.tr("Bastões")
        }
    }
}

extension DefaultRoomsOnboarding {
    
    /// Pattern of this room type (the color comes from ``color``).
    var texturePattern: RoomTexturePattern {
        switch self {
        case .bedroom: .clouds
        case .homeOffice: .worms
        case .livingRoom: .stars
        case .garage: .halfCircle
        case .kitchen: .halfCircle
        case .pantry: .worms
        case .bathroom: .sparkles
        case .powderRoom: .clouds
        case .laundryRoom: .stars
        case .balcony: .worms
        case .garden: .sparkles
        }
    }
}

extension RoomModel {
    
    /// Texture for this room's cards: by room type (`kind`, or the name for rooms saved before
    /// `kind` existed), otherwise the one the user picked for a custom room, falling back to
    /// ``RoomTexturePattern/fallback``.
    var texturePattern: RoomTexturePattern {
        DefaultRoomsOnboarding(kind: kind, name: name)?.texturePattern
            ?? pattern?.resolved(for: color)
            ?? .fallback
    }
}

extension RoomDTO {
    
    /// Texture for this room's card on the selection screen.
    var texturePattern: RoomTexturePattern {
        DefaultRoomsOnboarding(rawValue: name)?.texturePattern
            ?? pattern?.resolved(for: color)
            ?? .fallback
    }
}
