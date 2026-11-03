//
//  ShopListViewModel.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 18/09/26.
//

import Foundation
import CloudKit

// MARK: - Presentation types

/// How the items are ordered inside each category card. The list is always grouped by category.
enum ShopListSortOption: String, CaseIterable, Identifiable {
    /// Most recently added first.
    case newestFirst
    /// Added longest ago first.
    case oldestFirst

    /// Identifier for SwiftUI lists (the raw value).
    var id: String { rawValue }

    /// The option's name in the sort menu, translated.
    var label: String {
        switch self {
        case .newestFirst: return L10n.tr("Adicionados recentemente")
        case .oldestFirst: return L10n.tr("Adicionados há mais tempo")
        }
    }

    /// SF Symbol of the option in the sort menu.
    var symbol: String {
        switch self {
        case .newestFirst: return "clock"
        case .oldestFirst: return "clock.arrow.circlepath"
        }
    }
}

/// A field the add/edit form requires before it can be saved.
enum ShopItemField: CaseIterable {
    /// The item's name.
    case name
    /// How much to buy.
    case quantity
    /// The unit of the amount.
    case unit
    /// The aisle.
    case category
    /// Who the item is for.
    case consumers

    /// What the form tells the user to do, in the same wording as the chore form's warnings
    /// ("Escolha um cômodo para confirmar a tarefa.").
    var warning: String {
        switch self {
        case .name: return L10n.tr("Digite o nome para confirmar o item.")
        case .quantity: return L10n.tr("Informe a quantidade para confirmar o item.")
        case .unit: return L10n.tr("Escolha uma unidade para confirmar o item.")
        case .category: return L10n.tr("Escolha uma categoria para confirmar o item.")
        case .consumers: return L10n.tr("Escolha quem vai consumir/pagar para confirmar o item.")
        }
    }
}

/// A titled group of items, shown as one collapsible section.
struct ShopListSection: Identifiable {
    /// Identifier for SwiftUI lists and for remembering collapsed sections.
    let id: String
    /// The section's title.
    let title: String
    /// The items in the section.
    let items: [ShopListItem]
    /// The category the section groups, or `nil` for sections that mix categories ("A comprar",
    /// "Comprados"). It gives the card its color and icon.
    var category: ShopItemCategory? = nil
}

/// One card of the stacked list: a section plus how the stack draws it.
struct ShopListStackEntry: Identifiable {
    /// The section the card shows.
    let section: ShopListSection
    /// Whether the card is open (header and items) or closed (header only).
    let isExpanded: Bool
    /// Whether the next card sits on top of this one's lower edge. Only closed cards that are
    /// followed by another closed card overlap.
    let overlapsNext: Bool
    /// Whether the card comes right after another open card, to which it is stitched.
    let followsExpanded: Bool
    /// Whether another open card comes right after this one and is stitched to it.
    let precedesExpanded: Bool

    /// The section's id, so SwiftUI keeps the card's identity while it moves.
    var id: String { section.id }
}

/// Owns the house's shopping list, its items, and the house members available to assign items.
@MainActor
@Observable
final class ShopListViewModel {

    /// The house's shopping list, or `nil` before loading or when the house has none.
    private(set) var list: ShopListModel?

    /// Every item of the list, bought or not.
    private(set) var items: [ShopListItem] = []

    /// The house members, one per person.
    private(set) var houseUsers: [UserModel] = []

    /// Every user record of the house, also the extra ones of the same person (see
    /// ``HouseSnapshot/userRecords``).
    private(set) var houseUserRecords: [UserModel] = []

    /// The signed-in user's in-house record, credited as ``ShopListItem/addedByUser`` on items
    /// created here.
    private(set) var currentUser: UserModel?

    /// An error to show, or `nil`.
    private(set) var errorMessage: String?

    /// Items still to buy.
    var pendingItems: [ShopListItem] {
        items.filter { !$0.isBought }
    }

    /// Bought items still on the list: the ones whose shares were all paid leave it (they stay
    /// stored, and ``items`` still has them, so the debts keep adding up).
    var boughtItems: [ShopListItem] {
        items.filter { $0.isBought && !isFullySettled($0) }
    }

