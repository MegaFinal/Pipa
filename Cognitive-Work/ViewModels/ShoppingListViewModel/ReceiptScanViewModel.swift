//
//  ReceiptScanViewModel.swift
//  Cognitive-Work
//
//  Created by anshu Li on 04/11/26.
//

import Foundation
import UIKit

/// Reads a scanned receipt, pairs its products with the shopping list, and holds what the
/// review screen shows and edits. Nothing reaches the list until the person confirms
/// (``confirm(into:)``).
@MainActor
@Observable
final class ReceiptScanViewModel {

    /// Where the screen is.
    enum Phase {
        /// The photos are being read.
        case reading
        /// Products were found and can be reviewed.
        case review
        /// No product was found (a blurry photo, or not a receipt with products).
        case empty
    }

    /// Whether the products' sum matches the receipt.
    enum TotalCheck: Equatable {
        /// It matches one of the printed totals (1% or 5 centavos).
        case matches(Double)
        /// It doesn't; the closest printed total and the difference (sum − total).
        case differs(total: Double, difference: Double)
        /// No total was read from the receipt.
        case noPrintedTotal
    }

    private(set) var phase: Phase = .reading
    /// The products, as the person edits them.
    var lines: [ReceiptScanLine] = []
    /// The price fields' text, by line (bank-style entry, see ``ShopListViewModel/formatPriceInput(_:)``).
    var priceTexts: [UUID: String] = [:]

    private var printedTotals: [Double] = []
    private var printedItemCount: Int?
    /// Item numbers the reader lost (see ``ReceiptScanResult/missingItemNumbers``).
    private(set) var missingItemNumbers: [Int] = []
    /// Whether the products came from the photo reading with Apple Intelligence.
    private(set) var readFromPhoto = false

    // MARK: - Going to the list

    /// The list items a line can be linked to (see ``ShopListViewModel/receiptLinkableItems``).
    private(set) var linkableItems: [ShopListItem] = []
    /// Lines that go to the list when confirmed (all of them at first; the checkbox in front of
    /// each line takes it out).
    private(set) var included: Set<UUID> = []
    /// The list item (by ``ShopListItem/id``) a line checks off. A line without one is added as
    /// a new item. Only names that clearly match are paired: many products on a receipt were
    /// never on the list.
    private(set) var links: [UUID: String] = [:]
    /// The house members, to choose who a product bought outside the list is for.
    private(set) var houseUsers: [UserModel] = []
    /// Who each line outside the list is for, by ``UserModel/id``. A line without an entry is
    /// for the whole house (the default, like the AI items).
    private(set) var consumerIDs: [UUID: Set<String>] = [:]
    /// Whether the confirmed receipt is being saved.
    private(set) var isApplying = false

    // MARK: - Reading

    /// The name each line had when read, to tell which ones the person renamed.
    private var readNames: [UUID: String] = [:]

    /// Reads the photos of one receipt and pairs the products with `items` by their names.
    /// Names are spelled out (``ReceiptAbbreviations``) or, for products the house scanned
    /// before, replaced by what it called them (`memory`, see ``ReceiptNameMemory``).
    ///
    /// - Parameter houseUsers: Who a product bought outside the list can be for.
    func read(
        _ pages: [UIImage],
        linking items: [ShopListItem],
        houseUsers: [UserModel],
        memory: [String: String] = [:]
    ) async {
        phase = .reading
        let result = await ReceiptScanService.read(pages)
        lines = result.lines.map { line in
            var line = line
            line.receiptName = line.name
            line.name = ReceiptNameMemory.name(for: line, in: memory) ?? ReceiptAbbreviations.expand(line.name)
            return line
        }
        readNames = Dictionary(uniqueKeysWithValues: lines.map { ($0.id, $0.name) })
        priceTexts = Dictionary(uniqueKeysWithValues: lines.map { ($0.id, Self.priceText(for: $0.total)) })
        printedTotals = result.printedTotals
        printedItemCount = result.printedItemCount
        missingItemNumbers = result.missingItemNumbers
        readFromPhoto = result.readFromPhoto

        linkableItems = items
        self.houseUsers = houseUsers
        included = Set(lines.map(\.id))
        links = [:]
        consumerIDs = [:]
        let pairs = ReceiptItemMatcher.match(receiptNames: lines.map(\.name), listNames: items.map(\.name))
        for (itemIndex, lineIndex) in pairs {
            links[lines[lineIndex].id] = items[itemIndex].id
        }

        phase = lines.isEmpty ? .empty : .review
    }

    // MARK: - Editing

    /// Applies a typed price to its line.
    func updatePrice(_ text: String, for line: ReceiptScanLine) {
        priceTexts[line.id] = text
        guard let index = lines.firstIndex(where: { $0.id == line.id }) else { return }
        lines[index].total = ShopListViewModel.parsePrice(text) ?? 0
        // Once the person typed the value, it's theirs: no more warning.
        lines[index].warning = nil
    }

