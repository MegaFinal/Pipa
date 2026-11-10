//
//  Tier.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 13/08/26.
//

import Foundation

/// Ranks, from lowest to highest, in the order of ``allCases``. The raw value is what is stored.
///
/// The case names follow the current ranks. Each raw value is the rank's first name, which is
/// what CloudKit stores, so it must not change: records saved with it keep decoding.
///
/// Thirteen ranks form one ladder, each one starting at its ``thresholds`` entry (see the
/// extension below).
enum Tier: String, CaseIterable {
    /// "Pipa Tradicional I": the lowest rank, where every cycle starts.
    case tradicionalI = "novatoDaCasa"
    case tradicionalII = "aprendiz"
    case tradicionalIII = "ajudanteOficial"
    case deltaI = "escudeiroDaFaxina"
    case deltaII = "vigiaDaCozinha"
    case deltaIII = "sentinelaDaSala"
    case andorinhaI = "guardiaoDaCasa"
    case andorinhaII = "protetorDoLar"
    case andorinhaIII = "cavaleiroDoRodo"
    case quatorzeBisI = "mestreDaCasa"
    case quatorzeBisII = "sabioDoLar"
    case quatorzeBisIII = "lendaDaCasa"
    /// "Pipa dragão chinês": the top rank.
    case dragaoChines = "almaDaCasa"

    // MARK: - Legacy

    // Old code and records still say `.tier1`, `.tier2` or `.tier3`; these keep them compiling.
    // See ``init(stored:)``.
    static let tier1 = Tier.tradicionalI
    static let tier2 = Tier.tradicionalII
    static let tier3 = Tier.tradicionalIII

    /// Decodes a tier stored in CloudKit.
    ///
    /// Records saved before the current ranks hold "tier1"…"tier3" or one of the old 16 names
    /// ("bronze1" … "diamond3", "Master"); those land on the rank at the same relative height of
    /// the ladder. Unknown or missing values become ``tradicionalI``.
    init(stored value: String?) {
        if let value, let tier = Tier(rawValue: value) {
            self = tier
            return
        }
        let legacy = ["bronze1", "bronze2", "bronze3", "silver1", "silver2", "silver3", "gold1", "gold2",
                      "gold3", "platinum1", "platinum2", "platinum3", "diamond1", "diamond2", "diamond3", "Master"]
        switch value {
        case "tier1": self = .tier1
        case "tier2": self = .tier2
        case "tier3": self = .tier3
        default:
            guard let value, let old = legacy.firstIndex(of: value) else { self = .tradicionalI; return }
            let top = Tier.allCases.count - 1
            self = Tier.allCases[Int((Double(old) * Double(top) / Double(legacy.count - 1)).rounded())]
        }
    }

    // MARK: - Presentation

    /// Name of the rank's image in the asset catalog (`Assets.xcassets/Ranking`).
    ///
    /// The Chinese dragon doesn't have artwork in `Ranking` yet, so it keeps the old icon from
    /// `Assets.xcassets/Tiers` until its own exists.
    var imageName: String {
        switch self {
        case .tradicionalI: return "tradicional"
        case .tradicionalII: return "tradicional_II"
        case .tradicionalIII: return "tradicional_III"
        case .deltaI: return "delta_I"
        case .deltaII: return "delta_II"
        case .deltaIII: return "delta_III"
        case .andorinhaI: return "andorinha_I"
        case .andorinhaII: return "andorinha_II"
        case .andorinhaIII: return "andorinha_III"
        case .quatorzeBisI: return "14bis"
        case .quatorzeBisII: return "14biz_II"
        case .quatorzeBisIII: return "14bis_III"
        case .dragaoChines: return "Master"
        }
    }

    /// "Pipa Tradicional I", "Pipa Tradicional II", … "Pipa dragão chinês".
    var displayName: String {
        switch self {
        case .tradicionalI: return L10n.tr("Pipa Tradicional I")
        case .tradicionalII: return L10n.tr("Pipa Tradicional II")
        case .tradicionalIII: return L10n.tr("Pipa Tradicional III")
        case .deltaI: return L10n.tr("Pipa delta I")
        case .deltaII: return L10n.tr("Pipa delta II")
        case .deltaIII: return L10n.tr("Pipa delta III")
        case .andorinhaI: return L10n.tr("Pipa andorinha I")
        case .andorinhaII: return L10n.tr("Pipa andorinha II")
        case .andorinhaIII: return L10n.tr("Pipa andorinha III")
        case .quatorzeBisI: return L10n.tr("14 Bis I")
        case .quatorzeBisII: return L10n.tr("14 Bis II")
        case .quatorzeBisIII: return L10n.tr("14 Bis III")
        case .dragaoChines: return L10n.tr("Pipa dragão chinês")
        }
    }

