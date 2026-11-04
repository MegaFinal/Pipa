//
//  TagPickerType.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 28/08/26.
//

import SwiftUI
import CloudKit

/// The three tags a chore can have (priority, frequency and duration).
///
/// Tag views use it to know which text and colors to show for a chore.
enum TagPickerType {
    /// How urgent the chore is (``PriorityTag``).
    case priority
    /// How often the chore repeats (``Recurrence``).
    case frequency
    /// How long the chore takes (``ChoreDurationTier``).
    case duration
        
    /// The text of this tag for `chore`.
    /// - Parameters:
    ///   - chore: The chore being shown or edited.
    ///   - currentRoom: The chore's room. Not used by the current tags.
    func labelName(for chore: ChoreDTO, currentRoom: RoomModel?) -> String {
        switch self {
        case .priority:
            return chore.priorityTag.displayName
        case .frequency:
            return chore.frequency.displayName
        case .duration:
            return ChoreDurationTier.from(minutes: chore.duration).displayText
        }
    }
    
    /// Text color of the tag: recurrence tags have their own, every other tag uses white.
    func labelTextColor(for chore: ChoreDTO) -> Color {
        switch self {
        case .frequency:
            return chore.frequency.textColor
        case .priority, .duration:
            return .white
        }
    }
    
    /// The background color of this tag for `chore`.
    /// - Parameters:
    ///   - chore: The chore being shown or edited.
    ///   - currentRoom: The chore's room. Not used by the current tags.
    func labelColor(for chore: ChoreDTO, currentRoom: RoomModel?) -> Color {
        switch self {
        case .priority:
            return chore.priorityTag.color
        case .frequency:
            return chore.frequency.color
        case .duration:
            return ChoreDurationTier.from(minutes: chore.duration).color
        }
    }
}