    /// Whether `line` goes to the list.
    func isIncluded(_ line: ReceiptScanLine) -> Bool {
        included.contains(line.id)
    }

    /// Puts `line` in or takes it out.
    func toggle(_ line: ReceiptScanLine) {
        if included.contains(line.id) {
            included.remove(line.id)
        } else {
            included.insert(line.id)
        }
    }

    /// The list item `line` checks off, or `nil` when it's added as a new item.
    func linkedItem(for line: ReceiptScanLine) -> ShopListItem? {
        links[line.id].flatMap { id in linkableItems.first { $0.id == id } }
    }

    /// Links `line` to a list item (by id), or to none (`nil`: a new item).
    func link(_ line: ReceiptScanLine, to itemID: String?) {
        links[line.id] = itemID
        included.insert(line.id)
    }

    // MARK: - Sections

    /// Lines that check off a list item, shown first.
    var listLines: [ReceiptScanLine] {
        lines.filter { links[$0.id] != nil }
    }

    /// Lines bought outside the list, shown below and added as new items.
    var otherLines: [ReceiptScanLine] {
        lines.filter { links[$0.id] == nil }
    }

    // MARK: - Who it's for

    /// Who `line` is for: the whole house unless the person chose.
    func consumers(for line: ReceiptScanLine) -> [UserModel] {
        guard let ids = consumerIDs[line.id] else { return houseUsers }
        return houseUsers.filter { ids.contains($0.id) }
    }

    /// Whether `line` is for the whole house.
    func isForEveryone(_ line: ReceiptScanLine) -> Bool {
        consumers(for: line).count == houseUsers.count
    }

    /// Adds `user` to who `line` is for, or takes them out (someone always stays).
    func toggleConsumer(_ user: UserModel, for line: ReceiptScanLine) {
        var ids = consumerIDs[line.id] ?? Set(houseUsers.map(\.id))
        if ids.contains(user.id) {
            guard ids.count > 1 else { return }
            ids.remove(user.id)
        } else {
            ids.insert(user.id)
        }
        consumerIDs[line.id] = ids
    }

    /// Makes `line` for `users` (`nil`: the whole house).
    func setConsumers(_ users: [UserModel]?, for line: ReceiptScanLine) {
        consumerIDs[line.id] = users.map { Set($0.map(\.id)) }
    }

    /// Makes every line outside the list for `users` (`nil`: the whole house).
    func setConsumersForOtherLines(_ users: [UserModel]?) {
        for line in otherLines {
            setConsumers(users, for: line)
        }
    }

    // MARK: - Confirming

    /// Whether there is something to confirm, and it isn't being saved already.
    var canConfirm: Bool {
        !isApplying && !included.isEmpty
    }

    /// Saves the ticked lines into the list: linked items are checked off (or priced) with the
    /// sum of their lines, the others are added already bought, for who the person chose.
    ///
    /// - Returns: `true` when everything was saved; otherwise `shopList` has the error.
    func confirm(into shopList: ShopListViewModel) async -> Bool {
        isApplying = true
        defer { isApplying = false }

        var totals: [String: Double] = [:]
        var newItems: [ShopListViewModel.ReceiptNewItem] = []
        for line in lines where included.contains(line.id) {
            if let item = linkedItem(for: line) {
                totals[item.id, default: 0] += line.total
                continue
            }
            let name = line.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let amount = Self.listAmount(for: line)
            newItems.append(.init(
                name: name,
                total: line.total,
                quantity: amount.quantity,
                unit: amount.unit,
                consumers: consumers(for: line)
            ))
        }
        let purchases = linkableItems.compactMap { item in
            totals[item.id].map { total in
                ShopListViewModel.ReceiptPurchase(item: item, total: total, amount: weighedAmount(for: item))
            }
        }

        let saved = await shopList.applyReceipt(purchases: purchases, newItems: newItems)
        await shopList.rememberReceiptNames(learnedNames())
        return saved == purchases.count + newItems.count
    }

    /// What to remember from this receipt: the list item each ticked line was linked to, and
    /// the names the person typed for new items. Untouched new items teach nothing.
    func learnedNames() -> [String: String] {
        var names: [String: String] = [:]
        for line in lines where included.contains(line.id) {
            let name: String
            if let item = linkedItem(for: line) {
                name = item.name
            } else {
                let typed = line.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !typed.isEmpty, typed != readNames[line.id] else { continue }
                name = typed
            }
            for key in ReceiptNameMemory.keys(for: line) {
                names[key] = name
            }
        }
        return names
    }

