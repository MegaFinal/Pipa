//
//  SharedImportViewModel.swift
//  Cognitive-Work
//
//  Created by anshu Li on 18/11/26.
//

import Foundation
import CloudKit

/// What a chore shared from another app fills in the chore form: by hand (free) or with the
/// on-device model (Premium).
struct ChoreImportPrefill {
    /// The chore's name, already short enough for the form.
    let name: String
    /// The day written in the text ("amanhã"), read by code.
    let date: Date?
    /// The room picked on the import card, if any.
    let room: RoomModel?
    /// What the AI read from the line (Premium); `nil` on the free plan.
    let suggestion: ChoreSuggestion?
}

/// Drives ``SharedImportView``: turns a text shared from another app into shopping and chore
/// cards, lets the person fix them, and saves the ones they keep.
///
/// Free: plain code reads name and amount (shopping) or name and day (chores), see
/// ``SharedTextReader``. Premium: the on-device model fills every field from each line, the same
/// way as "Adicionar com IA" and the chore form. Saving goes through the usual paths
/// (``ShopListViewModel/addSuggestedItems(_:)`` and ``CreateAndEditChoreViewModel/confirm()``),
/// so validation, points and notifications are the same as adding by hand.
@MainActor
@Observable
final class SharedImportViewModel {

    // MARK: - Cards

    /// A proposed shopping item.
    struct ShopCard: Identifiable {
        let id = UUID()
        var suggestion: ShopItemSuggestion
        var isIncluded = true
        /// Filled by the AI (shows ✨).
        var isFromAI: Bool
        /// Category not chosen yet (free plan: the person picks it in the item form).
        var needsCategory: Bool
        /// People not chosen yet (free plan: the person picks them in the item form).
        var needsPeople: Bool
        /// The same product already on the list, if any.
        var duplicate: ShopListItem?
        /// Adds the quantity to ``duplicate`` instead of creating a new item.
        var addsToDuplicate = false

        /// Read by plain code: name and amount only; category and people are for the person.
        init(plain suggestion: ShopItemSuggestion) {
            self.suggestion = suggestion
            self.isFromAI = false
            self.needsCategory = true
            self.needsPeople = true
        }

        /// Read by the AI: every field filled (people not said means the whole house, as in
        /// "Adicionar com IA").
        init(ai suggestion: ShopItemSuggestion) {
            self.suggestion = suggestion
            self.isFromAI = true
            self.needsCategory = false
            self.needsPeople = false
        }

        var isComplete: Bool { !needsCategory && !needsPeople }
    }

    /// A proposed chore. Its fields live in a chore form's view model (``form``), filled from
    /// the shared line and completed in ``CreateAndEditChoreView``; it's saved with the rest.
    struct ChoreCard: Identifiable {
        let id = UUID()
        /// The shared line it came from.
        let line: String
        /// The new chore's form, already loaded and filled.
        let form: CreateAndEditChoreViewModel
        /// Read by the AI (shows ✨).
        let isFromAI: Bool
        var isIncluded = true
        /// A chore with the same name that already exists.
        var duplicate: ChoreModel?
        /// The existing chore's form, made when the person picks it instead of a new one.
        var existingForm: CreateAndEditChoreViewModel?
        /// Changes the existing chore (``duplicate``) instead of creating a new one, like "Somar"
        /// on a repeated shopping item.
        var usesExisting = false

        /// The form the card shows, opens and saves: the existing chore's or the new one's.
        var activeForm: CreateAndEditChoreViewModel {
            usesExisting ? (existingForm ?? form) : form
        }

        var name: String { activeForm.draft.name }
        var room: RoomModel? { activeForm.draft.room }
        var date: Date? { activeForm.selectedDate }
        var frequency: Recurrence { activeForm.draft.frequency }

        /// Name, room and day (daily chores need no day): what the form asks before saving. An
        /// existing chore always has them.
        var isComplete: Bool {
            activeForm.hasValidName && activeForm.hasRoom && activeForm.hasDate
        }
    }

    // MARK: - State

    /// The shared text being read.
    let entry: SharedInbox.Entry
    /// The text, editable from the page ("Editar texto") before reading it again.
    var text: String

