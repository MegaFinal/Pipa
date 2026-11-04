//
//  Tier.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 13/08/26.
//

import Foundation

/// Ranks, from lowest to highest, in the order of ``allCases``. The raw value is what is stored.
///
/// The case names are the ranks' first names and stay as they are: they are the values saved in
/// CloudKit. Only ``displayName`` (what the user sees) follows the current names.
///
/// Thirteen ranks form one ladder, each one ``pointsPerDivision`` points above the one before
/// (see the extension below).
enum Tier: String, CaseIterable {
    /// "Pipa Tradicional I": the lowest rank, where every cycle starts.
    case novatoDaCasa
    case aprendiz
    case ajudanteOficial
    case escudeiroDaFaxina
    case vigiaDaCozinha
    case sentinelaDaSala
    case guardiaoDaCasa
    case protetorDoLar
    case cavaleiroDoRodo
    case mestreDaCasa
    case sabioDoLar
    case lendaDaCasa
    /// "Pipa dragão chinês": the top rank.
    case almaDaCasa

    // MARK: - Legacy

    // Old code and records still say `.tier1`, `.tier2` or `.tier3`; these keep them compiling.
    // See ``init(stored:)``.
    static let tier1 = Tier.novatoDaCasa
    static let tier2 = Tier.aprendiz
    static let tier3 = Tier.ajudanteOficial

    /// Decodes a tier stored in CloudKit.
    ///
    /// Records saved before the current ranks hold "tier1"…"tier3" or one of the old 16 names
    /// ("bronze1" … "diamond3", "Master"); those land on the rank at the same relative height of
    /// the ladder. Unknown or missing values become ``novatoDaCasa``.
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
            guard let value, let old = legacy.firstIndex(of: value) else { self = .novatoDaCasa; return }
            let top = Tier.allCases.count - 1
            self = Tier.allCases[Int((Double(old) * Double(top) / Double(legacy.count - 1)).rounded())]
        }
    }

    // MARK: - Presentation

    /// Name of the rank's image in the asset catalog (`Assets.xcassets/Tiers`).
    ///
    /// The catalog still holds the 16 old rank icons, so each rank borrows the one at the same
    /// relative height of the ladder until icons for the new ranks exist.
    var imageName: String {
        let icons = ["bronze1", "bronze2", "bronze3", "silver1", "silver2", "silver3", "gold1", "gold2",
                     "gold3", "platinum1", "platinum2", "platinum3", "diamond1", "diamond2", "diamond3", "Master"]
        let index = Tier.allCases.firstIndex(of: self) ?? 0
        let top = Tier.allCases.count - 1
        return icons[Int((Double(index) * Double(icons.count - 1) / Double(top)).rounded())]
    }

    /// "Pipa Tradicional I", "Pipa Tradicional II", … "Pipa dragão chinês".
    var displayName: String {
        switch self {
        case .novatoDaCasa: return L10n.tr("Pipa Tradicional I")
        case .aprendiz: return L10n.tr("Pipa Tradicional II")
        case .ajudanteOficial: return L10n.tr("Pipa Tradicional III")
        case .escudeiroDaFaxina: return L10n.tr("Pipa delta I")
        case .vigiaDaCozinha: return L10n.tr("Pipa delta II")
        case .sentinelaDaSala: return L10n.tr("Pipa delta III")
        case .guardiaoDaCasa: return L10n.tr("Pipa andorinha I")
        case .protetorDoLar: return L10n.tr("Pipa andorinha II")
        case .cavaleiroDoRodo: return L10n.tr("Pipa andorinha III")
        case .mestreDaCasa: return L10n.tr("14 Bis I")
        case .sabioDoLar: return L10n.tr("14 Bis II")
        case .lendaDaCasa: return L10n.tr("14 Bis III")
        case .almaDaCasa: return L10n.tr("Pipa dragão chinês")
        }
    }

    /// Position on the ladder, from 0 (``novatoDaCasa``) to 12 (``almaDaCasa``).
    var position: Int { Tier.allCases.firstIndex(of: self) ?? 0 }
}

// MARK: - Progression

/// The 13 cases form one ladder. Every step costs ``pointsPerDivision`` points:
/// - Reaching the threshold moves to the next rank (Pipa Tradicional I → Pipa Tradicional II); points above a
///   threshold carry over.
/// - Pipa dragão chinês is reached at `12 × pointsPerDivision` points and is the top of the ladder:
///   points keep adding up, the rank no longer changes.
/// - Every cycle starts over: when a cycle is settled, its rank goes to the history and the
///   points go back to 0 (see ``CycleSettlementService``).
///
/// The rank is always derived from the current points, so undoing a completed chore (which
/// removes its points) can also bring the rank back down.
extension Tier {

    /// Points needed to climb one rank.
    ///
    /// Calibrated for a two-week cycle: a member who does their fair share of a typical house
    /// (3 members) earns about 55 points a day, so they get close to the top only after about
    /// 10 days, and someone who does half of it ends the cycle mid-ladder.
    static let pointsPerDivision = 50

    /// Rank for `points`. Negative points count as zero.
    init(points: Int) {
        let ladder = Tier.allCases
        let step = max(points, 0) / Tier.pointsPerDivision
        self = ladder[min(step, ladder.count - 1)]
    }

    private var step: Int { position }

    /// Points at which this rank starts.
    var minimumPoints: Int { step * Tier.pointsPerDivision }

    /// The step after this rank, or `nil` for the top one.
    var next: Tier? {
        let ladder = Tier.allCases
        return step + 1 < ladder.count ? ladder[step + 1] : nil
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

    /// Coins paid at the end of each cycle to someone at this rank. A higher rank never pays
    /// less than a lower one.
    var cycleCoins: Int {
        let coins = [10, 12, 15, 18, 22, 26, 31, 37, 44, 52, 62, 74, 90]
        return coins[position]
    }
}
