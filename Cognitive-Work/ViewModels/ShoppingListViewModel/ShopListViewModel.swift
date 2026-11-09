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
    /// What failed, for the error alert's title (e.g. "Não foi possível excluir o cômodo"). Set
    /// together with ``errorMessage``, which says why and what to do.
    private(set) var errorTitle: String?

    /// First day of the house's current gamification season, to know which purchases its points
    /// still count (``HouseCycleModel/currentSeasonStart(_:asOf:calendar:)``).
    @ObservationIgnored
    private var currentCycleStart: Date?

    /// Items still to buy.
    var pendingItems: [ShopListItem] {
        items.filter { !$0.isBought }
    }

    /// Bought items still on the list. The ones whose shares were all paid are hidden here and
    /// deleted right after by ``cleanUpBoughtItems()`` (they no longer count in any debt). The ones
    /// bought with nobody to charge leave it from the day after the purchase (see
    /// ``isFinishedPersonalPurchase(_:now:)``); those stay stored, so the suggestions keep
    /// learning from the purchases.
    var boughtItems: [ShopListItem] {
        items.filter { $0.isBought && !isFullySettled($0) && !isFinishedPersonalPurchase($0) }
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

        let person = personResolver()
        let settled = Set(item.settledUserIDs.map(person))
        let debtors = Set(item.consumerRecordIDs.map(person)).subtracting([person(buyerID)])

        return !debtors.isEmpty && debtors.isSubset(of: settled)
    }
    
    /// Whether `item` was bought by someone for themselves (or for nobody in particular), so
    /// nobody owes anything for it, and it was bought before today.
    ///
    /// ``isFullySettled(_:)`` only takes an item off the list once somebody pays for it, so these
    /// never left "Comprados". They stay there the rest of the day of the purchase (to undo a
    /// check by mistake) and leave the list after that.
    func isFinishedPersonalPurchase(_ item: ShopListItem, now: Date = .now) -> Bool {
        guard item.isBought, let buyerID = item.buyerRecordID else { return false }

        let person = personResolver()
        let debtors = Set(item.consumerRecordIDs.map(person)).subtracting([person(buyerID)])
        guard debtors.isEmpty else { return false }

        let boughtDay = Calendar.current.startOfDay(for: item.boughtAt ?? item.createdAt)
        return boughtDay < Calendar.current.startOfDay(for: now)
    }
    
    /// Turns a user record id into the person it belongs to (`ownerRecordName`), like
    /// ``DebtCalculator``: the same person may have more than one user record.
    private func personResolver() -> (CKRecord.ID) -> String {
        // The signed-in member too: the item may point at their record before the house list
        // has it. Without an account name, the record itself (as in ``DebtCalculator``).
        var ownerByRecord: [String: String] = [:]
        for user in houseUserRecords + houseUsers + [currentUser].compactMap({ $0 }) {
            guard let name = user.recordID?.recordName else { continue }
            ownerByRecord[name] = user.ownerRecordName.isEmpty ? name : user.ownerRecordName
        }
        return { ownerByRecord[$0.recordName] ?? $0.recordName }
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

    /// Pull to refresh: drops the cached house data and fetches it again from CloudKit.
    func forceRefresh() async {
        guard !isPreview else { return }
        let snapshot = await HouseDataStore.shared.refreshAfterRemoteChange()
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
            errorTitle = L10n.tr("Lista de compras indisponível")
            errorMessage = Self.missingListMessage
            return
        }

        if errorMessage == Self.missingListMessage { errorMessage = nil }
        list = shopList
        items = shopList.belonging(to: snapshot.shopItems)
        currentCycleStart = HouseCycleModel.currentSeasonStart(snapshot.cycles, asOf: .now)

        // A debt may have been settled on another device: clear what's fully paid.
        Task { await cleanUpBoughtItems() }
    }

    // MARK: - Bought items and debts

    /// Item ids being removed automatically, so overlapping sweeps don't delete twice.
    @ObservationIgnored
    private var itemsBeingRemoved: Set<String> = []

    /// Who a user record belongs to (their iCloud account), matching ``DebtCalculator``: the
    /// same person can have more than one record, and an item may point at any of them.
    private func person(_ id: CKRecord.ID) -> String {
        let user = (houseUserRecords + houseUsers + [currentUser].compactMap { $0 })
            .first { $0.recordID == id }
        guard let user, !user.ownerRecordName.isEmpty else { return id.recordName }
        return user.ownerRecordName
    }

    /// The housemates of a bought item who share its price with the buyer (everyone it was for,
    /// except the buyer). Empty when the item makes no debt: no price, or only for the buyer.
    private func debtorIDs(of item: ShopListItem) -> [CKRecord.ID] {
        guard item.isBought, item.hasPrice, item.totalValue != nil,
              let buyerID = item.buyerRecordID else { return [] }
        let buyer = person(buyerID)
        return item.consumerRecordIDs.filter { person($0) != buyer }
    }

    /// Whether someone still owes their share of `item`. While this is `true` the item stays in
    /// the "bought" section and can't be deleted by hand: it's what the debts are built from.
    func hasOpenDebt(_ item: ShopListItem) -> Bool {
        // Matched by person, like ``isFullySettled(_:)``: the share may have been paid from
        // another record of the same person.
        let settled = Set(item.settledUserIDs.map(person))
        return debtorIDs(of: item).contains { !settled.contains(person($0)) }
    }

    /// Whether `item` can be deleted by hand. A bought item can't while someone still owes for
    /// it (unmarking it as bought brings it back to the list, where it can be deleted).
    func canDelete(_ item: ShopListItem) -> Bool {
        !hasOpenDebt(item)
    }

    /// Deletes every bought item whose debt is fully settled: once nobody owes anything for it,
    /// it leaves the "bought" section by itself. Called after a settlement and on every load.
    func cleanUpBoughtItems() async {
        guard list != nil, !isPreview else { return }
        let done = items.filter { isFullySettled($0) && !itemsBeingRemoved.contains($0.id) && $0.recordID != nil }
        guard !done.isEmpty else { return }

        let doneIDs = Set(done.map(\.id))
        itemsBeingRemoved.formUnion(doneIDs)
        defer { itemsBeingRemoved.subtract(doneIDs) }

        // One delete request per zone (in practice, one for the whole house), so every item
        // leaves the list at the same time instead of one by one.
        var removedIDs: Set<String> = []
        let itemsByZone = Dictionary(grouping: done) { $0.recordID!.zoneID }
        for (zoneID, zoneItems) in itemsByZone {
            // Silent: a failure just leaves the items there until the next load tries again.
            guard await CloudKitManager.shared.delete(
                recordIDs: zoneItems.compactMap(\.recordID),
                zoneID: zoneID
            ) else { continue }
            removedIDs.formUnion(zoneItems.map(\.id))
        }
        items.removeAll { removedIDs.contains($0.id) }
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

    /// The house member with record `id`, among every user record of the house.
    private func houseUser(withID id: CKRecord.ID?) -> UserModel? {
        guard let id else { return nil }
        return houseUserRecords.first { $0.recordID == id } ?? houseUsers.first { $0.recordID == id }
    }

    /// Takes back the points of a purchase: the buyer's and the one paid to whoever added the item.
    ///
    /// Purchases saved before ``ShopListItem/awardedPoints`` existed paid the one who added the
    /// item when it was added, not when it was bought, so only the buyer's points (recomputed)
    /// are taken back from those.
    ///
    /// - Parameters:
    ///   - awarded: The item's ``ShopListItem/awardedPoints`` before it was un-bought or deleted.
    ///   - hasPrice: Whether the item had a price, for purchases without `awarded`.
    ///   - buyerID: Who bought it.
    ///   - adderID: Who added it to the list.
    private func takeBackPurchasePoints(
        awarded: Int?,
        hasPrice: Bool,
        buyerID: CKRecord.ID?,
        adderID: CKRecord.ID?
    ) async {
        let scoreManager = ScoreManager.shared

        if let buyer = houseUser(withID: buyerID) {
            let buyerPoints = awarded ?? ScoreValues.shoppingPurchase(hasPrice: hasPrice)
            await scoreManager.removeScore(score: buyerPoints, for: buyer)
        }
        if awarded != nil, let adder = houseUser(withID: adderID) {
            await scoreManager.removeScore(score: ScoreValues.shoppingItemAdded.points, for: adder)
        }
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

    /// the price of one unit derived from the total, shown under the price fields.
    /// `nil` when it would only repeat the total (a single unit or package) or when there is no price.
    static func unitPriceText(total: Double?, quantity: Int, unit: UnitMeasurement) -> String? {
        guard let total,
              let unitPrice = ShopListItem.unitPrice(total: total, quantity: quantity, unit: unit)
        else { return nil }
        // One piece or package costs the total itself; nothing to add.
        if unitPrice.unit.dimension == .count, quantity == 1 { return nil }
        let format = FloatingPointFormatStyle<Double>.Currency(code: "BRL").locale(L10n.locale)
        let price = unitPrice.amount.formatted(format)
        let unitName = unitPrice.unit.getDisplayName(for: 1)
        return L10n.tr("\(price) por \(unitName)")
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

    /// Parses the raw price text (the total paid for the whole item) and saves the item —
    /// creating a new one, or applying edits to `existingItem` when one is passed.
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
            errorTitle = L10n.tr("Faltam informações do item")
            errorMessage = firstMissing.warning
            return false
        }

        let totalPrice = Self.parsePrice(valueText)

        if isPreview {
            previewSave(existingItem, name: name, totalPrice: totalPrice, quantity: quantity,
                        unitMeasurement: unitMeasurement, category: category,
                        relatedUsers: relatedUsers, addedBy: addedBy)
            return true
        }

        // No points here: an item pays when it is bought (see `setBought(_:price:)`), so filling
        // the list, or editing items, can't be repeated for points.
        let success: Bool

        if let existingItem {
            success = await updateItem(
                existingItem,
                name: name,
                totalPrice: totalPrice,
                quantity: quantity,
                unitMeasurement: unitMeasurement,
                category: category,
                relatedUsers: relatedUsers
            )
        } else {
            success = await addItem(
                name: name,
                totalPrice: totalPrice,
                quantity: quantity,
                unitMeasurement: unitMeasurement,
                category: category,
                relatedUsers: relatedUsers,
                addedBy: addedBy
            )
        }

        return success
    }

    /// Adds a new item to ``list`` and shows it right away (never duplicating a row).
    @discardableResult
    func addItem(
        name: String,
        totalPrice: Double? = nil,
        quantity: Int,
        unitMeasurement: UnitMeasurement,
        category: ShopItemCategory = .default,
        relatedUsers: [UserModel] = [],
        addedBy: UserModel?
    ) async -> Bool {
        guard let list else {
            errorTitle = L10n.tr("Não foi possível adicionar o item")
            errorMessage = L10n.tr("A lista de compras ainda não carregou. Aguarde um instante e tente novamente.")
            return false
        }

        let relatedUsersReferences = relatedUsers.compactMap { user -> CKRecord.Reference? in
            guard let recordID = user.recordID else { return nil }
            return CKRecord.Reference(recordID: recordID, action: .none)
        }
        let addedByReference = addedBy?.recordID.map { CKRecord.Reference(recordID: $0, action: .none) }

        let draft = ShopListItem(
            name: name,
            totalPrice: totalPrice,
            quantity: quantity,
            unitMeasurement: unitMeasurement,
            category: category,
            relatedUsers: relatedUsersReferences.isEmpty ? nil : relatedUsersReferences,
            addedByUser: addedByReference
        )

        guard let created = await list.addItem(draft) else {
            errorTitle = L10n.tr("Não foi possível adicionar o item")
            errorMessage = CloudKitManager.shared.errorMessage ?? L10n.tr("Verifique sua conexão e tente novamente.")
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
        totalPrice: Double?,
        quantity: Int,
        unitMeasurement: UnitMeasurement,
        category: ShopItemCategory,
        relatedUsers: [UserModel]
    ) async -> Bool {

        guard await item.update(
            name: name,
            totalPrice: totalPrice,
            quantity: quantity,
            unitMeasurement: unitMeasurement,
            category: category,
            relatedUsers: relatedUsers
        ) else {
            errorTitle = L10n.tr("Não foi possível salvar o item")
            errorMessage = CloudKitManager.shared.errorMessage ?? L10n.tr("Verifique sua conexão e tente novamente.")
            return false
        }
        return true
    }

    // MARK: - Buying

    /// An item the user is checking off; the view asks for its price first (or, when it already
    /// has one, asks the user to confirm or change it).
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
    ///
    /// Checking off always opens the price popup: empty when the item has no price, filled in
    /// with the current price otherwise, so the user can confirm it or correct it.
    func toggleBought(_ item: ShopListItem) async {
        if !item.isBought {
            purchasePrompt = PurchasePrompt(item: item)
            return
        }
        await setBought(item, price: nil)
    }

    /// Finishes a purchase started from the price popup.
    ///
    /// - Parameter valueText: The typed total, or `nil` to buy without a price ("Comprar sem
    ///   valor"), which also removes a price the item already had.
    func confirmPurchase(of item: ShopListItem, valueText: String?) async {
        purchasePrompt = nil

        let price = valueText.flatMap(Self.parsePrice).flatMap { $0 > 0 ? $0 : nil }
        await setBought(item, price: price, clearsPrice: valueText == nil)
    }

    /// Marks `item` as bought (or not), saving the total paid when given.
    ///
    /// - Parameter clearsPrice: When buying, removes the item's current price first, so it's
    ///   bought without a value (no debts are created for it).
    private func setBought(_ item: ShopListItem, price: Double?, clearsPrice: Bool = false) async {
        if isPreview {
            if clearsPrice { item.totalPrice = nil }
            if let price { item.totalPrice = price }
            item.isBought.toggle()
            item.boughtAt = item.isBought ? Date() : nil // Keep the purchase date in step.
            return
        }

        if item.isBought {
            // Read before the toggle clears the purchase.
            let awarded = item.awardedPoints
            let buyerID = item.buyerRecordID
            guard await item.toggle() else {
                errorTitle = L10n.tr("Não foi possível atualizar a compra")
                errorMessage = CloudKitManager.shared.errorMessage ?? L10n.tr("Verifique sua conexão e tente novamente.")
                return
            }
            // Unchecked before the trip's notification went out: nobody hears about it.
            BoughtItemsNotifier.shared.remove(item)
            await takeBackPurchasePoints(
                awarded: awarded,
                hasPrice: item.hasPrice,
                buyerID: buyerID,
                adderID: item.addedByRecordID
            )
        } else if let currentUser {
            // "Comprar sem valor" on an item that had a price: drop it before saving, so the
            // record is saved without it. Restored below if the save fails.
            let previousPrice = item.totalPrice
            if clearsPrice { item.totalPrice = nil }

            // The buyer is paid for the purchase (and for recording the price); whoever added the
            // item is paid now too, since the item turned out to be needed.
            let points = ScoreValues.shoppingPurchase(hasPrice: price != nil || item.hasPrice)
            let didSave = await item.markBought(by: currentUser, totalPrice: price, awarding: points)
            guard didSave else {
                item.totalPrice = previousPrice
                errorTitle = L10n.tr("Não foi possível atualizar a compra")
                errorMessage = CloudKitManager.shared.errorMessage ?? L10n.tr("Verifique sua conexão e tente novamente.")
                return
            }

            notifyItemBought(item, by: currentUser)
            
            await ScoreManager.shared.assignScore(score: points, for: currentUser)
            if let adder = houseUser(withID: item.addedByRecordID) {
                await ScoreManager.shared.assignScore(score: ScoreValues.shoppingItemAdded.points, for: adder)
            }
        } else if await item.toggle() == false {
            errorTitle = L10n.tr("Não foi possível atualizar a compra")
            errorMessage = CloudKitManager.shared.errorMessage ?? L10n.tr("Verifique sua conexão e tente novamente.")
        }
    }

    /// Puts `item` in this shopping trip's notifications. Not sent right away: the items of
    /// one trip go out together, once it's over (see ``BoughtItemsNotifier``), through
    /// ``notifyPurchase(_:by:)``.
    private func notifyItemBought(_ item: ShopListItem, by buyer: UserModel) {
        BoughtItemsNotifier.shared.add(item, by: buyer) { [self] items, buyer in
            await notifyPurchase(items, by: buyer, fromReceipt: false)
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
        // The screen hides the option, but this is what keeps the debts safe.
        guard canDelete(item) else {
            errorTitle = L10n.tr("Este item ainda tem pendências")
            errorMessage = L10n.tr("Itens comprados saem da lista sozinhos quando todos pagarem a sua parte. Se ele foi marcado por engano, desmarque como comprado para poder excluir.")
            return false
        }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return true }

        items.remove(at: index)
        if isPreview { return true }

        guard let list, await list.removeItem(item) else {
            errorTitle = L10n.tr("Não foi possível excluir o item")
            errorMessage = CloudKitManager.shared.errorMessage ?? L10n.tr("Verifique sua conexão e tente novamente.")
            if !items.contains(where: { $0.id == item.id }) {
                items.insert(item, at: min(index, items.count))
            }
            return false
        }

        // An item bought in this cycle and then deleted takes its purchase points back, so buying
        // and deleting items can't be repeated for points. Items not bought never paid anything;
        // purchases of a closed cycle were already counted in it.
        if item.isBought, isInCurrentCycle(item.boughtAt) {
            await takeBackPurchasePoints(
                awarded: item.awardedPoints,
                hasPrice: item.hasPrice,
                buyerID: item.buyerRecordID,
                adderID: item.addedByRecordID
            )
        }
        return true
    }

    // MARK: - Scanned receipt

    /// A list item and what the receipt says was paid for it (lines linked to the same item
    /// already added up).
    struct ReceiptPurchase {
        let item: ShopListItem
        let total: Double
        /// The weight actually bought, for a weighed product ("500 g" on the list, 0,364 kg on
        /// the receipt): the item's quantity becomes it. `nil` keeps the quantity.
        var amount: (quantity: Int, unit: UnitMeasurement)? = nil
        /// Who it's for, when the person changed it on the review screen. `nil` keeps the
        /// item's people.
        var consumers: [UserModel]? = nil
    }

    /// A product read from a receipt that wasn't on the list, to add already bought.
    struct ReceiptNewItem {
        let name: String
        let total: Double
        let quantity: Int
        let unit: UnitMeasurement
        /// Who it's for; empty means the whole house.
        let consumers: [UserModel]
        /// The aisle it goes in.
        var category: ShopItemCategory = .other
    }

    /// The aisle of the latest item the house has with this exact name, unless it's "Outros",
    /// for a product read from a receipt (same words, ignoring case and accents).
    func receiptCategory(named name: String) -> ShopItemCategory? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return items
            .filter { item in
                item.category != .other && ShopItemDuplicateFinder.isExactMatch(trimmed, item.name)
            }
            .max { ($0.boughtAt ?? $0.createdAt) < ($1.boughtAt ?? $1.createdAt) }?
            .category
    }

    /// What the house called products it scanned before (see ``ReceiptNameMemory``).
    var receiptNameMemory: [String: String] {
        list?.receiptNames ?? [:]
    }

    /// Remembers names for the next receipts. Failing only loses the shortcut, so it's silent.
    func rememberReceiptNames(_ names: [String: String]) async {
        guard !isPreview, !names.isEmpty else { return }
        await list?.rememberReceiptNames(names)
    }

    /// The items a receipt line can be linked to: only the ones still to buy (what's already
    /// in "Comprados" was bought before, not with this receipt).
    var receiptLinkableItems: [ShopListItem] {
        pendingItems
    }

    /// Applies a receipt the person reviewed. List items are checked off by the signed-in user
    /// with the price paid (one a housemate bought meanwhile is left as it is), and products that weren't
    /// on the list are added already bought, for who the person chose (the whole house when
    /// nobody, like ``addSuggestedItems(_:)``).
    ///
    /// Fast, so the review screen closes soon: the list items go in one request and the new
    /// items in another, all or nothing each (``errorMessage`` is set when one fails). The
    /// points, the notifications (``notifyPurchase(_:by:)``) and the like run afterwards, in
    /// the background.
    ///
    /// - Returns: How many purchases and new items were saved.
    func applyReceipt(purchases: [ReceiptPurchase], newItems: [ReceiptNewItem]) async -> Int {
        guard let currentUser, let buyerID = currentUser.recordID else {
            errorMessage = L10n.tr("Erro ao editar item.")
            return 0
        }
        var saved = 0
        var failed = false
        // The items this receipt bought, for the points and the notifications.
        var bought: [ShopListItem] = []
        // The signed-in user's points, and the points of who added the list items, by record.
        var myPoints = 0
        var adderPoints: [String: (user: UserModel, points: Int)] = [:]

        // MARK: List items: one request
        var checkedOff: [(item: ShopListItem, points: Int, undo: () -> Void)] = []
        for purchase in purchases {
            let item = purchase.item
            let price = purchase.total > 0 ? purchase.total : nil

            if isPreview {
                if let price { item.totalPrice = price }
                if let amount = purchase.amount, !item.isBought {
                    item.quantity = amount.quantity
                    item.unitMeasurement = amount.unit
                }
                if let people = purchase.consumers, !item.isBought {
                    item.relatedUsersReference = people.compactMap { user in
                        user.recordID.map { CKRecord.Reference(recordID: $0, action: .none) }
                    }
                }
                if !item.isBought {
                    item.isBought = true
                    item.boughtAt = Date()
                }
                saved += 1
                continue
            }

            // Bought by a housemate while the receipt was being reviewed: theirs stays.
            if item.isBought {
                saved += 1
                continue
            }
            // The amount bought and who it's for go in the same save as the purchase.
            let previousAmount = (item.quantity, item.unitMeasurement)
            let previousPeople = item.relatedUsersReference
            if let amount = purchase.amount {
                item.quantity = amount.quantity
                item.unitMeasurement = amount.unit
            }
            if let people = purchase.consumers {
                let references = people.compactMap { user in
                    user.recordID.map { CKRecord.Reference(recordID: $0, action: .none) }
                }
                if !references.isEmpty { item.relatedUsersReference = references }
            }
            // Same scoring as `setBought`: the buyer's points are saved in `awardedPoints`
            // so un-buying takes back exactly them, and the adder is paid now.
            let purchasePoints = ScoreValues.shoppingPurchase(hasPrice: price != nil || item.hasPrice)
            let undoPurchase = item.markBoughtLocally(by: buyerID, totalPrice: price, awarding: purchasePoints)
            checkedOff.append((item, purchasePoints, {
                undoPurchase()
                (item.quantity, item.unitMeasurement) = previousAmount
                item.relatedUsersReference = previousPeople
            }))
        }
        if !checkedOff.isEmpty {
            if await CloudKitManager.shared.batchUpdate(checkedOff.map(\.item)) {
                for entry in checkedOff {
                    bought.append(entry.item)
                    myPoints += entry.points
                    if let adder = houseUser(withID: entry.item.addedByRecordID) {
                        if adder.ownerRecordName == currentUser.ownerRecordName {
                            myPoints += ScoreValues.shoppingItemAdded.points
                        } else if let key = adder.recordID?.recordName {
                            adderPoints[key, default: (adder, 0)].points += ScoreValues.shoppingItemAdded.points
                        }
                    }
                    saved += 1
                }
            } else {
                checkedOff.forEach { $0.undo() }
                failed = true
            }
        }

        // MARK: New items: one request
        let house = houseUsers.compactMap { user in
            user.recordID.map { CKRecord.Reference(recordID: $0, action: .none) }
        }
        let me = CKRecord.Reference(recordID: buyerID, action: .none)
        var drafts: [ShopListItem] = []
        for newItem in newItems {
            let chosen = newItem.consumers.compactMap { user in
                user.recordID.map { CKRecord.Reference(recordID: $0, action: .none) }
            }
            let people = chosen.isEmpty ? house : chosen
            let draft = ShopListItem(
                name: newItem.name,
                totalPrice: newItem.total > 0 ? newItem.total : nil,
                quantity: newItem.quantity,
                unitMeasurement: newItem.unit,
                isBought: true,
                category: newItem.category,
                relatedUsers: people.isEmpty ? nil : people,
                addedByUser: me,
                buyerUser: me
            )
            draft.boughtAt = Date()
            // Bought on creation: saved like any purchase so un-buying takes these points back.
            draft.awardedPoints = ScoreValues.shoppingPurchase(hasPrice: newItem.total > 0)

            if isPreview {
                draft.recordID = CKRecord.ID(recordName: "preview-item-\(UUID().uuidString)")
                upsert(draft)
                saved += 1
                continue
            }
            drafts.append(draft)
        }
        if !drafts.isEmpty {
            if let listID = list?.recordID {
                // Created like `ShopListModel.addItem`: in the list's zone, with the list as parent.
                let parent = CKRecord.Reference(recordID: listID, action: .none)
                let records = drafts.map { draft -> CKRecord in
                    let recordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: listID.zoneID)
                    let record = CKRecord(recordType: ShopListItem.recordType, recordID: recordID)
                    draft.populate(record: record)
                    record.parent = parent
                    draft.recordID = recordID
                    return record
                }
                if await CloudKitManager.shared.batchSave(records: records, zoneID: listID.zoneID) {
                    CloudKitManager.shared.invalidateSessionCacheIfNeeded(for: ShopListItem.self)
                    for draft in drafts {
                        draft.listRecordID = listID
                        upsert(draft)
                        bought.append(draft)
                        // The current user both added and bought it: purchase points + the adder's points.
                        myPoints += (draft.awardedPoints ?? 0) + ScoreValues.shoppingItemAdded.points
                        saved += 1
                    }
                } else {
                    drafts.forEach { $0.recordID = nil }
                    failed = true
                }
            } else {
                failed = true
            }
        }

        if failed {
            errorMessage = CloudKitManager.shared.errorMessage ?? L10n.tr("Não foi possível salvar todos os itens.")
        }

        // MARK: Afterwards, in the background
        guard !isPreview else { return saved }
        let adders = Array(adderPoints.values)
        let points = myPoints
        Task {
            if points > 0 {
                await ScoreManager.shared.assignScoreForMyUser(score: points)
            }
            for adder in adders {
                await ScoreManager.shared.assignScore(score: adder.points, for: adder.user)
            }
            // A receipt is the whole trip: no waiting like the items checked off on the list.
            await notifyPurchase(bought, by: currentUser, fromReceipt: true)
        }
        return saved
    }

    /// Tells the housemates about one shopping trip: a scanned receipt, or the items checked
    /// off on the list in a row (``BoughtItemsNotifier``).
    ///
    /// Only who has something to pay hears about it: one notification each, with what was
    /// bought for them and their part, added up like "Pendências" does (``DebtCalculator``, so
    /// the amounts match). Who added an item without paying for it isn't told.
    ///
    /// - Parameter fromReceipt: Bought with a scanned receipt (the receipt's icon instead of the
    ///   cart).
    private func notifyPurchase(_ bought: [ShopListItem], by buyer: UserModel, fromReceipt: Bool) async {
        guard !bought.isEmpty, !isPreview else { return }
        let buyerPerson = buyer.ownerRecordName

        // Their part of this trip only, by person: one person may have more than one record.
        let ledger = DebtCalculator.ledger(
            items: bought,
            users: houseUsers,
            userRecords: houseUserRecords,
            me: buyer
        )
        var shares: [String: Double] = [:]
        for group in ledger.owedToYou {
            shares[group.counterparty.ownerRecordName, default: 0] += group.total
        }

        // What each of them shares, in the order it was bought.
        var order: [String] = []
        var shared: [String: (member: UserModel, names: [String])] = [:]
        for item in bought {
            for id in item.consumerRecordIDs {
                // Every record of the house, not just one per person: the item may point at any.
                guard let member = houseUser(withID: id),
                      !member.ownerRecordName.isEmpty, member.ownerRecordName != buyerPerson
                else { continue }
                let key = member.ownerRecordName
                if shared[key] == nil {
                    shared[key] = (member, [])
                    order.append(key)
                }
                if !(shared[key]?.names.contains(item.name) ?? true) {
                    shared[key]?.names.append(item.name)
                }
            }
        }

        for key in order {
            // Nothing to pay (no prices): nothing to tell.
            guard let entry = shared[key], let share = shares[key], share > 0 else { continue }
            #if DEBUG
            print("[BoughtItems] telling \(entry.member.name): \(entry.names), \(share)")
            #endif
            await NotificationManager.shared.notifyBoughtForYou(
                entry.names,
                share: share.formatted(.currency(code: "BRL").locale(L10n.locale)),
                by: buyer.name,
                to: entry.member,
                fromReceipt: fromReceipt
            )
        }
    }

    /// Whether `date` falls in the house's current season (any date does before the first one ends).
    private func isInCurrentCycle(_ date: Date?) -> Bool {
        guard let date else { return false }
        guard let currentCycleStart else { return true }
        return date >= currentCycleStart
    }

    // MARK: - Apple Intelligence

    /// Whether the add-item form should offer AI suggestions on this device and language.
    var canSuggestItemDetails: Bool {
        IntelligenceManager.shared.isAvailable && PremiumManager.shared.allows(.intelligence)
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
    /// The latest item with the same name that had a price, to offer it again ("Última vez:
    /// R$ 25,00"). Plain code over the house's items (no AI): same words, ignoring case and
    /// accents; bought items count by when they were bought.
    ///
    /// - Parameter excluding: The item being edited, so it doesn't suggest its own price.
    func lastPricedItem(named name: String, excluding excluded: ShopListItem? = nil) -> ShopListItem? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return items
            .filter { item in
                item.hasPrice
                    && item.id != excluded?.id
                    && ShopItemDuplicateFinder.isExactMatch(trimmed, item.name)
            }
            .max { ($0.boughtAt ?? $0.createdAt) < ($1.boughtAt ?? $1.createdAt) }
    }

    func duplicateItem(named name: String) async -> ShopListItem? {
        let candidates = ShopItemDuplicateFinder.candidates(for: name, in: pendingItems)
        for candidate in candidates {
            if ShopItemDuplicateFinder.isExactMatch(name, candidate.name) {
                return candidate
            }
            // Comparing with AI is Premium; the free plan only matches identical names.
            guard PremiumManager.shared.allows(.intelligence) else { continue }
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
    /// housemate created the item). Name, unit and category stay as they are; a known total
    /// grows with the quantity, so the price of one unit stays the same.
    @discardableResult
    func merge(into item: ShopListItem, adding amount: Int, consumers: [UserModel]) async -> Bool {
        let range = QuantityStepper.allowedRange
        let people = item.relatedUsers(in: houseUsers) + newConsumers(consumers, for: item)
        let quantity = min(item.quantity + amount, range.upperBound)
        let total = item.totalValue.map { $0 * Double(quantity) / Double(max(item.quantity, 1)) }
        return await saveItem(
            item,
            name: item.name,
            valueText: total.map(Self.priceInputText(for:)) ?? "",
            quantity: quantity,
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
                valueText: suggestion.totalPrice.map(Self.priceInputText(for:)) ?? "",
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
    static func shareText(total: Double?, consumerCount: Int) -> String? {
        guard let total, total > 0, consumerCount > 0 else { return nil }
        let share = (total / Double(consumerCount) * 100).rounded() / 100
        let format = FloatingPointFormatStyle<Double>.Currency(code: "BRL").locale(L10n.locale)
        return L10n.tr("\(share.formatted(format)) por pessoa")
    }

    // MARK: - Previews

    /// What saving does in a preview: the same change as CloudKit would make, in memory only.
    private func previewSave(
        _ existingItem: ShopListItem?,
        name: String,
        totalPrice: Double?,
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
            existingItem.totalPrice = totalPrice
            existingItem.quantity = quantity
            existingItem.unitMeasurement = unitMeasurement
            existingItem.category = category
            existingItem.relatedUsersReference = references
        } else {
            let item = ShopListItem(
                name: name,
                totalPrice: totalPrice,
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