    /// Loads and saves shopping items (its own instance; the tabs refresh after saving).
    let shopList = ShopListViewModel()
    /// Loads rooms, members and chores, and saves chores.
    let choresModel = CarouselViewModel()

    private(set) var shopCards: [ShopCard] = []
    private(set) var choreCards: [ChoreCard] = []

    private(set) var isLoading = true
    private(set) var isReading = false
    private(set) var isSaving = false
    /// Shown above the cards: nothing found, or a save that failed.
    var errorText: String?
    /// Whether the cards were filled by the AI (for the ✨ on the shared text).
    private(set) var didReadWithAI = false

    /// Whether anything was saved, so the tabs reload when the page closes.
    private(set) var didSaveAnything = false

    init(entry: SharedInbox.Entry) {
        self.entry = entry
        self.text = entry.text
    }

    // MARK: - Derived

    /// Premium and a device that can run the model.
    var usesAI: Bool {
        IntelligenceManager.shared.isAvailable && PremiumManager.shared.allows(.intelligence)
    }

    var houseUsers: [UserModel] { choresModel.userModels }

    /// Rooms a chore can go to ("Casa" is the house itself, not a room to pick).
    var rooms: [RoomModel] { choresModel.roomModels.filter { $0.name != "Casa" } }

    /// Whether the shopping list exists (a house without a list can't take items).
    var canAddShopping: Bool { shopList.canAddItems }

    /// Ticked cards; the ✓ button is enabled when there's at least one.
    var includedCount: Int {
        shopCards.filter(\.isIncluded).count + choreCards.filter(\.isIncluded).count
    }

    var isEmpty: Bool { shopCards.isEmpty && choreCards.isEmpty }

    // MARK: - Loading

    /// Loads the house (same cached data as the tabs) and reads the text.
    func start() async {
        isLoading = true
        await shopList.setup()
        await choresModel.fetchAllData()
        isLoading = false
        await read()
    }

    /// Turns the text into cards. Free: plain code. Premium: the on-device model, with the
    /// plain-code result for any line it can't read.
    func read() async {
        isReading = true
        errorText = nil
        defer { isReading = false }

        let lines = SharedTextReader.lines(in: text)
        let shopLines = lines.filter { $0.kind == .shopping }.map { $0.text }
        let choreLines = lines.filter { $0.kind == .chore }.map { $0.text }
        didReadWithAI = usesAI

        let newShop: [ShopCard]
        if didReadWithAI && !shopLines.isEmpty {
            newShop = await aiShopCards(for: shopLines)
        } else {
            newShop = shopLines.map { ShopCard(plain: SharedTextReader.shopItem(from: $0)) }
        }

        var newChores: [ChoreCard] = []
        for line in choreLines {
            newChores.append(await choreCard(for: line))
        }

        shopCards = newShop
        choreCards = newChores

        if isEmpty {
            errorText = L10n.tr("Nenhum item encontrado. Tente escrever de outro jeito.")
        }
        await checkDuplicates()
    }

    /// The model reads at most 10 items at a time ("Adicionar com IA"), so long lists go in
    /// small groups. A group it can't read falls back to plain code.
    private func aiShopCards(for lines: [String]) async -> [ShopCard] {
        var cards: [ShopCard] = []
        var start = 0
        while start < lines.count {
            let group = Array(lines[start..<min(start + 8, lines.count)])
            start += group.count
            if let items = await shopList.suggestItems(from: group.joined(separator: "\n")), !items.isEmpty {
                cards += items.map { ShopCard(ai: $0) }
            } else {
                cards += group.map { ShopCard(plain: SharedTextReader.shopItem(from: $0)) }
            }
        }
        return cards
    }