    /// Whether the list has nothing to show. Not `items.isEmpty`: fully settled items stay in
    /// ``items`` (for the debts) but are hidden, so a list with only those would render blank.
    var isListEmpty: Bool {
        pendingItems.isEmpty && boughtItems.isEmpty
    }

    /// Whether `item` was bought with a price shared with others and every one of them already
    /// paid the buyer. People are matched by `ownerRecordName`, like ``DebtCalculator``, since
    /// the same person may have more than one user record.
    func isFullySettled(_ item: ShopListItem) -> Bool {
        guard item.isBought, item.hasPrice, let buyerID = item.buyerRecordID else { return false }

        var ownerByRecord: [String: String] = [:]
        for user in houseUserRecords + houseUsers {
            if let name = user.recordID?.recordName { ownerByRecord[name] = user.ownerRecordName }
        }
        func person(_ id: CKRecord.ID) -> String { ownerByRecord[id.recordName] ?? id.recordName }

        let buyer = person(buyerID)
        let settled = Set(item.settledUserIDs.map(person))
        let debtors = Set(item.consumerRecordIDs.map(person)).subtracting([buyer])

        return !debtors.isEmpty && debtors.isSubset(of: settled)
    }

    // MARK: - Presentation

    /// How the list is ordered.
    var sortOption: ShopListSortOption = .newestFirst

    /// Identifies the "Comprados" section.
    static let boughtSectionID = "bought"

    /// Sections the user opened.
    private(set) var expandedSectionIDs: Set<String> = [ShopListViewModel.boughtSectionID]

    /// The card that was just opened.
    private(set) var movingSectionID: String?

    /// Clears ``movingSectionID`` once the card has settled.
    @ObservationIgnored
    private var movingResetTask: Task<Void, Never>?

    /// Whether the "+" button can add items (the list has to be loaded first).
    var canAddItems: Bool { list != nil }

    /// "3 itens para comprar", shown under the title.
    var pendingSummary: String {
        L10n.tr("\(pendingItems.count) itens para comprar")
    }

    /// Pending items as one section per category, in the fixed ``ShopItemCategory/listOrder``,
    /// each with its items in the order of ``sortOption``.
    var pendingSections: [ShopListSection] {
        let pending = pendingItems

        return ShopItemCategory.listOrder.compactMap { category in
            let items = sorted(pending.filter { $0.category == category })
            return items.isEmpty ? nil : ShopListSection(id: category.rawValue, title: category.displayName, items: items, category: category)
        }
    }

    /// The "Comprados" section, or `nil` when nothing was bought yet.
    var boughtSection: ShopListSection? {
        let items = sorted(boughtItems)
        return items.isEmpty ? nil : ShopListSection(id: Self.boughtSectionID, title: L10n.tr("Comprados"), items: items)
    }

    /// `items` by the date they were added, in the direction of ``sortOption``.
    private func sorted(_ items: [ShopListItem]) -> [ShopListItem] {
        switch sortOption {
        case .newestFirst: return items.sorted { $0.createdAt > $1.createdAt }
        case .oldestFirst: return items.sorted { $0.createdAt < $1.createdAt }
        }
    }

    /// Whether `section` is collapsed.
    func isCollapsed(_ section: ShopListSection) -> Bool {
        !expandedSectionIDs.contains(section.id)
    }

    /// Collapses or expands `section`.
    func toggleCollapsed(_ section: ShopListSection) {
        if expandedSectionIDs.contains(section.id) {
            expandedSectionIDs.remove(section.id)
            movingResetTask?.cancel()
            movingSectionID = nil
        } else {
            expandedSectionIDs.insert(section.id)
            markMoving(section)
        }
    }

