//
//  FreeTimeEnum.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 25/08/26.
//

/// How much free time a member has on one day of the week, in fixed steps.
///
/// The raw value is the Portuguese label, kept stable because it is saved; show ``displayName`` instead.
enum FreeTimeEnum: String{
    /// No free time that day.
    case none = ""
    /// About 30 minutes.
    case thirtyMinutes = "30 minutos"
    /// About 1 hour.
    case oneHour = "1 hora"
    /// About 2 hours.
    case twoHours = "2 horas"
    /// About 3 hours.
    case threeHours = "3 horas"
    /// About 4 hours.
    case fourHours = "4 horas"
    /// 5 hours or more.
    case fiveHours = "5 horas ou mais"
    
    /// Label shown to the user, in the app's language. (`rawValue` is kept as the stable
    /// Portuguese identifier.)
    var displayName: String {
        rawValue.isEmpty ? "" : L10n.tr(key: rawValue)
    }
    
    /// The free time in hours (for example, `0.5` for ``thirtyMinutes``).
    var timeInHours: Double {
        switch self {
        case .none:
            return 0.0
        case .thirtyMinutes:
            return 0.5
        case .oneHour:
            return 1.0
        case .twoHours:
            return 2.0
        case .threeHours:
            return 3.0
        case .fourHours:
            return 4.0
        case .fiveHours:
            return 5.0
        }
    }
    
    /// Creates the option at position `num` of the free time slider.
    /// - Parameter num: From `0` (``none``) to `6` (``fiveHours``). Other values give ``none``.
    init(_ num: Int) {
        switch num {
        case 0 :
            self = .none
        case 1 :
            self = .thirtyMinutes
        case 2 :
            self = .oneHour
        case 3 :
            self = .twoHours
        case 4 :
            self = .threeHours
        case 5 :
            self = .fourHours
        case 6 :
            self = .fiveHours
        default:
            self = .none
        }
    }
    
    /// Position of the option on the free time slider, from `0` (``none``) to `6` (``fiveHours``).
    var level: Int {
        switch self {
        case .none: return 0
        case .thirtyMinutes: return 1
        case .oneHour: return 2
        case .twoHours: return 3
        case .threeHours: return 4
        case .fourHours: return 5
        case .fiveHours: return 6
        }
    }
    
    /// Creates the smallest option that covers `minutes`.
    /// - Parameter minutes: Free time in minutes. More than 4 hours gives ``fiveHours``.
    init(minutes: Int) {
        switch minutes {
        case ..<1: self = .none
        case ...30: self = .thirtyMinutes
        case ...60: self = .oneHour
        case ...120: self = .twoHours
        case ...180: self = .threeHours
        case ...240: self = .fourHours
        default: self = .fiveHours
        }
    }
}