    /// One chore card: a chore form loaded and filled with the model's reading on Premium, or
    /// with name and day read by code otherwise.
    private func choreCard(for line: String) async -> ChoreCard {
        let form = CreateAndEditChoreViewModel(
            originalModel: Self.newChoreModel(),
            availableHouseUsers: houseUsers,
            carouselViewModel: choresModel
        )
        await form.load()

        var suggestion: ChoreSuggestion?
        if usesAI {
            suggestion = await IntelligenceManager.shared.suggestChore(
                for: line,
                rooms: rooms,
                housemates: houseUsers,
                currentUser: choresModel.dashboardUser
            )
        }
        let plain = SharedTextReader.chore(from: line)
        form.fill(with: ChoreImportPrefill(
            name: suggestion?.name ?? plain.name,
            date: suggestion?.date ?? plain.date,
            room: suggestion?.room,
            suggestion: suggestion
        ))

        var card = ChoreCard(line: line, form: form, isFromAI: suggestion != nil)
        card.duplicate = existingChore(named: card.name)
        return card
    }

    // MARK: - Repeated items

    /// Marks cards whose item or chore is already there. Repeated chores start unticked.
    private func checkDuplicates() async {
        for card in shopCards {
            let existing = await shopList.duplicateItem(named: card.suggestion.name)
            guard let index = shopCards.firstIndex(where: { $0.id == card.id }) else { continue }
            shopCards[index].duplicate = existing
        }
    }

    /// A chore with the same name (ignoring case, accents and small words).
    private func existingChore(named name: String) -> ChoreModel? {
        ChoreDuplicateFinder.candidates(for: name, in: choresModel.cardModels)
            .first { ChoreDuplicateFinder.isExactMatch(name, $0.name) }
    }

    // MARK: - Editing

    func toggle(_ id: ShopCard.ID) {
        guard let index = shopCards.firstIndex(where: { $0.id == id }) else { return }
        shopCards[index].isIncluded.toggle()
    }

    func toggleChore(_ id: ChoreCard.ID) {
        guard let index = choreCards.firstIndex(where: { $0.id == id }) else { return }
        choreCards[index].isIncluded.toggle()
    }

    func setAddsToDuplicate(_ id: ShopCard.ID, _ adds: Bool) {
        guard let index = shopCards.firstIndex(where: { $0.id == id }) else { return }
        shopCards[index].addsToDuplicate = adds
    }

    /// The item form confirmed changes to a card.
    func replace(_ id: ShopCard.ID, with suggestion: ShopItemSuggestion) {
        guard let index = shopCards.firstIndex(where: { $0.id == id }) else { return }
        shopCards[index].suggestion = suggestion
        shopCards[index].isIncluded = true
        // Confirmed in the form: category and people are the person's choice now.
        shopCards[index].needsCategory = false
        shopCards[index].needsPeople = false
        Task {
            let existing = await shopList.duplicateItem(named: suggestion.name)
            guard let index = shopCards.firstIndex(where: { $0.id == id }) else { return }
            shopCards[index].duplicate = existing
            shopCards[index].addsToDuplicate = false
        }
    }

    /// The chore form came back (✓). A new chore's name may have changed, so look for a
    /// repeat again.
    func choreEdited(_ id: ChoreCard.ID) {
        guard let index = choreCards.firstIndex(where: { $0.id == id }) else { return }
        choreCards[index].isIncluded = true
        guard !choreCards[index].usesExisting else { return }
        let existing = existingChore(named: choreCards[index].form.draft.name)
        if existing?.recordID != choreCards[index].duplicate?.recordID {
            choreCards[index].duplicate = existing
            choreCards[index].existingForm = nil
        }
    }

    /// Picks the existing chore or a new one for a repeated chore. The existing chore's form is
    /// loaded the first time, in edit mode, so its changes are saved with the rest.
    func setUsesExisting(_ id: ChoreCard.ID, _ usesExisting: Bool) async {
        guard let index = choreCards.firstIndex(where: { $0.id == id }) else { return }
        if usesExisting, choreCards[index].existingForm == nil, let existing = choreCards[index].duplicate {
            let form = CreateAndEditChoreViewModel(
                originalModel: existing,
                availableHouseUsers: houseUsers,
                carouselViewModel: choresModel
            )
            await form.load()
            guard let index = choreCards.firstIndex(where: { $0.id == id }) else { return }
            choreCards[index].existingForm = form
            choreCards[index].usesExisting = true
            return
        }
        choreCards[index].usesExisting = usesExisting && choreCards[index].existingForm != nil
    }

