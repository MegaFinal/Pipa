//
//  ReceiptScanViewModel.swift
//  Cognitive-Work
//
//  Created by anshu Li on 04/11/26.
//

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

    /// What happens to a line when the person confirms.
    enum Target: Equatable {
        /// Checks off this list item (by ``ShopListItem/id``) with the line's price.
        case item(String)
        /// Adds the product to the list, already bought.
        case newItem
        /// Leaves it out.
        case skip
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

    // MARK: - Linking to the list

    /// The list items a line can be linked to (see ``ShopListViewModel/receiptLinkableItems``).
    private(set) var linkableItems: [ShopListItem] = []
    /// Where each line goes. Lines start left out unless their name matched a list item: many
    /// products on a receipt were never on the list, so a line is only paired when the words
    /// clearly match (no AI guess, which paired almost every line with something).
    private(set) var targets: [UUID: Target] = [:]
    /// Whether the confirmed receipt is being saved.
    private(set) var isApplying = false

    // MARK: - Reading

    /// Reads the photos of one receipt and pairs the products with `items` by their names.
    func read(_ pages: [UIImage], linking items: [ShopListItem]) async {
        phase = .reading
        let result = await ReceiptScanService.read(pages)
        lines = result.lines.map { line in
            var line = line
            line.name = Self.displayName(line.name)
            return line
        }
        priceTexts = Dictionary(uniqueKeysWithValues: lines.map { ($0.id, Self.priceText(for: $0.total)) })
        printedTotals = result.printedTotals
        printedItemCount = result.printedItemCount
        missingItemNumbers = result.missingItemNumbers

        linkableItems = items
        targets = Dictionary(uniqueKeysWithValues: lines.map { ($0.id, Target.skip) })
        matchByName()

        phase = lines.isEmpty ? .empty : .review
    }

    /// Pairs lines and list items whose words match (``ReceiptItemMatcher``).
    private func matchByName() {
        let pairs = ReceiptItemMatcher.match(receiptNames: lines.map(\.name), listNames: linkableItems.map(\.name))
        for (itemIndex, lineIndex) in pairs {
            targets[lines[lineIndex].id] = .item(linkableItems[itemIndex].id)
        }
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

    /// Changes where `line` goes.
    func setTarget(_ target: Target, for line: ReceiptScanLine) {
        targets[line.id] = target
    }

    /// Adds every line that is left out as a new item.
    func addSkippedAsNew() {
        for line in lines where targets[line.id] == .skip {
            targets[line.id] = .newItem
        }
    }

    /// Removes a line read by mistake.
    func remove(_ line: ReceiptScanLine) {
        lines.removeAll { $0.id == line.id }
        priceTexts[line.id] = nil
        targets[line.id] = nil
        if lines.isEmpty { phase = .empty }
    }

    // MARK: - Linking summary

    /// The list item `id` refers to.
    func item(withID id: String) -> ShopListItem? {
        linkableItems.first { $0.id == id }
    }

    /// Whether some line is linked to `item`.
    func isLinked(_ item: ShopListItem) -> Bool {
        targets.values.contains(.item(item.id))
    }

    /// Items still to buy that no line was linked to: the receipt doesn't seem to have them.
    var unfoundItems: [ShopListItem] {
        linkableItems.filter { !$0.isBought && !isLinked($0) }
    }

    /// How many list items will be checked off or priced.
    var linkedCount: Int {
        Set(targets.values.compactMap { target -> String? in
            if case .item(let id) = target { return id }
            return nil
        }).count
    }

    /// How many products will be added to the list.
    var newCount: Int {
        targets.values.filter { $0 == .newItem }.count
    }

    /// How many lines are left out.
    var skippedCount: Int {
        targets.values.filter { $0 == .skip }.count
    }

    /// Whether there is something to confirm, and it isn't being saved already.
    var canConfirm: Bool {
        !isApplying && linkedCount + newCount > 0
    }

    // MARK: - Confirming

    /// Saves the review into the list: linked items are checked off (or priced) with the sum
    /// of their lines, and new products are added already bought. Left-out lines are dropped.
    ///
    /// - Returns: `true` when everything was saved; otherwise `shopList` has the error.
    func confirm(into shopList: ShopListViewModel) async -> Bool {
        isApplying = true
        defer { isApplying = false }

        var totals: [String: Double] = [:]
        var newItems: [ShopListViewModel.ReceiptNewItem] = []
        for line in lines {
            switch targets[line.id] ?? .skip {
            case .item(let id):
                totals[id, default: 0] += line.total
            case .newItem:
                let name = line.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                let amount = Self.listAmount(for: line)
                newItems.append(.init(name: name, total: line.total, quantity: amount.quantity, unit: amount.unit))
            case .skip:
                continue
            }
        }
        let purchases = linkableItems.compactMap { item in
            totals[item.id].map { ShopListViewModel.ReceiptPurchase(item: item, total: $0) }
        }

        let saved = await shopList.applyReceipt(purchases: purchases, newItems: newItems)
        return saved == purchases.count + newItems.count
    }

    /// The list's quantity and unit for a line: grams for a weighed product (kilograms past
    /// what the quantity field allows), otherwise units.
    static func listAmount(for line: ReceiptScanLine) -> (quantity: Int, unit: UnitMeasurement) {
        let range = QuantityStepper.allowedRange
        func clamped(_ value: Int) -> Int { min(max(value, range.lowerBound), range.upperBound) }

        if line.weightKg > 0 {
            let grams = Int((line.weightKg * 1000).rounded())
            if range.contains(grams) { return (grams, .gram) }
            return (clamped(Int(line.weightKg.rounded())), .kilogram)
        }
        return (clamped(line.quantity), .unit)
    }

    // MARK: - Summary

    /// What the products add up to.
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

    /// A receipt name as the list would show it: "LTE COND.MOC.TP 395g" -> "Lte cond.moc.tp
    /// 395g". Names already in mixed case are kept.
    static func displayName(_ name: String) -> String {
        let letters = name.filter(\.isLetter)
        guard !letters.isEmpty else { return name }
        let upper = letters.filter(\.isUppercase).count
        guard upper * 5 >= letters.count * 4 else { return name }
        let lowered = name.lowercased(with: L10n.locale)
        return lowered.prefix(1).uppercased(with: L10n.locale) + lowered.dropFirst()
    }

    /// The price field's text for a value ("18,16").
    static func priceText(for value: Double) -> String {
        value > 0 ? ShopListViewModel.priceInputText(for: value) : ""
    }

    /// "R$ 18,16" in the app's language.
    static func money(_ value: Double) -> String {
        value.formatted(FloatingPointFormatStyle<Double>.Currency(code: "BRL").locale(L10n.locale))
    }

    /// "2 ×" or "0,364 kg"; empty for a single unit.
    static func amountText(for line: ReceiptScanLine) -> String {
        if line.weightKg > 0 {
            let weight = line.weightKg.formatted(.number.precision(.fractionLength(3)).locale(L10n.locale))
            return "\(weight) kg"
        }
        return line.quantity > 1 ? "\(line.quantity) ×" : ""
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
        }
    }
}
