//
//  ChoreDurationTier.swift
//  Cognitive-Work
//
//  Created by anshu Li on 25/08/26.
//

import Foundation
import SwiftUI

/// How long a chore takes, in broad groups (quick, moderate, slow, very slow).
///
/// Used in the chore form (the user picks a group instead of typing minutes) and to draw the
/// chore's duration tag and bar.
enum ChoreDurationTier: Int, CaseIterable, Hashable {
    /// No duration was chosen yet.
    case undefined = -1
    /// Less than 20 minutes.
    case quick = 1
    /// From 20 to 59 minutes.
    case moderate = 2
    /// From 60 to 89 minutes.
    case slow = 3
    /// 90 minutes or more.
    case verySlow = 4

    /// The group a duration belongs to.
    /// - Parameter minutes: The chore's duration, in minutes.
    /// - Returns: The matching group (never ``undefined``).
    static func from(minutes: Double) -> ChoreDurationTier {
        switch minutes {
        case ..<20:
            return .quick
        case 20..<60:
            return .moderate
        case 60..<90:
            return .slow
        default:
            return .verySlow
        }
    }

    /// The duration, in minutes, a chore gets when this tier is picked in the form.
    var minutes: Double {
        switch self {
        case .undefined: return 0
        case .quick: return 15
        case .moderate: return 30
        case .slow: return 60
        case .verySlow: return 120
        }
    }

    /// Relative height of the duration bar drawn for this group (``slow`` is `1.0`).
    var heightRatio: Double {
        switch self {
        case .undefined: return 0
        case .quick: return 0.3
        case .moderate: return 0.6
        case .slow: return 1.0
        case .verySlow: return 1.5
        }
    }

    /// The group's name shown to the user, translated.
    var displayText: String {
        switch self {
        case .undefined: return L10n.tr("indefinido")
        case .quick: return L10n.tr("curta")
        case .moderate: return L10n.tr("regular")
        case .slow: return L10n.tr("longa")
        case .verySlow: return L10n.tr("extensa")
        }
    }
    
    /// The tag color of this group: blue (quick) to red (very slow).
    var color: Color {
        switch self {
        case .undefined: return .gray
        case .quick: return .tagBlue
        case .moderate: return .tagGreen
        case .slow: return .tagOrange
        case .verySlow: return .tagRed
        }
    }
}