    /// Moves a shopping card to chores ("lavar o tapete" read as a purchase).
    func moveToChores(_ id: ShopCard.ID) async {
        guard let index = shopCards.firstIndex(where: { $0.id == id }) else { return }
        let card = shopCards.remove(at: index)
        let line = card.isFromAI ? card.suggestion.name : card.suggestion.input
        choreCards.append(await choreCard(for: line))
    }

    /// Moves a chore card to shopping ("sabão em pó" read as a chore).
    func moveToShopping(_ id: ChoreCard.ID) async {
        guard let index = choreCards.firstIndex(where: { $0.id == id }) else { return }
        let card = choreCards.remove(at: index)
        var shop: ShopCard
        if usesAI, let item = await shopList.suggestItems(from: card.line)?.first {
            shop = ShopCard(ai: item)
        } else {
            shop = ShopCard(plain: SharedTextReader.shopItem(from: card.line))
        }
        shop.duplicate = await shopList.duplicateItem(named: shop.suggestion.name)
        shopCards.append(shop)
    }

    // MARK: - Saving

    /// ✓ is enabled when something is ticked and every ticked card is complete. Unticked cards
    /// are simply not wanted.
    var canConfirm: Bool {
        let shops = shopCards.filter(\.isIncluded)
        let chores = choreCards.filter(\.isIncluded)
        return !(shops.isEmpty && chores.isEmpty)
            && shops.allSatisfy(\.isComplete)
            && chores.allSatisfy(\.isComplete)
    }

    /// Whether a ticked card still needs fields (shown as a hint under the cards).
    var hasIncompleteCards: Bool {
        shopCards.contains { $0.isIncluded && !$0.isComplete }
            || choreCards.contains { $0.isIncluded && !$0.isComplete }
    }

    /// Saves the ticked cards. Saved cards leave the list, so trying again never adds them twice.
    ///
    /// - Returns: `true` when everything was saved and the page can close.
    func save() async -> Bool {
        guard canConfirm else { return false }
        isSaving = true
        errorText = nil
        defer { isSaving = false }

        for card in shopCards where card.isIncluded {
            let success: Bool
            if card.addsToDuplicate, let existing = card.duplicate {
                success = await shopList.merge(
                    into: existing,
                    adding: card.suggestion.quantity,
                    consumers: card.suggestion.consumers ?? []
                )
            } else {
                success = await shopList.addSuggestedItems([card.suggestion]) == 1
            }
            guard success else {
                errorText = shopList.errorMessage ?? L10n.tr("Tente novamente.")
                shopList.clearError()
                return false
            }
            shopCards.removeAll { $0.id == card.id }
            didSaveAnything = true
        }

        for card in choreCards where card.isIncluded {
            // The same save as the form's ✓ (points, occurrences, calendar). An existing chore
            // left unchanged isn't saved again.
            let form = card.activeForm
            guard await form.confirm() else {
                errorText = form.alert?.message ?? L10n.tr("Tente novamente.")
                return false
            }
            choreCards.removeAll { $0.id == card.id }
            didSaveAnything = true
        }
        return true
    }

    /// An empty chore, like the "+" button on the chores tab creates.
    static func newChoreModel() -> ChoreModel {
        ChoreModel(
            name: "",
            description: "",
            isDone: false,
            frequency: .undefined,
            duration: 0,
            isPublic: true,
            priorityTag: .undefined
        )
    }
}

// MARK: - Chore form

extension CreateAndEditChoreViewModel {

    /// Fills the form from a shared line. On Premium it's the same as reading a description
    /// (``apply(_:keepingName:)``, with ✨ on what the AI filled); on the free plan only the name
    /// and the day said.
    func fill(with prefill: ChoreImportPrefill) {
        if let suggestion = prefill.suggestion {
            apply(suggestion)
        } else {
            draft.name = prefill.name
            if let date = prefill.date {
                // A day said without how often means once (same rule as the AI path).
                draft.frequency = .none
                let day = Calendar.current.startOfDay(for: date)
                if dateWindow.contains(day), day >= earliestSelectableDay {
                    selectedDate = day
                }
            }
        }
        if let room = prefill.room {
            draft.room = room
        }
    }
}
