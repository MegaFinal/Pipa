//
//  RoomColorEnum.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 12/08/26.
//

import SwiftUI

/// The colors a room can have. Chores, cards and tags of a room use its color.
///
/// The raw value is the name saved in CloudKit.
enum RoomColor: String, CaseIterable, Identifiable {
    case purple = "purple"
    case orange = "orange"
    case yellow = "yellow"
    case green = "green"
    case blue = "blue"
    
    /// Identifier for SwiftUI lists (the raw value).
    var id: String { self.rawValue }
    
    /// The palette color for this case (see the asset catalog's `Colors` group).
    var uiColor: Color {
        switch self {
        case .purple: return .chorePurple
        case .orange: return .choreOrange
        case .yellow: return .choreYellow
        case .green: return .choreGreen
        case .blue: return .choreBlue
        }
    }
    
    /// The soft counterpart of ``uiColor`` (asset catalog `Colors/LowOpacity`), used on cards that
    /// sit behind or beside the main content, like the chart's chore card and the progress cards.
    var lowOpacityColor: Color {
        switch self {
        case .purple: return .lowOpacityPurple
        case .orange: return .lowOpacityOrange
        case .yellow: return .lowOpacityYellow
        case .green: return .lowOpacityGreen
        case .blue: return .lowOpacityBlue
        }
    }
    
    /// The background of the progress cards on the chores screen: the soft ``lowOpacityColor``,
    /// except for yellow, which uses the full `choreYellow` (the soft yellow looks washed out there).
    var progressCardColor: Color {
        self == .yellow ? .choreYellow : lowOpacityColor
    }
    
    /// Decodes a color stored in CloudKit, including values from palettes that no longer exist.
    ///
    /// Rooms saved by older builds may hold `"red"`, `"white"` or `"pink"`. Failing on those made
    /// ``RoomModel/init(record:)`` return `nil`, which dropped the whole room — and every chore
    /// pointing at it rendered as an unknown (gray) room. Legacy values are now mapped to the
    /// closest current color.
    init?(storedValue: String?) {
        guard let storedValue else { return nil }
        
        if let current = RoomColor(rawValue: storedValue) {
            self = current
            return
        }
        
        switch storedValue {
        case "pink", "red": self = .purple
        case "white": self = .blue
        default: return nil
        }
    }
}
