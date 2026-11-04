//
//  PriorityTagEnum.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 12/08/26.
//

import SwiftUI

/// How urgent a chore is. Used for its tag, to sort and filter chores and to give points.
///
/// The raw value is the Portuguese name, kept stable because it is saved; show ``displayName`` instead.
enum PriorityTag: String, CaseIterable, Hashable {
    /// No priority was chosen.
    case undefined = "indefinido"
    /// Low priority.
    case low = "não urgente"
    /// Medium priority.
    case medium = "pouco urgente"
    /// Important.
    case high = "urgente"
    /// Urgent: should be done first.
    case urgent = "muito urgente"
    
    /// A number to compare priorities: `-1` (undefined) to `3` (urgent).
    var intValue: Int {
        switch self {
        case .undefined: return -1
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        case .urgent: return 3
        }
    }
    
    /// The tag color: blue (low) to red (urgent).
    var color: Color {
        switch self {
        case .undefined: return .gray
        case .low: return .tagBlue
        case .medium: return .tagGreen
        case .high: return .tagOrange
        case .urgent: return .tagRed
        }
    }
    
    /// The priority's name shown to the user, translated.
    var displayName: String {
        switch self {
        case .low: return L10n.tr("baixa")
        case .medium: return L10n.tr("média")
        case .high: return L10n.tr("importante")
        case .urgent: return L10n.tr("urgente")
        case .undefined: return L10n.tr("indefinida")
        }
    }
    
    /// Points a chore of this priority adds to its score (more urgent, more points).
    var scoreValue: Int {
        switch self {
        case .undefined: return 0
        case .low: return 5
        case .medium: return 8
        case .high: return 13
        case .urgent: return 21
        }
    }
    
    /// Whether `lhs` is *less* urgent than `rhs`. Used to sort chores by priority.
    static func isLarger (lhs: PriorityTag, rhs: PriorityTag) -> Bool {
        lhs.intValue < rhs.intValue
    }
}
