//
//  PremiumFeature.swift
//  Cognitive-Work
//
//  Created by Carolina Sun on 26/10/26.
//

import SwiftUI

/// Every feature that belongs to Pipa Premium.
///
/// Premium is bought by one person but unlocks the whole house (see ``PremiumManager``). Ask
/// ``PremiumManager/allows(_:)`` before running one of these, and open ``PremiumView`` with the
/// feature highlighted when it returns `false`.

enum PremiumFeature: String, CaseIterable, Identifiable {
    /// Re-divide the chores at any moment (the free plan divides once per cycle, in the retro).
    case rebalanceDivision
    /// Everything that uses Apple Intelligence: filling a chore or a shopping item from a
    /// description (typed or spoken), checklist ideas, the suggested order of today's chores,
    /// adding several items at once, "what goes with the list" and spotting repeated chores/items.
    case intelligence
    /// The "Pendências" area: who owes whom.
    case debts
    /// Full history of past months' expenses.
    case expenseHistory
    /// Scan receipts to fill in the price of what was bought.
    case receiptScan
    /// Advanced dashboard.
    case advancedDashboard
    /// Extra Harvii screens: dashboard and shopping list.
    case harviiScreens

    var id: String { rawValue }

    /// `true` while the feature isn't built yet. The paywall shows it as "Em breve".
    var isComingSoon: Bool {
        switch self {
        case .rebalanceDivision, .intelligence, .debts:
            return false
        case .expenseHistory, .receiptScan, .advancedDashboard, .harviiScreens:
            return true
        }
    }

    /// Short name shown on the paywall.
    var title: String {
        switch self {
        case .rebalanceDivision: return L10n.tr("Divisão automática ilimitada")
        case .intelligence: return L10n.tr("Sugestões inteligentes")
        case .debts: return L10n.tr("Acompanhe suas pendências")
        case .expenseHistory: return L10n.tr("Histórico completo de gastos")
        case .receiptScan: return L10n.tr("Escanear notas fiscais")
        case .advancedDashboard: return L10n.tr("Dashboard avançado")
        case .harviiScreens: return L10n.tr("Telas extras no Harvii")
        }
    }

    /// One line explaining what the feature does.
    var subtitle: String {
        switch self {
        case .rebalanceDivision: return L10n.tr("Alguém entrou na casa ou a sua rotina mudou? Refaça a sua divisão a qualquer momento.")
        case .intelligence: return L10n.tr("Receba sugestões do que comprar e de como organizar a sua rotina, feitas com IA.")
        case .debts: return L10n.tr("Veja os detalhes das suas pendências, quem te deve e para quem você está devendo, e acerte as contas com Pix.")
        case .expenseHistory: return L10n.tr("Todos os meses da casa em um só lugar.")
        case .receiptScan: return L10n.tr("Tire uma foto e os preços são preenchidos.")
        case .advancedDashboard: return L10n.tr("Mais gráficos sobre a divisão da casa.")
        case .harviiScreens: return L10n.tr("Dashboard e lista de compras no seu Harvii.")
        }
    }

    /// SF Symbol shown next to the feature.
    var systemImage: String {
        switch self {
        case .rebalanceDivision: return "infinity"
        case .intelligence: return "sparkles"
        case .debts: return "banknote"
        case .expenseHistory: return "calendar"
        case .receiptScan: return "doc.text.viewfinder"
        case .advancedDashboard: return "chart.bar.xaxis"
        case .harviiScreens: return "rectangle.on.rectangle"
        }
    }

    /// Color of the icon on the paywall.
    var tint: Color {
        switch self {
        case .rebalanceDivision: return RoomColor.orange.uiColor
        case .intelligence: return RoomColor.purple.uiColor
        case .debts, .expenseHistory: return RoomColor.green.uiColor
        case .receiptScan, .advancedDashboard, .harviiScreens: return RoomColor.blue.uiColor
        }
    }

    /// What the paywall lists: only what already exists (App Review rejects paywalls that sell
    /// features the app doesn't have yet).
    static var paywallFeatures: [PremiumFeature] {
        allCases.filter { !$0.isComingSoon }
    }
}
