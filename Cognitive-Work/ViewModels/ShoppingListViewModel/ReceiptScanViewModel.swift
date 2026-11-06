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
    /// Photos left out as repeats of an earlier one.
    private(set) var repeatedPages = 0

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
    /// Who each line is for, by ``UserModel/id``, when the person chose. Without an entry, a
    /// line linked to a list item is for that item's people, and a new item for the whole house
    /// (like the AI items).
    private(set) var consumerIDs: [UUID: Set<String>] = [:]

    /// Lines whose quantity the person changed; a list item linked to them takes it.
    private(set) var editedQuantities: Set<UUID> = []
    /// The aisle of each line, for the ones added as new items (a line linked to a list item
    /// keeps the item's). See ``guessCategory(for:)``.
    private(set) var categories: [UUID: ShopItemCategory] = [:]
    /// Lines whose aisle the person picked: renaming them doesn't guess it again, and the
    /// house remembers it.
    private(set) var editedCategories: Set<UUID> = []
    /// Lines whose aisle the on-device model chose; the card marks them so the person checks.
    private(set) var aiCategories: Set<UUID> = []
    /// The aisle the house already uses for a product name (see
    /// ``ShopListViewModel/receiptCategory(named:)``).
    @ObservationIgnored
    private var knownCategory: (String) -> ShopItemCategory? = { _ in nil }
    /// The house's memory of receipt products, for their aisles.
    @ObservationIgnored
    private var memory: [String: String] = [:]
    /// Whether the confirmed receipt is being saved.
    private(set) var isApplying = false
    /// Lines the person added whose form wasn't confirmed yet; closing that form removes them.
    private(set) var newLineIDs: Set<UUID> = []

    // MARK: - Reading

    /// The name each line had when read, to tell which ones the person renamed.
    private var readNames: [UUID: String] = [:]

    /// Reads the photos of one receipt and pairs the products with `items` by their names.
    /// Names are spelled out (``ReceiptAbbreviations``) or, for products the house scanned
    /// before, replaced by what it called them (`memory`, see ``ReceiptNameMemory``).
    ///
    /// - Parameters:
    ///   - houseUsers: Who a product bought outside the list can be for.
    ///   - knownCategory: The aisle the house already uses for a product name.
    func read(
        _ pages: [UIImage],
        linking items: [ShopListItem],
        houseUsers: [UserModel],
        memory: [String: String] = [:],
        knownCategory: @escaping (String) -> ShopItemCategory? = { _ in nil }
    ) async {
        phase = .reading
        let result = await ReceiptScanService.read(pages)
        load(result, linking: items, houseUsers: houseUsers, memory: memory, knownCategory: knownCategory)
    }

    /// Shows what was read from a receipt (``read(_:linking:houseUsers:memory:knownCategory:)``
    /// after reading; previews and tests call it directly).
    func load(
        _ result: ReceiptScanResult,
        linking items: [ShopListItem],
        houseUsers: [UserModel],
        memory: [String: String] = [:],
        knownCategory: @escaping (String) -> ShopItemCategory? = { _ in nil }
    ) {
        lines = result.lines.map { line in
            var line = line
            line.receiptName = line.name
            line.name = ReceiptNameMemory.name(for: line, in: memory) ?? ReceiptAbbreviations.expand(line.name)
            return line
        }
        editedQuantities = []
        self.memory = memory
        self.knownCategory = knownCategory
        editedCategories = []
        aiCategories = []
        categories = Dictionary(uniqueKeysWithValues: lines.map { ($0.id, guessCategory(for: $0)) })
        readNames = Dictionary(uniqueKeysWithValues: lines.map { ($0.id, $0.name) })
        priceTexts = Dictionary(uniqueKeysWithValues: lines.map { ($0.id, Self.priceText(for: $0.total)) })
        printedTotals = result.printedTotals
        printedItemCount = result.printedItemCount
        missingItemNumbers = result.missingItemNumbers
        readFromPhoto = result.readFromPhoto
        repeatedPages = result.repeatedPages

        linkableItems = items
        self.houseUsers = houseUsers
        included = Set(lines.map(\.id))
        links = [:]
        consumerIDs = [:]
        newLineIDs = []
        let pairs = ReceiptItemMatcher.match(receiptNames: lines.map(\.name), listNames: items.map(\.name))
        for (itemIndex, lineIndex) in pairs {
            links[lines[lineIndex].id] = items[itemIndex].id
        }

        phase = lines.isEmpty ? .empty : .review
    }

    // MARK: - Editing

    /// Changes how many units a line has. The price follows the receipt's price per unit, as
    /// when a misread quantity is fixed ("1 UN" read for "2 UN").
    func setQuantity(_ quantity: Int, for line: ReceiptScanLine) {
        guard QuantityStepper.allowedRange.contains(quantity),
              let index = lines.firstIndex(where: { $0.id == line.id }) else { return }
        let old = lines[index]
        if old.total > 0, old.quantity > 0 {
            let total = (old.total / Double(old.quantity) * Double(quantity) * 100).rounded() / 100
            lines[index].total = total
            priceTexts[line.id] = Self.priceText(for: total)
        }
        lines[index].quantity = quantity
        editedQuantities.insert(line.id)
    }

    /// Adds an empty line, ticked, for a product the reader missed. It stays new (see
    /// ``newLineIDs``) until its form is confirmed.
    @discardableResult
    func addLine() -> ReceiptScanLine {
        let line = ReceiptScanLine(itemNumber: nil, name: "", quantity: 1, weightKg: 0, total: 0, warning: nil)
        lines.append(line)
        priceTexts[line.id] = ""
        readNames[line.id] = ""
        categories[line.id] = .other
        included.insert(line.id)
        newLineIDs.insert(line.id)
        if phase == .empty { phase = .review }
        return line
    }

    /// Takes `line` off the receipt (a line the person added and then gave up on). Without
    /// lines left, the screen goes back to "nothing found".
    func removeLine(_ line: ReceiptScanLine) {
        let id = line.id
        lines.removeAll { $0.id == id }
        priceTexts[id] = nil
        readNames[id] = nil
        categories[id] = nil
        included.remove(id)
        links[id] = nil
        consumerIDs[id] = nil
        editedQuantities.remove(id)
        editedCategories.remove(id)
        aiCategories.remove(id)
        newLineIDs.remove(id)
        if lines.isEmpty { phase = .empty }
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

    // MARK: - Aisle

    /// The aisle `line` goes in: the linked list item's, or the one guessed or picked.
    func category(for line: ReceiptScanLine) -> ShopItemCategory {
        linkedItem(for: line)?.category ?? categories[line.id] ?? .other
    }

    /// The aisle of a line, without the model: the one the house put it in before, the one the
    /// house uses for the same name, or the one its words tell (``ReceiptCategories``);
    /// "Outros" when none does.
    private func guessCategory(for line: ReceiptScanLine) -> ShopItemCategory {
        if !line.receiptName.isEmpty,
           let stored = ReceiptNameMemory.category(for: line, in: memory),
           let category = ShopItemCategory(rawValue: stored) {
            return category
        }
        return knownCategory(line.name) ?? ReceiptCategories.guess(line.name) ?? .other
    }

    /// The aisle a typed name suggests, without the model: the one the house uses for it, or
    /// the one its words tell; "Outros" when none does.
    func guessCategory(named name: String) -> ShopItemCategory {
        knownCategory(name) ?? ReceiptCategories.guess(name) ?? .other
    }

    /// For the products outside the list still in "Outros", asks the on-device model, one at a
    /// time, while the person reviews. What it can't tell stays in "Outros"; a line the person
    /// renamed or gave an aisle meanwhile is left as it is.
    func guessCategoriesWithAI() async {
        guard IntelligenceManager.shared.isAvailable else { return }
        let unknown = lines.filter { line in
            linkedItem(for: line) == nil && categories[line.id] == .other && !editedCategories.contains(line.id)
        }
        for line in unknown {
            guard !Task.isCancelled else { return }
            guard let category = await IntelligenceManager.shared.receiptCategory(for: line.name) else { continue }
            guard let current = lines.first(where: { $0.id == line.id }), current.name == line.name,
                  !editedCategories.contains(line.id), categories[line.id] == .other
            else { continue }
            categories[line.id] = category
            aiCategories.insert(line.id)
        }
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

    /// The lines grouped by the aisle they go in, in the shopping list's order, like the
    /// list's cards.
    var sections: [ReceiptCategorySection] {
        let grouped = Dictionary(grouping: lines) { category(for: $0) }
        return ShopItemCategory.listOrder.compactMap { category in
            grouped[category].map { ReceiptCategorySection(category: category, lines: $0) }
        }
    }

    // MARK: - Who it's for

    /// Who `line` is for: who the person chose; otherwise the list item's people, or the whole
    /// house for a new item.
    func consumers(for line: ReceiptScanLine) -> [UserModel] {
        if let ids = consumerIDs[line.id] {
            return houseUsers.filter { ids.contains($0.id) }
        }
        return defaultConsumers(forItemID: links[line.id])
    }

    /// Who a line is for before the person picks: the list item's people, or the whole house.
    func defaultConsumers(forItemID itemID: String?) -> [UserModel] {
        if let itemID, let item = linkableItems.first(where: { $0.id == itemID }) {
            let people = item.relatedUsers(in: houseUsers)
            if !people.isEmpty { return people }
        }
        return houseUsers
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
                consumers: consumers(for: line),
                category: category(for: line)
            ))
        }
        let purchases = linkableItems.compactMap { item in
            totals[item.id].map { total in
                ShopListViewModel.ReceiptPurchase(
                    item: item,
                    total: total,
                    amount: boughtAmount(for: item),
                    consumers: chosenConsumers(for: item)
                )
            }
        }

        let saved = await shopList.applyReceipt(purchases: purchases, newItems: newItems)
        await shopList.rememberReceiptNames(learnedNames())
        return saved == purchases.count + newItems.count
    }

    /// What to remember from this receipt: the list item each ticked line was linked to, the
    /// names the person typed for new items, and the aisles they picked (not the model's
    /// guesses). Untouched new items teach nothing.
    func learnedNames() -> [String: String] {
        var names: [String: String] = [:]
        // Lines the person added have no printed name to remember.
        for line in lines where included.contains(line.id) && !line.receiptName.isEmpty {
            // The aisle: the list item's, or the one the person picked.
            let category: ShopItemCategory? = linkedItem(for: line)?.category
                ?? (editedCategories.contains(line.id) ? categories[line.id] : nil)
            if let category, category != .other {
                for key in ReceiptNameMemory.categoryKeys(for: line) {
                    names[key] = category.rawValue
                }
            }

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

    // MARK: - What changes on a list item

    /// What a list item's quantity becomes: the weight bought, when everything ticked for it on
    /// the receipt was weighed ("500 g" on the list, 0,364 kg on the receipt -> 364 g), or the
    /// units, when the person changed them on a card (only for items counted in units or
    /// packages). `nil` keeps the item's quantity.
    func boughtAmount(for item: ShopListItem) -> (quantity: Int, unit: UnitMeasurement)? {
        let itemLines = lines.filter { included.contains($0.id) && links[$0.id] == item.id }
        guard !itemLines.isEmpty else { return nil }

        let amount: (quantity: Int, unit: UnitMeasurement)
        if itemLines.allSatisfy({ $0.weightKg > 0 }) {
            amount = Self.listAmount(weightKg: itemLines.map(\.weightKg).reduce(0, +))
        } else if itemLines.contains(where: { editedQuantities.contains($0.id) }),
                  itemLines.allSatisfy({ $0.weightKg == 0 }),
                  [UnitMeasurement.unit, .package, .undefined].contains(item.unitMeasurement) {
            let range = QuantityStepper.allowedRange
            let units = min(max(itemLines.map(\.quantity).reduce(0, +), range.lowerBound), range.upperBound)
            amount = (units, item.unitMeasurement == .undefined ? .unit : item.unitMeasurement)
        } else {
            return nil
        }
        guard amount.quantity != item.quantity || amount.unit != item.unitMeasurement else { return nil }
        return amount
    }

    /// Who a list item is for after the receipt: who the person picked on one of its cards, or
    /// `nil` to keep its people.
    func chosenConsumers(for item: ShopListItem) -> [UserModel]? {
        let picked = lines.first { line in
            included.contains(line.id) && links[line.id] == item.id && consumerIDs[line.id] != nil
        }
        return picked.map(consumers(for:))
    }

    // MARK: - Editing one line (the line form)

    /// A copy of `line` for ``ReceiptLineFormView``.
    func draft(for line: ReceiptScanLine) -> ReceiptLineDraft {
        let current = lines.first { $0.id == line.id } ?? line
        let id = current.id
        return ReceiptLineDraft(
            id: id,
            isNew: newLineIDs.contains(id),
            weightKg: current.weightKg,
            warning: current.warning,
            name: current.name,
            quantity: current.quantity,
            priceText: priceTexts[id] ?? Self.priceText(for: current.total),
            unitPrice: current.quantity > 0 ? current.total / Double(current.quantity) : current.total,
            linkedItemID: links[id],
            category: categories[id] ?? .other,
            aiCategory: aiCategories.contains(id) ? categories[id] : nil,
            didPickCategory: editedCategories.contains(id),
            consumers: consumers(for: current),
            didPickConsumers: consumerIDs[id] != nil
        )
    }

    /// A typed name. The aisle of a new item follows it until the person picks one.
    func setName(_ name: String, in draft: inout ReceiptLineDraft) {
        draft.name = name
        if !draft.didPickCategory {
            draft.category = guessCategory(named: name)
        }
    }

    /// Units bought; the price follows the price of one unit, as on the review.
    func setQuantity(_ quantity: Int, in draft: inout ReceiptLineDraft) {
        draft.quantity = quantity
        guard quantity > 0, draft.unitPrice > 0 else { return }
        let total = (draft.unitPrice * Double(quantity) * 100).rounded() / 100
        draft.priceText = Self.priceText(for: total)
    }

    /// A typed price; it becomes the new price of one unit.
    func setPrice(_ text: String, in draft: inout ReceiptLineDraft) {
        draft.priceText = text
        guard draft.quantity > 0 else { return }
        draft.unitPrice = (ShopListViewModel.parsePrice(text) ?? 0) / Double(draft.quantity)
    }

    /// The list item the line checks off (`nil`: a new item). The people follow it until the
    /// person picks them.
    func setLink(_ itemID: String?, in draft: inout ReceiptLineDraft) {
        draft.linkedItemID = itemID
        if !draft.didPickConsumers {
            draft.consumers = defaultConsumers(forItemID: itemID)
        }
    }

    /// The aisle the person picked.
    func setCategory(_ category: ShopItemCategory, in draft: inout ReceiptLineDraft) {
        draft.category = category
        draft.didPickCategory = true
    }

    /// Who the person picked to split the price.
    func setConsumers(_ users: [UserModel], in draft: inout ReceiptLineDraft) {
        draft.consumers = users
        draft.didPickConsumers = true
    }

    /// The list item a draft checks off, if any.
    func linkedItem(for draft: ReceiptLineDraft) -> ShopListItem? {
        draft.linkedItemID.flatMap { id in linkableItems.first { $0.id == id } }
    }

    /// What still keeps the form from being confirmed, one thing at a time; `nil` when it can be.
    func missingFieldText(in draft: ReceiptLineDraft) -> String? {
        // The same warnings as the item form.
        if draft.trimmedName.isEmpty { return ShopItemField.name.warning }
        if !draft.isWeighed, draft.quantity < 1 { return ShopItemField.quantity.warning }
        if draft.consumers.isEmpty { return ShopItemField.consumers.warning }
        return nil
    }

    /// Applies a confirmed draft to its line, which goes back to being ticked.
    func save(_ draft: ReceiptLineDraft) {
        guard missingFieldText(in: draft) == nil,
              let index = lines.firstIndex(where: { $0.id == draft.id })
        else { return }
        let id = draft.id
        let original = lines[index]
        newLineIDs.remove(id)
        included.insert(id)

        lines[index].name = draft.trimmedName
        if !draft.isWeighed, draft.quantity != original.quantity {
            lines[index].quantity = draft.quantity
            editedQuantities.insert(id)
        }
        if draft.priceText != priceTexts[id] {
            priceTexts[id] = draft.priceText
            lines[index].total = ShopListViewModel.parsePrice(draft.priceText) ?? 0
            // The person checked the value: no more warning.
            lines[index].warning = nil
        }
        links[id] = draft.linkedItemID
        // Only an aisle the form changed: the model may have guessed one meanwhile.
        if draft.didPickCategory || draft.trimmedName != original.name {
            categories[id] = draft.category
            if !draft.isCategoryFromAI { aiCategories.remove(id) }
        }
        if draft.didPickCategory { editedCategories.insert(id) }
        consumerIDs[id] = draft.didPickConsumers ? Set(draft.consumers.map(\.id)) : nil
    }

    /// Closes a form without confirming: a line the person had just added goes away.
    func discard(_ draft: ReceiptLineDraft) {
        guard newLineIDs.contains(draft.id),
              let line = lines.first(where: { $0.id == draft.id })
        else { return }
        removeLine(line)
    }

    // MARK: - What each card says

    /// "2 unidades" or "0,364 kg".
    static func quantityText(for line: ReceiptScanLine) -> String {
        if line.weightKg > 0 { return amountText(for: line) }
        return ShopListViewModel.accessibilityQuantity(line.quantity, unit: .unit)
    }

    /// The line under a product's name: "Na lista · 2 unidades · R$ 5,98" ("Na lista" when it
    /// checks off a list item).
    func detailText(for line: ReceiptScanLine) -> String {
        var parts = [Self.quantityText(for: line), Self.money(line.total)]
        if linkedItem(for: line) != nil { parts.insert(L10n.tr("Na lista"), at: 0) }
        return parts.joined(separator: " · ")
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
        if line.weightKg > 0 { return weightText(line.weightKg) }
        guard line.quantity > 1 else { return "" }
        return "\(line.quantity) \(UnitMeasurement.unit.getDisplayName(for: Double(line.quantity)))"
    }

    /// "0,364 kg".
    static func weightText(_ kilograms: Double) -> String {
        let weight = kilograms.formatted(.number.precision(.fractionLength(3)).locale(L10n.locale))
        return "\(weight) kg"
    }

    /// What to check on a line the reader flagged, shown under its price in the form.
    static func warningText(_ warning: ReceiptLineWarning) -> String {
        switch warning {
        case .totalMismatch(_, let printed):
            return L10n.tr("Confira o valor. Na nota aparece \(money(printed)).")
        case .quantityNotRead:
            return L10n.tr("Confira a quantidade.")
        case .noAmount:
            return L10n.tr("Digite o valor pago.")
        case .notOnReceipt:
            return L10n.tr("Confira o valor.")
        }
    }

}

/// The products of one aisle, shown in one card on the review.
struct ReceiptCategorySection: Identifiable {
    let category: ShopItemCategory
    let lines: [ReceiptScanLine]
    var id: ShopItemCategory { category }
}
