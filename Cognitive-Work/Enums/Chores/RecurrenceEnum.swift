//
//  RecurrenceEnum.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 12/08/26.
//

import SwiftUI

/// How often a chore repeats.
///
/// The raw value is the Portuguese name, kept stable because it is saved; show ``displayName`` instead.
enum Recurrence: String, CaseIterable, Hashable {
    /// No frequency was chosen.
    case undefined = "indefinida"
    /// Happens only once.
    case none = "sem recorrencia"
    /// Every day.
    case daily = "diaria"
    /// Once a week.
    case weekly = "semanal"
    /// Once every two weeks (once per cycle).
    case fortnightly = "quinzenal"
    /// Once a month (every other cycle).
    case monthly = "mensal"
    
    /// The background color of the frequency tag.
    var color: Color {
        switch self {
        case .undefined: return .gray
        case .none: return .recurrenceTagPurple
        case .daily: return .recurrenceTagRed
        case .weekly: return .recurrenceTagOrange
        case .fortnightly: return .recurrenceTagGreen
        case .monthly: return .recurrenceTagBlue
        }
    }
    
    /// The text color of the frequency tag.
    var textColor: Color {
        switch self {
        case .undefined: return .gray
        case .none: return .recurrenceTextPurple
        case .daily: return .recurrenceTextRed
        case .weekly: return .recurrenceTextOrange
        case .fortnightly: return .recurrenceTextGreen
        case .monthly: return .recurrenceTextBlue
        }
    }
    
    /// Points a chore of this frequency adds to its score (rarer chores give more points).
    var scoreValue: Int {
        switch self {
        case .undefined:
            return -1
        case .none:
            return 0
        case .daily:
            return 3
        case .weekly:
            return 5
        case .fortnightly:
            return 8
        case .monthly:
            return 13
        }
    }
    
    /// The frequency's name shown to the user, translated.
    var displayName: String {
        switch self {
        case .none: return L10n.tr("única")
        case .daily: return L10n.tr("diária")
        case .weekly: return L10n.tr("semanal")
        case .fortnightly: return L10n.tr("quinzenal")
        case .monthly: return L10n.tr("mensal")
        case .undefined: return L10n.tr("indefinida")
        }
    }

    /// How many times a chore of this frequency happens in one cycle (two weeks). Used to price
    /// coupons (see ``CouponPricing``).
    var occurrencesPerCycle: Double {
        switch self {
        case .daily: return 14
        case .weekly: return 2
        case .fortnightly, .monthly, .none, .undefined: return 1
        }
    }
}
