//
//  PendingPaymentsViewModel.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 08/10/26.
//

import Foundation
import CloudKit
import UIKit

/// Drives the "Pendências" screen: who owes whom for the things bought for the house.
@MainActor
@Observable
final class PendingPaymentsViewModel {

    /// An amount split for the big summary cards: "R$" "350" ",00".
    struct AmountParts {
        let currency: String
        let whole: String
        let cents: String
    }

    /// The shopping list's data (items and members) the debts come from.
    private let shopList: ShopListViewModel

    /// Which side of the debts is listed. The matching summary card is highlighted.
    var selectedDirection: DebtDirection = .youOwe

    /// The debt waiting for the user to confirm settling it, or `nil`.
    private(set) var settlementRequest: DebtGroup?

    /// True while a settlement is being saved.
    private(set) var isSettling = false

    /// An error to show, or `nil`.
    private(set) var errorMessage: String?

    /// See ``ShopListViewModel``: previews can't reach CloudKit.
    @ObservationIgnored
    private let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

    /// Creates the view model on top of the shopping list's data.
    init(shopList: ShopListViewModel) {
        self.shopList = shopList
    }

    // MARK: - Reading

    /// Shares settled during this visit, remembered here too so the totals drop right away and a
    /// refresh that still carries the old record can't bring a paid debt back.
    private var settledKeys: Set<String> = []

    /// Every open debt, worked out from the list (minus the ones settled in this session).
    private var ledger: DebtLedger {
        DebtCalculator.ledger(
            items: shopList.items,
            users: shopList.houseUsers,
            userRecords: shopList.houseUserRecords,
            me: shopList.currentUser,
            settledOverrides: settledKeys
        )
    }

    /// What the house owes you minus what you owe: positive when you are ahead.
    var balance: Double {
        let value = total(for: .owedToYou) - total(for: .youOwe)
        return (value * 100).rounded() / 100
    }

    /// Title of the balance card.
    var balanceTitle: String { L10n.tr("Saldo") }

    /// What the balance means: the house owes you, you owe the house, or all clear.
    var balanceCaption: String {
        if balance > 0 { return L10n.tr("A casa te deve") }
        if balance < 0 { return L10n.tr("Você deve à casa") }
        return L10n.tr("Tudo certo por aqui")
    }

    /// "+R$12,00", "-R$12,00" or "R$0,00".
    var balanceText: String {
        let sign = balance > 0 ? "+" : (balance < 0 ? "-" : "")
        return sign + currencyText(abs(balance))
    }

    /// Green when you are ahead, orange when you are behind, yellow when even.
    var balanceColor: RoomColor {
        if balance > 0 { return .green }
        if balance < 0 { return .orange }
        return .yellow
    }

    /// Debts settled a moment ago. A settled debt leaves the ledger, so its last state is kept here
    /// to keep showing the card, with a "Pago!" button, until ``markPaid(_:)`` removes it.
    private var paidGroups: [String: DebtGroup] = [:]

    /// The debts of the selected side, one group per housemate: the open ones, plus the ones just
    /// settled, in the order of the house members.
    var groups: [DebtGroup] {
        let open = ledger.groups(for: selectedDirection)
        let openIDs = Set(open.map(\.id))
        let paid = paidGroups.values.filter { $0.direction == selectedDirection && !openIDs.contains($0.id) }

        let order = shopList.houseUsers.compactMap(\.recordID)
        func position(_ group: DebtGroup) -> Int {
            group.counterparty.recordID.flatMap(order.firstIndex(of:)) ?? .max
        }
        return (open + paid).sorted { position($0) < position($1) }
    }

    /// Whether `group` was marked as paid in this session.
    func isPaid(_ group: DebtGroup) -> Bool {
        paidGroups[group.id] != nil
    }

    /// The total on one side of the debts.
    func total(for direction: DebtDirection) -> Double {
        ledger.total(for: direction)
    }

    /// The signed-in user's profile banner (color and texture), used to highlight the selected card.
    var banner: ProfileBanner {
        shopList.currentUser?.banner ?? .default
    }

    // MARK: - Texts

    /// "Você deve" or "Te devem", translated.
    func title(for direction: DebtDirection) -> String {
        switch direction {
        case .youOwe: return L10n.tr("Você deve")
        case .owedToYou: return L10n.tr("Te devem")
        }
    }

    /// Just the person's name: the selected card already says which way the money goes.
    func title(for group: DebtGroup) -> String {
        group.counterparty.name
    }

    /// Title shown when the selected side has no debts.
    var emptyTitle: String {
        switch selectedDirection {
        case .youOwe: return L10n.tr("Você não deve nada")
        case .owedToYou: return L10n.tr("Ninguém te deve")
        }
    }

    /// Message shown when there are no debts.
    var emptyMessage: String {
        L10n.tr("Quando uma compra com valor for dividida entre os moradores, ela aparece aqui.")
    }

    // MARK: - Formatting

    /// "R$55,50", in the app's language.
    /// Negative values get the sign in front: "-R$12,00".
    func currencyText(_ value: Double) -> String {
        let sign = value < 0 ? "-" : ""
        return sign + "R$" + abs(value).formatted(.number.precision(.fractionLength(2)).locale(L10n.locale))
    }