    /// Lays `sections` out as a stack of cards
    func stackEntries(for sections: [ShopListSection]) -> [ShopListStackEntry] {
        let closed = sections.filter { isCollapsed($0) }
        let open = sections.filter { !isCollapsed($0) }

        let closedEntries = closed.enumerated().map { index, section in
            ShopListStackEntry(
                section: section,
                isExpanded: false,
                overlapsNext: index < closed.count - 1,
                followsExpanded: false,
                precedesExpanded: false
            )
        }
        let openEntries = open.enumerated().map { index, section in
            ShopListStackEntry(
                section: section,
                isExpanded: true,
                overlapsNext: false,
                followsExpanded: index > 0,
                precedesExpanded: index < open.count - 1
            )
        }
        return closedEntries + openEntries
    }

    /// Remembers `section` as the moving card for a moment (see ``movingSectionID``).
    private func markMoving(_ section: ShopListSection) {
        movingSectionID = section.id
        movingResetTask?.cancel()
        movingResetTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.movingSectionID = nil
        }
    }

    /// The housemates `item` is for, resolved against ``houseUsers`` (no network).
    func relatedUsers(for item: ShopListItem) -> [UserModel] {
        item.relatedUsers(in: houseUsers)
    }

    /// Creates an empty view model; data comes from ``HouseDataStore``.
    init() {}

    /// `true` inside Xcode previews. CloudKit can't run there (no iCloud entitlement), and
    /// touching it crashes the preview process, so every method below that would reach the
    /// network works on the in-memory data instead.
    @ObservationIgnored
    private let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

    /// Creates a view model with fixed data, for previews.
    init(previewItems: [ShopListItem], houseUsers: [UserModel] = [], currentUser: UserModel? = nil) {
        self.items = previewItems
        self.houseUsers = houseUsers
        self.houseUserRecords = houseUsers
        self.currentUser = currentUser
        self.hasLoaded = true
    }

    // MARK: - Setup

    /// Whether a snapshot has been applied at least once.
    private(set) var hasLoaded = false

    /// The refresh currently waiting or in flight, if any.
    @ObservationIgnored
    private var refreshTask: Task<Void, Never>?

    /// The snapshot last applied, so the same one is never applied twice.
    @ObservationIgnored
    private var appliedSnapshotID: UUID?

    /// Shows the house data already in memory right away
    func setup() async {
        guard !isPreview else { hasLoaded = true; return }
        if let cached = HouseDataStore.shared.snapshot {
            apply(cached)
        }
        await refresh()
    }

    /// Applies the freshest house data. The store only fetches if its data is stale.
    func refresh() async {
        guard !isPreview else { return }
        let snapshot = await HouseDataStore.shared.loadLatest()
        guard !Task.isCancelled else { return }
        apply(snapshot)
    }

    /// Coalesces refresh requests and cancels the previous one.
    ///
    /// - Parameter debounce: How long to wait for further requests before fetching.
    func requestRefresh(debounce: Duration = .milliseconds(250)) {
        guard !isPreview else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            let snapshot = await HouseDataStore.shared.refreshAfterRemoteChange()
            guard !Task.isCancelled, let self else { return }
            self.apply(snapshot)
        }
    }

    /// Shown when the house has no shopping list.
    private static var missingListMessage: String { L10n.tr("Essa casa ainda não tem uma lista de compras.") }

    /// Replaces the screen's state with `snapshot`, unless it was already applied.
    private func apply(_ snapshot: HouseSnapshot) {
        defer { hasLoaded = true }
        guard !snapshot.isPlaceholder else { return }
        guard snapshot.id != appliedSnapshotID else { return }
        appliedSnapshotID = snapshot.id

        houseUsers = snapshot.users
        houseUserRecords = snapshot.userRecords
        currentUser = snapshot.houseUser

        guard let shopList = snapshot.shopList else {
            list = nil
            items = []
            errorMessage = Self.missingListMessage
            return
        }

        if errorMessage == Self.missingListMessage { errorMessage = nil }
        list = shopList
        items = shopList.belonging(to: snapshot.shopItems)
    }

    /// Adds `item`, or replaces the one with the same id — never creates a duplicate row.
    private func upsert(_ item: ShopListItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
    }

    // MARK: - Gamification

    /// Points a new item is worth: the item itself, its beneficiaries, and a price.
    static func creationScore(beneficiaries: Int, hasPrice: Bool) -> Int {
        var score = ScoreValues.shoppingItemAdded.points
        score += beneficiaries * ScoreValues.shoppingItemBeneficiaryAssigned.points
        if hasPrice { score += ScoreValues.receiptScanned(itemCount: 1).points }
        return score
    }

    // MARK: - Items

    /// Reads a price typed by the user (`,` or `.` as the decimal separator).
    ///
    /// - Returns: The price, or `nil` when the text is empty or isn't a number.
    static func parsePrice(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    /// Most digits a price can have (R$ 9.999.999,99).
    static let maxPriceDigits = 9

    /// Bank-style price entry: the user types only digits and they fill in from the cents, so
    /// `1`, `5`, `0` reads "0,01", "0,15", "1,50". Anything that isn't a digit is ignored.
    static func formatPriceInput(_ text: String) -> String {
        let digits = text.filter(\.isNumber).prefix(maxPriceDigits)
        guard let cents = Int(digits), cents > 0 else { return "" }
        return "\(cents / 100),\(String(format: "%02d", cents % 100))"
    }

    /// The text field content for an already known price.
    static func priceInputText(for value: Double) -> String {
        formatPriceInput(String(Int((value * 100).rounded())))
    }

    /// The required fields that are still empty or invalid. 
    static func missingFields(
        name: String,
        quantity: Int,
        unitMeasurement: UnitMeasurement,
        category: ShopItemCategory?,
        relatedUsers: [UserModel]
    ) -> [ShopItemField] {
        var missing: [ShopItemField] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missing.append(.name) }
        if !QuantityStepper.allowedRange.contains(quantity) { missing.append(.quantity) }
        if unitMeasurement == .undefined { missing.append(.unit) }
        if category == nil { missing.append(.category) }
        if relatedUsers.isEmpty { missing.append(.consumers) }
        return missing
    }

    /// Parses the raw price text and saves the item — creating a new one, or applying edits to
    /// `existingItem` when one is passed.
    ///
    /// - Returns: `true` when the save reached CloudKit.
    @discardableResult
    func saveItem(
        _ existingItem: ShopListItem?,
        name: String,
        valueText: String,
        quantity: Int,
        unitMeasurement: UnitMeasurement,
        category: ShopItemCategory,
        relatedUsers: [UserModel],
        addedBy: UserModel?
    ) async -> Bool {
        let missing = Self.missingFields(
            name: name,
            quantity: quantity,
            unitMeasurement: unitMeasurement,
            category: category,
            relatedUsers: relatedUsers
        )
        if let firstMissing = missing.first {
            errorMessage = firstMissing.warning
            return false
        }

        let value = Self.parsePrice(valueText)

        if isPreview {
            previewSave(existingItem, name: name, value: value, quantity: quantity,
                        unitMeasurement: unitMeasurement, category: category,
                        relatedUsers: relatedUsers, addedBy: addedBy)
            return true
        }

        var score = 0
        let hasNewPrice = (value ?? 0) > 0
        let success: Bool

        if let existingItem {
            let previousUserIDs = Set(existingItem.relatedUsers(in: houseUsers).compactMap(\.recordID))
            let hadPrice = (existingItem.value ?? 0) > 0

            let addedBeneficiaries = relatedUsers.filter { user in
                guard let id = user.recordID else { return false }
                return !previousUserIDs.contains(id)
            }
            score += addedBeneficiaries.count * ScoreValues.shoppingItemBeneficiaryAssigned.points
            if hasNewPrice && !hadPrice {
                score += ScoreValues.receiptScanned(itemCount: 1).points
            }

            success = await updateItem(
                existingItem,
                name: name,
                value: value,
                quantity: quantity,
                unitMeasurement: unitMeasurement,
                category: category,
                relatedUsers: relatedUsers
            )
        } else {
            score = Self.creationScore(
                beneficiaries: relatedUsers.count,
                hasPrice: hasNewPrice
            )

            success = await addItem(
                name: name,
                value: value,
                quantity: quantity,
                unitMeasurement: unitMeasurement,
                category: category,
                relatedUsers: relatedUsers,
                addedBy: addedBy
            )
        }

        if success && score > 0 {
            await ScoreManager.shared.assignScoreForMyUser(score: score)
        }
        return success
    }

    /// Adds a new item to ``list`` and shows it right away (never duplicating a row).
    @discardableResult
    func addItem(
        name: String,
        value: Double? = nil,
        quantity: Int,
        unitMeasurement: UnitMeasurement,
        category: ShopItemCategory = .default,
        relatedUsers: [UserModel] = [],
        addedBy: UserModel?
    ) async -> Bool {
        guard let list else {
            errorMessage = L10n.tr("Lista de compras ainda não carregada.")
            return false
        }

        let relatedUsersReferences = relatedUsers.compactMap { user -> CKRecord.Reference? in
            guard let recordID = user.recordID else { return nil }
            return CKRecord.Reference(recordID: recordID, action: .none)
        }
        let addedByReference = addedBy?.recordID.map { CKRecord.Reference(recordID: $0, action: .none) }

        let draft = ShopListItem(
            name: name,
            value: value,
            quantity: quantity,
            unitMeasurement: unitMeasurement,
            category: category,
            relatedUsers: relatedUsersReferences.isEmpty ? nil : relatedUsersReferences,
            addedByUser: addedByReference
        )

        guard let created = await list.addItem(draft) else {
            errorMessage = CloudKitManager.shared.errorMessage ?? L10n.tr("Erro ao adicionar item.")
            return false
        }

        upsert(created)
        return true
    }

    /// Applies edits made to an existing item and persists them.
    @discardableResult
    func updateItem(
        _ item: ShopListItem,
        name: String,
        value: Double?,
        quantity: Int,
        unitMeasurement: UnitMeasurement,
        category: ShopItemCategory,
        relatedUsers: [UserModel]
    ) async -> Bool {

        guard await item.update(
            name: name,
            value: value,
            quantity: quantity,
            unitMeasurement: unitMeasurement,
            category: category,
            relatedUsers: relatedUsers
        ) else {
            errorMessage = CloudKitManager.shared.errorMessage ?? L10n.tr("Erro ao editar item.")
            return false
        }
        return true
    }

    // MARK: - Buying

    /// An item the user is checking off that has no price yet; the view asks for it first.
    struct PurchasePrompt: Identifiable {
        let item: ShopListItem
        var id: String { item.id }
    }

    /// Set while the "how much was it?" popup should be on screen.
    private(set) var purchasePrompt: PurchasePrompt?

    /// Closes the "how much did you pay?" popup without buying.
    func dismissPurchasePrompt() {
        purchasePrompt = nil
    }

    /// Whether `text` is a price the popup can confirm.
    static func isValidPrice(_ text: String) -> Bool {
        (parsePrice(text) ?? 0) > 0
    }

    /// Checks an item off, or puts it back on the list.
    func toggleBought(_ item: ShopListItem) async {
        if !item.isBought, !item.hasPrice {
            purchasePrompt = PurchasePrompt(item: item)
            return
        }
        await setBought(item, price: nil)
    }

    /// Finishes a purchase started from the price popup.
    ///
    /// - Parameter valueText: The typed price, or `nil` to buy without informing it.
    func confirmPurchase(of item: ShopListItem, valueText: String?) async {
        purchasePrompt = nil

        let price = valueText.flatMap(Self.parsePrice).flatMap { $0 > 0 ? $0 : nil }
        await setBought(item, price: price)
    }

    /// Marks `item` as bought (or not), saving the price paid when given.
    private func setBought(_ item: ShopListItem, price: Double?) async {
        if isPreview {
            if let price { item.value = price }
            item.isBought.toggle()
            item.boughtAt = item.isBought ? Date() : nil // Keep the purchase date in step.
            return
        }

        if item.isBought {
            let buyerID = item.buyerRecordID
            guard await item.toggle() else {
                errorMessage = CloudKitManager.shared.errorMessage ?? L10n.tr("Erro ao editar item.")
                return
            }
            let points = ScoreValues.shoppingItemBought.points
            if let buyerID, let buyer = houseUsers.first(where: { $0.recordID == buyerID }) {
                await ScoreManager.shared.removeScore(score: points, for: buyer)
            }
        } else if let currentUser {
            let didSave = await item.markBought(by: currentUser, value: price)
            guard didSave else {
                errorMessage = CloudKitManager.shared.errorMessage ?? L10n.tr("Erro ao editar item.")
                return
            }

            var points = ScoreValues.shoppingItemBought.points
            if price != nil { points += ScoreValues.receiptScanned(itemCount: 1).points }
            await ScoreManager.shared.assignScoreForMyUser(score: points)
        } else if await item.toggle() == false {
            errorMessage = CloudKitManager.shared.errorMessage ?? L10n.tr("Erro ao editar item.")
        }
    }

    /// Dismisses the error shown by the view.
    func clearError() {
        errorMessage = nil
    }

    /// Removes an item from CloudKit and from ``items``.
    @discardableResult
    func deleteItem(_ item: ShopListItem) async -> Bool {
        guard list != nil || isPreview else { return false }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return true }

        items.remove(at: index)
        if isPreview { return true }

        guard let list, await list.removeItem(item) else {
            errorMessage = CloudKitManager.shared.errorMessage ?? L10n.tr("Erro ao remover item.")
            if !items.contains(where: { $0.id == item.id }) {
                items.insert(item, at: min(index, items.count))
            }
            return false
        }

        if !item.isBought, let me = currentUser?.recordID, item.addedByRecordID == me {
            await ScoreManager.shared.removeScoreForMyUser(score: ScoreValues.shoppingItemAdded.points)
        }
        return true
    }

    // MARK: - Apple Intelligence

    /// Whether the add-item form should offer AI suggestions on this device and language.
    var canSuggestItemDetails: Bool {
        IntelligenceManager.shared.isAvailable
    }

    /// Suggests name, quantity, unit, category, price and who splits the item from a description.
    ///
    /// - Parameters:
    ///   - text: What the person typed in the AI prompt.
    ///   - housemates: Everyone who can share the item (the form's `availableUsers`).
    ///   - currentUser: The person typing.
    ///   - selectedConsumers: Who the form already has selected (for a per-person price with no
    ///     names).
    /// - Returns: `nil` when AI is unavailable, the text is too short, or the request fails.
    func suggestItemDetails(
        for text: String,
        housemates: [UserModel],
        currentUser: UserModel?,
        selectedConsumers: [UserModel]
    ) async -> ShopItemSuggestion? {
        let entry = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard entry.count >= 3 else { return nil }
        return await IntelligenceManager.shared.suggestShopItem(
            for: entry,
            housemates: housemates,
            currentUser: currentUser,
            selectedConsumers: selectedConsumers
        )
    }

    /// A pending item that is the same product as `name`, if any, so the form can offer to add
    /// to its quantity instead of creating a second card.
    func duplicateItem(named name: String) async -> ShopListItem? {
        let candidates = ShopItemDuplicateFinder.candidates(for: name, in: pendingItems)
        for candidate in candidates {
            if ShopItemDuplicateFinder.isExactMatch(name, candidate.name) {
                return candidate
            }
            // Comparing with AI is Premium; the free plan only matches identical names.
            guard PremiumManager.shared.allows(.shopAI) else { continue }
            if await IntelligenceManager.shared.isSameProduct(name, as: candidate.name) == true {
                return candidate
            }
        }
        return nil
    }

    /// The people in `consumers` who aren't sharing `item` yet.
    func newConsumers(_ consumers: [UserModel], for item: ShopListItem) -> [UserModel] {
        let current = Set(item.relatedUsers(in: houseUsers).map(\.id))
        var seen = Set<String>()
        return consumers.filter { !current.contains($0.id) && seen.insert($0.id).inserted }
    }

    /// Merges a new entry into an item already on the list: adds `amount` to its quantity and
    /// adds `consumers` who aren't sharing it yet (for example, the person adding it now when a
    /// housemate created the item). Name, price, unit and category stay as they are.
    @discardableResult
    func merge(into item: ShopListItem, adding amount: Int, consumers: [UserModel]) async -> Bool {
        let range = QuantityStepper.allowedRange
        let people = item.relatedUsers(in: houseUsers) + newConsumers(consumers, for: item)
        return await saveItem(
            item,
            name: item.name,
            valueText: item.value.map(Self.priceInputText(for:)) ?? "",
            quantity: min(item.quantity + amount, range.upperBound),
            unitMeasurement: item.unitMeasurement,
            category: item.category,
            relatedUsers: people,
            addedBy: currentUser
        )
    }

    /// Reads several items from one text for the list page's AI button.
    ///
    /// - Returns: `nil` when AI is unavailable, the text is too short, or the request fails.
    func suggestItems(from text: String) async -> [ShopItemSuggestion]? {
        let entry = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard entry.count >= 3 else { return nil }
        return await IntelligenceManager.shared.suggestShopItems(
            from: entry,
            housemates: houseUsers,
            currentUser: currentUser
        )
    }

    /// Saves reviewed suggestions one by one through ``saveItem(_:name:valueText:quantity:unitMeasurement:category:relatedUsers:addedBy:)``,
    /// so validation and points work exactly as when adding by hand. An item whose people
    /// weren't mentioned is for the whole house. Stops at the first failure, leaving
    /// ``errorMessage`` set.
    ///
    /// - Returns: How many were saved, counted from the start of `suggestions`.
    func addSuggestedItems(_ suggestions: [ShopItemSuggestion]) async -> Int {
        var saved = 0
        for suggestion in suggestions {
            let success = await saveItem(
                nil,
                name: suggestion.name,
                valueText: suggestion.unitPrice.map(Self.priceInputText(for:)) ?? "",
                quantity: suggestion.quantity,
                unitMeasurement: suggestion.unit,
                category: suggestion.category,
                relatedUsers: suggestion.consumers ?? houseUsers,
                addedBy: currentUser
            )
            guard success else { break }
            saved += 1
        }
        return saved
    }

    /// "R$ 12,50 por pessoa": an item's total split equally between `consumerCount` people,
    /// rounded to cents like ``DebtCalculator``. `nil` without a price or without anyone.
    static func shareText(unitPrice: Double?, quantity: Int, consumerCount: Int) -> String? {
        guard let unitPrice, unitPrice > 0, consumerCount > 0 else { return nil }
        let total = unitPrice * Double(quantity)
        let share = (total / Double(consumerCount) * 100).rounded() / 100
        let format = FloatingPointFormatStyle<Double>.Currency(code: "BRL").locale(L10n.locale)
        return L10n.tr("\(share.formatted(format)) por pessoa")
    }

    // MARK: - Previews

    /// What saving does in a preview: the same change as CloudKit would make, in memory only.
    private func previewSave(
        _ existingItem: ShopListItem?,
        name: String,
        value: Double?,
        quantity: Int,
        unitMeasurement: UnitMeasurement,
        category: ShopItemCategory,
        relatedUsers: [UserModel],
        addedBy: UserModel?
    ) {
        let references = relatedUsers.compactMap { user in
            user.recordID.map { CKRecord.Reference(recordID: $0, action: .none) }
        }

        if let existingItem {
            existingItem.name = name
            existingItem.value = value
            existingItem.quantity = quantity
            existingItem.unitMeasurement = unitMeasurement
            existingItem.category = category
            existingItem.relatedUsersReference = references
        } else {
            let item = ShopListItem(
                name: name,
                value: value,
                quantity: quantity,
                unitMeasurement: unitMeasurement,
                category: category,
                relatedUsers: references.isEmpty ? nil : references
            )
            item.recordID = CKRecord.ID(recordName: "preview-item-\(UUID().uuidString)")
            upsert(item)
        }
    }
}
