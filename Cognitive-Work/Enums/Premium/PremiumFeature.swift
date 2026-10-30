//
//  PremiumFeature.swift
//  Cognitive-Work
//
//  Created by Carolina Sun on 26/10/26.
//

import Foundation

/// Every feature that belongs to Pipa Premium.
///
/// Premium is bought by one person but unlocks the whole house (see ``PremiumManager``). Ask
/// ``PremiumManager/allows(_:)`` before running one of these, and open ``PremiumView`` with the
/// feature highlighted when it returns `false`.

enum PremiumFeature: String, CaseIterable, Identifiable {
    /// Re-divide the chores at any moment (the free plan divides once per cycle, in the retro).
    case rebalanceDivision
    /// Apple Intelligence on the shopping list: add items from text or voice, fill in an item, suggest what goes with the list and spot duplicates.
    case shopAI
    /// The "Pendências" area: who owes whom.
    case debts
    /// Full history of past months' expenses.
    case expenseHistory
    /// Scan receipts to fill in the price of what was bought.
    case receiptScan
    /// Create chores and suggest their order with AI.
    case choreAI
    /// Advanced dashboard.
    case advancedDashboard
    /// Extra Harvii screens: dashboard and shopping list.
    case harviiScreens

    var id: String { rawValue }

    /// `true` while the feature isn't built yet. The paywall shows it as "Em breve".
    var isComingSoon: Bool {
        switch self {
        case .rebalanceDivision, .shopAI, .debts:
            return false
        case .expenseHistory, .receiptScan, .choreAI, .advancedDashboard, .harviiScreens:
            return true
        }
    }

    /// Short name shown on the paywall.
    var title: String {
        switch self {
        case .rebalanceDivision: return L10n.tr("Rebalancear a divisão quando quiser")
        case .shopAI: return L10n.tr("IA na lista de compras")
        case .debts: return L10n.tr("Quem deve para quem")
        case .expenseHistory: return L10n.tr("Histórico completo de gastos")
        case .receiptScan: return L10n.tr("Escanear notas fiscais")
        case .choreAI: return L10n.tr("Criar tarefas com IA")
        case .advancedDashboard: return L10n.tr("Dashboard avançado")
        case .harviiScreens: return L10n.tr("Telas extras no Harvii")
        }
    }

    /// One line explaining what the feature does.
    var subtitle: String {
        switch self {
        case .rebalanceDivision: return L10n.tr("Entrou alguém novo ou a rotina mudou? Refaça a divisão na hora.")
        case .shopAI: return L10n.tr("Adicione vários itens de uma vez e receba sugestões do que está faltando.")
        case .debts: return L10n.tr("Veja os detalhes das pendências e acerte as contas com Pix.")
        case .expenseHistory: return L10n.tr("Todos os meses da casa em um só lugar.")
        case .receiptScan: return L10n.tr("Tire uma foto e os preços são preenchidos.")
        case .choreAI: return L10n.tr("Descreva o que precisa ser feito e a IA monta as tarefas e a ordem.")
        case .advancedDashboard: return L10n.tr("Mais gráficos sobre a divisão da casa.")
        case .harviiScreens: return L10n.tr("Dashboard e lista de compras no seu Harvii.")
        }
    }

    /// SF Symbol shown next to the feature.
    var systemImage: String {
        switch self {
        case .rebalanceDivision: return "arrow.triangle.2.circlepath"
        case .shopAI: return "sparkles"
        case .debts: return "banknote"
        case .expenseHistory: return "calendar"
        case .receiptScan: return "doc.text.viewfinder"
        case .choreAI: return "wand.and.stars"
        case .advancedDashboard: return "chart.bar.xaxis"
        case .harviiScreens: return "rectangle.on.rectangle"
        }
    }
}