    /// The pieces of an amount for the big summary cards.
    func amountParts(_ value: Double) -> AmountParts {
        let totalCents = Int((max(value, 0) * 100).rounded())
        let separator = L10n.locale.decimalSeparator ?? ","

        return AmountParts(
            currency: "R$",
            whole: (totalCents / 100).formatted(.number.locale(L10n.locale)),
            cents: separator + String(format: "%02d", totalCents % 100)
        )
    }

    /// "Pagar" when you owe, "Recebi" when you are owed (it confirms they paid you), then "Pago!".
    func settleButtonTitle(for group: DebtGroup) -> String {
        if isPaid(group) { return L10n.tr("Pago!") }
        return group.direction == .owedToYou ? L10n.tr("Recebi") : L10n.tr("Pagar")
    }

    /// The popover's confirm button: one short word, so it never wraps.
    var confirmationButtonTitle: String {
        settlementRequest == nil ? "" : L10n.tr("Confirmar")
    }

    /// Title of the "mark as paid" confirmation.
    var confirmationTitle: String {
        guard let group = settlementRequest else { return "" }
        return L10n.tr("Marcar \(currencyText(group.total)) de \(group.counterparty.name) como pago?")
    }

    /// Message of the "mark as paid" confirmation.
    var confirmationMessage: String {
        switch settlementRequest?.direction {
        case .owedToYou: return L10n.tr("Isso marca que a pessoa já te pagou. Não dá para desfazer.")
        default: return L10n.tr("Isso marca que você já pagou. Não dá para desfazer.")
        }
    }

    // MARK: - Paying with Pix

    /// True for a moment after the Pix "copia e cola" is copied. The view shows a "copiado" toast.
    private(set) var isPixCopied = false

    /// Hides the "Pix copiado" message after a moment.
    @ObservationIgnored
    private var pixCopiedTask: Task<Void, Never>?

    /// Name of the housemate who has no Pix key yet, or `nil`. The view explains it in an alert.
    var missingPixKeyName: String?

    /// Explains that the housemate has no Pix key yet.
    var missingPixKeyMessage: String {
        L10n.tr("\(missingPixKeyName ?? "") ainda não cadastrou uma chave Pix. Peça para a pessoa cadastrar em Perfil > Chave Pix.")
    }

    /// What the "Pagar" / "Pago!" button does. When you owe, it copies the housemate's Pix
    /// "copia e cola" (amount included); when you are owed, it confirms that they paid you.
    func settleTapped(for group: DebtGroup) {
        guard !isPaid(group) else { return }

        switch group.direction {
        case .youOwe: copyPix(for: group)
        case .owedToYou: requestSettlement(of: group)
        }
    }

    /// Copies the housemate's Pix "copia e cola" code with the amount, or asks them to add a key.
    private func copyPix(for group: DebtGroup) {
        guard let key = group.counterparty.pixKey.flatMap(PixPayload.normalizedKey) else {
            missingPixKeyName = group.counterparty.name
            return
        }

        UIPasteboard.general.string = PixPayload.copyAndPaste(
            key: key,
            amount: group.total,
            receiverName: group.counterparty.name
        )
        HapticsManager.notify(.success)

        isPixCopied = true
        pixCopiedTask?.cancel()
        pixCopiedTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.isPixCopied = false
        }
    }

    // MARK: - Settling

    /// Asks the user to confirm settling `group`.
    func requestSettlement(of group: DebtGroup) {
        guard !isPaid(group) else { return }
        settlementRequest = group
    }

    /// Closes the confirmation without settling.
    func cancelSettlement() {
        settlementRequest = nil
    }

    /// Clears the error.
    func clearError() {
        errorMessage = nil
    }

    /// Settles the net debt: every share in it, both ways, is marked as paid by its own debtor.
    ///
    /// Takes the group instead of reading ``settlementRequest``: the dialog clears the request as
    /// it dismisses, which can happen before this runs.
    func settle(_ group: DebtGroup) async {
        guard !isSettling else { return }

        isSettling = true
        defer {
            isSettling = false
            settlementRequest = nil
        }

        if isPreview {
            group.entries.forEach { $0.item.settleLocally(for: $0.debtor) }
            markPaid(group)
            return
        }

        for entry in group.entries {
            guard await entry.item.markSettled(for: entry.debtor) else {
                errorMessage = CloudKitManager.shared.errorMessage ?? L10n.tr("Não foi possível quitar. Tente novamente.")
                return
            }
            settledKeys.insert(DebtCalculator.settlementKey(item: entry.item, debtor: entry.debtor))
        }
        markPaid(group)
    }

    /// How long the card says "Pago!" before it leaves the screen.
    private let paidDisplayDuration: Duration = .milliseconds(1400)

    /// Updates the totals now, keeps the card with a "Pago!" button for a moment, then removes it.
    private func markPaid(_ group: DebtGroup) {
        for entry in group.entries {
            settledKeys.insert(DebtCalculator.settlementKey(item: entry.item, debtor: entry.debtor))
        }
        paidGroups[group.id] = group

        Task { [weak self, paidDisplayDuration] in
            try? await Task.sleep(for: paidDisplayDuration)
            self?.paidGroups[group.id] = nil
        }
    }
}