    /// The list's quantity and unit for a line: grams for a weighed product (kilograms past
    /// what the quantity field allows), otherwise units.
    static func listAmount(for line: ReceiptScanLine) -> (quantity: Int, unit: UnitMeasurement) {
        if line.weightKg > 0 { return listAmount(weightKg: line.weightKg) }
        let range = QuantityStepper.allowedRange
        return (min(max(line.quantity, range.lowerBound), range.upperBound), .unit)
    }

    /// A weight as the list writes it: grams, or kilograms past what the quantity field allows.
    static func listAmount(weightKg: Double) -> (quantity: Int, unit: UnitMeasurement) {
        let range = QuantityStepper.allowedRange
        let grams = Int((weightKg * 1000).rounded())
        if range.contains(grams) { return (grams, .gram) }
        return (min(max(Int(weightKg.rounded()), range.lowerBound), range.upperBound), .kilogram)
    }

    // MARK: - Weighed products

    /// The weight bought of a list item, when everything ticked for it on the receipt was
    /// weighed ("500 g" on the list, 0,364 kg on the receipt -> 364 g). `nil` when there's
    /// nothing weighed, or it's already the item's quantity.
    func weighedAmount(for item: ShopListItem) -> (quantity: Int, unit: UnitMeasurement)? {
        let itemLines = lines.filter { included.contains($0.id) && links[$0.id] == item.id }
        guard !itemLines.isEmpty, itemLines.allSatisfy({ $0.weightKg > 0 }) else { return nil }
        let amount = Self.listAmount(weightKg: itemLines.map(\.weightKg).reduce(0, +))
        guard amount.quantity != item.quantity || amount.unit != item.unitMeasurement else { return nil }
        return amount
    }

    /// "500 gramas" -> "364 gramas": how a weighed line will change its list item's quantity,
    /// shown on the card before confirming.
    func quantityChange(for line: ReceiptScanLine) -> (from: String, to: String)? {
        guard line.weightKg > 0, let item = linkedItem(for: line), let amount = weighedAmount(for: item) else { return nil }
        return (
            ShopListViewModel.accessibilityQuantity(item.quantity, unit: item.unitMeasurement),
            ShopListViewModel.accessibilityQuantity(amount.quantity, unit: amount.unit)
        )
    }

    // MARK: - Summary

    /// What the products add up to (all of them, ticked or not, to compare with the receipt).
    var sum: Double {
        lines.map(\.total).reduce(0, +)
    }

    /// The sum against the receipt's printed totals.
    var totalCheck: TotalCheck {
        guard let closest = printedTotals.min(by: { abs(sum - $0) < abs(sum - $1) }) else {
            return .noPrintedTotal
        }
        if abs(sum - closest) <= max(closest * 0.01, 0.05) {
            return .matches(closest)
        }
        return .differs(total: closest, difference: sum - closest)
    }

    /// Lines the person should look at.
    var warningCount: Int {
        lines.filter { $0.warning != nil }.count
    }

    /// Whether the receipt looks hard to read: the sum doesn't match and many lines have
    /// warnings, or fewer products were found than the receipt says it has. The screen then
    /// suggests scanning again.
    var looksHardToRead: Bool {
        if case .matches = totalCheck { return false }
        if let printedItemCount, lines.count < printedItemCount / 2 { return true }
        return warningCount * 3 > lines.count
    }

    // MARK: - Formatting

    /// The price field's text for a value ("18,16").
    static func priceText(for value: Double) -> String {
        value > 0 ? ShopListViewModel.priceInputText(for: value) : ""
    }

    /// "R$ 18,16" in the app's language.
    static func money(_ value: Double) -> String {
        value.formatted(FloatingPointFormatStyle<Double>.Currency(code: "BRL").locale(L10n.locale))
    }

    /// "2 unidades" or "0,364 kg"; empty for a single unit.
    static func amountText(for line: ReceiptScanLine) -> String {
        if line.weightKg > 0 {
            let weight = line.weightKg.formatted(.number.precision(.fractionLength(3)).locale(L10n.locale))
            return "\(weight) kg"
        }
        guard line.quantity > 1 else { return "" }
        return "\(line.quantity) \(UnitMeasurement.unit.getDisplayName(for: Double(line.quantity)))"
    }

    /// What a warning tells the person, translated.
    static func warningText(_ warning: ReceiptLineWarning) -> String {
        switch warning {
        case .totalMismatch(let computed, let printed):
            return L10n.tr("Confira o valor: calculado \(money(computed)), impresso \(money(printed))")
        case .quantityNotRead:
            return L10n.tr("Quantidade não lida: usado o valor impresso")
        case .noAmount:
            return L10n.tr("Valor não encontrado")
        case .notOnReceipt:
            return L10n.tr("Confira o valor: não aparece na nota")
        }
    }
}
