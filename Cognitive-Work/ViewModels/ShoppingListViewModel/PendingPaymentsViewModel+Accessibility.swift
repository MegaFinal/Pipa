//
//  PendingPaymentsViewModel+Accessibility.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 09/10/26.
//

import Foundation

/// VoiceOver texts and announcements for the "Pendências" screen. Amounts are spelled as
/// currency so they're read "45 reais" instead of "R$ 45 vírgula 00".
extension PendingPaymentsViewModel {

    /// An amount read as currency.
    func accessibilityAmount(_ value: Double) -> String {
        VoiceOver.currency(value)
    }

    /// The balance amount; the caption already says which way it goes.
    var balanceAccessibilityText: String {
        VoiceOver.currency(abs(balance))
    }

    /// "Você deve, 350 reais".
    func summaryAccessibilityLabel(for direction: DebtDirection) -> String {
        "\(title(for: direction)), \(VoiceOver.currency(total(for: direction)))"
    }

    /// "Isabela, total R$ 45,00".
    func headerAccessibilityLabel(for group: DebtGroup) -> String {
        L10n.tr("\(title(for: group)), total \(VoiceOver.currency(group.total))")
    }

    /// "Pagar R$ 45,00 para Isabela" or "Marcar que Isabela pagou".
    func settleAccessibilityLabel(for group: DebtGroup) -> String {
        switch group.direction {
        case .youOwe:
            return L10n.tr("Pagar \(VoiceOver.currency(group.total)) para \(group.counterparty.name)")
        case .owedToYou:
            return L10n.tr("Marcar que \(group.counterparty.name) pagou")
        }
    }

    /// "Pago" once settled.
    func settleAccessibilityValue(for group: DebtGroup) -> String {
        isPaid(group) ? L10n.tr("Pago") : ""
    }

    /// What the dialog's confirm button runs: settles the requested debt, then says "Pago" when it
    /// went through. The request is read right away, before the dialog dismisses itself and clears
    /// it, so the `Task` that settles still knows which debt it is for.
    func confirmSettlementAnnouncing() {
        guard let group = settlementRequest else { return }
        cancelSettlement()
        Task {
            await settle(group)
            if isPaid(group) {
                VoiceOver.announce(L10n.tr("Pago"))
            }
        }
    }
}