    /// Position on the ladder, from 0 (``tradicionalI``) to 12 (``dragaoChines``).
    var position: Int { Tier.allCases.firstIndex(of: self) ?? 0 }
}

// MARK: - Progression

/// The 13 cases form one ladder, climbed with the points of the current cycle:
/// - Each rank starts at ``minimumPoints``; points above it carry over toward the next one.
/// - The steps grow as the ladder goes up (20 points to leave the first rank, 75 for the last
///   one), so the first ranks come quickly and the top ones take steady work, as in most
///   progression systems.
/// - Pipa dragão chinês, at ``topThreshold`` points, is the top of the ladder: points keep adding
///   up, the rank no longer changes.
/// - Every cycle starts over: when a cycle is settled, its rank goes to the history and the
///   points go back to 0 (see ``CycleSettlementService``).
///
/// The rank is always derived from the current points, so undoing a completed chore (which
/// removes its points) can also bring the rank back down.
extension Tier {

    /// Points at which each rank starts, in the order of ``allCases``.
    ///
    /// Calibrated on ``ScoreValues/choreCompletion(minutes:priority:)``, where a point is about a
    /// minute of chores: the top takes about 9 hours of chores in the two-week cycle (~45 minutes a
    /// day), what a member doing their fair share of a typical house (3 members, 5 rooms) gets.
    /// The curve is `650 × (rank / 12)^1.4`, rounded to 5.
    static let thresholds = [0, 20, 55, 95, 140, 190, 245, 305, 370, 435, 505, 575, 650]

    /// Points to reach the top rank.
    static var topThreshold: Int { thresholds[thresholds.count - 1] }

    /// Rank for `points`. Negative points count as zero.
    init(points: Int) {
        let points = max(points, 0)
        let step = Tier.thresholds.lastIndex { $0 <= points } ?? 0
        self = Tier.allCases[step]
    }

    /// Points at which this rank starts.
    var minimumPoints: Int { Tier.thresholds[position] }

    /// The step after this rank, or `nil` for the top one.
    var next: Tier? {
        let ladder = Tier.allCases
        return position + 1 < ladder.count ? ladder[position + 1] : nil
    }

    /// Points from the start of this rank to the next one, or `nil` for the top one.
    var divisionSize: Int? {
        next.map { $0.minimumPoints - minimumPoints }
    }

    /// Where `points` stand inside the current division.
    struct Progress: Equatable {
        /// The rank for these points.
        let tier: Tier
        /// Points earned since the current division started.
        let pointsIntoDivision: Int
        /// Points still missing for the next step, or `nil` at the top.
        let pointsToNext: Int?
        /// The rank after ``tier``, or `nil` at the top.
        let nextTier: Tier?

        /// How much of the way to the next rank is done, from 0 to 1 (1 at the top).
        var fraction: Double {
            guard let size = tier.divisionSize, size > 0 else { return 1 }
            return min(Double(pointsIntoDivision) / Double(size), 1)
        }
    }

    /// The rank of `points` and how far they are from the next rank.
    /// - Parameter points: The member's points in the current cycle. Negative values count as zero.
    /// - Returns: The rank, the points inside its division and the points missing for the next one.
    static func progress(forPoints points: Int) -> Progress {
        let points = max(points, 0)
        let tier = Tier(points: points)
        let next = tier.next
        return Progress(
            tier: tier,
            pointsIntoDivision: points - tier.minimumPoints,
            pointsToNext: next.map { $0.minimumPoints - points },
            nextTier: next
        )
    }
}

// MARK: - Coins

extension Tier {

    /// Coins a member has earned in the cycle by the time they reach this rank
    /// (``ScoreValues/coins(forPoints:)`` of ``minimumPoints``). A higher rank never pays less.
    ///
    /// Coins follow the points, not the rank: this is only the figure at the rank's start. The
    /// lowest rank starts at no coins.
    var cycleCoins: Int {
        ScoreValues.coins(forPoints: minimumPoints)
    }
}
