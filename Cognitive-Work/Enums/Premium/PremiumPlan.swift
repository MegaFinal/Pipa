//
//  PremiumPlan.swift
//  Cognitive-Work
//
//  Created by Carolina Sun on 26/10/26.
//

import Foundation

/// Price bracket by number of residents. A bigger house pays more for the house, but less
/// per person.
///
/// | Faixa         | Mensal   | Anual     | Anual Estudante |
/// |---------------|-----------|--------------|-----------------|
/// | Até 3                |   R$ 12,90 |    R$ 99,90    |      R$ 69,90        |
/// | 4 a 6                |  R$ 16,90  |    R$ 129,90   |      R$ 90,90        |
/// | 7 ou mais        |  R$ 21,90  |    R$ 169,90   |      R$ 118,90       |
///
/// The prices themselves live in App Store Connect (and `Premium.storekit` for testing); the
/// app only picks which products to show.
enum HouseSizeTier: String, CaseIterable, Comparable {
    case small
    case medium
    case large

    /// The bracket a house with `memberCount` residents belongs to.
    init(memberCount: Int) {
        switch memberCount {
        case ...3: self = .small
        case 4...6: self = .medium
        default: self = .large
        }
    }

    /// Shown on the paywall, e.g. "Até 3 moradores".
    var title: String {
        switch self {
        case .small: return L10n.tr("Até 3 moradores")
        case .medium: return L10n.tr("4 a 6 moradores")
        case .large: return L10n.tr("7 ou mais moradores")
        }
    }

    /// Product IDs of this bracket's subscriptions.
    func productIDs(includingStudent: Bool) -> [String] {
        let all = PremiumPlan.allSubscriptions.filter { $0.tier == self }
        return all
            .filter { includingStudent || !$0.isStudent }
            .map(\.productID)
    }

    private var order: Int {
        switch self {
        case .small: return 0
        case .medium: return 1
        case .large: return 2
        }
    }

    static func < (lhs: HouseSizeTier, rhs: HouseSizeTier) -> Bool {
        lhs.order < rhs.order
    }
}

/// One product of Pipa Premium.
///
/// All subscriptions are in the **same subscription group**, so a person can only have one at a
/// time and moving between brackets is an upgrade/downgrade the App Store handles (with
/// proration). In the group, `large` is level 1 (highest), `medium` level 2, `small` level 3.
struct PremiumPlan: Hashable {

    enum Period { case monthly, yearly, lifetime }

    let productID: String
    /// `nil` for lifetime: it covers any house size.
    let tier: HouseSizeTier?
    let period: Period
    let isStudent: Bool

    var isLifetime: Bool { period == .lifetime }

    private static let prefix = "JonasMelo.CognitiveWork.premium"

    /// "Vitalício (por conta)": a non-consumable bought once.
    static let lifetime = PremiumPlan(
        productID: "\(prefix).lifetime", tier: nil, period: .lifetime, isStudent: false
    )

    /// The 9 subscriptions: 3 brackets × (monthly, yearly, student yearly).
    static let allSubscriptions: [PremiumPlan] = HouseSizeTier.allCases.flatMap { tier in
        [
            PremiumPlan(productID: "\(prefix).\(tier.rawValue).monthly", tier: tier, period: .monthly, isStudent: false),
            PremiumPlan(productID: "\(prefix).\(tier.rawValue).yearly", tier: tier, period: .yearly, isStudent: false),
            PremiumPlan(productID: "\(prefix).\(tier.rawValue).student.yearly", tier: tier, period: .yearly, isStudent: true),
        ]
    }

    /// Every product the app sells.
    static let all: [PremiumPlan] = allSubscriptions + [lifetime]

    /// Every product ID the app sells.
    static let allProductIDs: Set<String> = Set(all.map(\.productID))

    /// The plan with this product ID, or `nil` if it isn't ours.
    init?(productID: String) {
        guard let plan = Self.all.first(where: { $0.productID == productID }) else { return nil }
        self = plan
    }

    private init(productID: String, tier: HouseSizeTier?, period: Period, isStudent: Bool) {
        self.productID = productID
        self.tier = tier
        self.period = period
        self.isStudent = isStudent
    }

    /// Whether this plan pays for a house of `tier`. Lifetime covers every size.
    func covers(_ required: HouseSizeTier) -> Bool {
        guard let tier else { return true }
        return tier >= required
    }
}
