//
//  ShopListSuggestionViewModel.swift
//  Cognitive-Work
//
//  Created by anshu Li on 20/10/26.
//

import Foundation

/// A product the list page suggests adding with one tap.
struct ShopListSuggestion: Identifiable {

    enum Kind {
        /// Usually added every `intervalDays` days, and that time has passed (computed in code).
        case usual(intervalDays: Int)
        /// Usually bought together with something on the list (on-device model).
        case goesWithList
    }

    /// The name without case or accents, so the same product is suggested once.
    let id: String
    let kind: Kind
    let name: String
    let category: ShopItemCategory
    let quantity: Int
    let unit: UnitMeasurement
    /// Who it's for; `nil` means the whole house.
    let consumers: [UserModel]?
}

@Observable
final class ShopListSuggestionViewModel {

    /// What the chip row shows: usual items first, then the model's ideas.
    private(set) var suggestions: [ShopListSuggestion] = []

    @ObservationIgnored private let shopList: ShopListViewModel
    /// Hidden by the person in this session ("Não sugerir agora").
    @ObservationIgnored private var dismissedIDs = Set<String>()
    /// The pending names the model last answered for, so it isn't asked again for the same list.
    /// Each category's AI suggestions and the items they were made for (see ``complementItems(excluding:)``).
    @ObservationIgnored private var sectionIdeas: [ShopItemCategory: (key: String, suggestions: [ShopListSuggestion])] = [:]
    @ObservationIgnored private var lastComplements: [ShopListSuggestion] = []
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    /// How many usual items and model ideas the row shows at most.
    private let maxUsual = 5

    init(shopList: ShopListViewModel) {
        self.shopList = shopList
    }

    // MARK: - Time scale

    #if DEBUG
    /// DEBUG only: one "day" is one minute, to test usual items without waiting days.
    /// Set to `false` to use real days in Xcode builds too.
    static let usesMinutesAsDays = true
    #else
    static let usesMinutesAsDays = false
    #endif

    /// How long one "day" lasts for usual items.
    static var dayLength: TimeInterval { usesMinutesAsDays ? 60 : 86_400 }

    /// Which "day" `date` falls on, as a number: calendar days normally, minutes in the DEBUG test mode.
    private static func dayIndex(of date: Date) -> Int {
        if usesMinutesAsDays {
            return Int((date.timeIntervalSince1970 / dayLength).rounded(.down))
        }
        let calendar = Calendar.current
        return calendar.dateComponents(
            [.day],
            from: Date(timeIntervalSince1970: 0),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
    }

    // MARK: - Refreshing

    /// Recomputes the suggestions shortly after the list stops changing.
    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return // A newer change is coming.
            }
            let usual = usualItems(now: .now)
            publish(usual: usual, complements: lastComplements)

            let complements = await complementItems(excluding: usual)
            guard !Task.isCancelled else { return }
            publish(usual: usual, complements: complements)
        }
    }

    private func publish(usual: [ShopListSuggestion], complements: [ShopListSuggestion]) {
        let pending = shopList.pendingItems
        let all = (usual + complements).filter { suggestion in
            !dismissedIDs.contains(suggestion.id)
                // Already back on the list: no need to suggest it.
                && ShopItemDuplicateFinder.candidates(for: suggestion.name, in: pending, limit: 1).isEmpty
        }
        suggestions = all
    }

    // MARK: - Actions

    /// Adds the suggestion as a new item, through the same save as adding by hand.
    @discardableResult
    func add(_ suggestion: ShopListSuggestion) async -> Bool {
        let success = await shopList.saveItem(
            nil,
            name: suggestion.name,
            valueText: "",
            quantity: suggestion.quantity,
            unitMeasurement: suggestion.unit,
            category: suggestion.category,
            relatedUsers: suggestion.consumers ?? shopList.houseUsers,
            addedBy: shopList.currentUser
        )
        if success {
            suggestions.removeAll { $0.id == suggestion.id }
        }
        return success
    }

    /// Hides a suggestion until the app is opened again.
    func dismiss(_ suggestion: ShopListSuggestion) {
        dismissedIDs.insert(suggestion.id)
        suggestions.removeAll { $0.id == suggestion.id }
    }

    // MARK: - Usual items

    private func usualItems(now: Date) -> [ShopListSuggestion] {
        let groups = Dictionary(grouping: shopList.items) { Self.key(for: $0.name) }
        let pendingKeys = Set(shopList.pendingItems.map { Self.key(for: $0.name) })

        var found: [(suggestion: ShopListSuggestion, overdue: Double)] = []
        for (key, group) in groups where !key.isEmpty && !pendingKeys.contains(key) {
            // One purchase per day at most, oldest first. Purchase date when known, otherwise
            // when it was added (items bought before `boughtAt` existed).
            let days = Set(group.map { Self.dayIndex(of: $0.boughtAt ?? $0.createdAt) }).sorted()
            guard days.count >= 3, let lastDay = days.last else { continue }

            let intervals = zip(days, days.dropFirst()).map { Double($1 - $0) }
            // The usual interval is the median gap, not the mean: one quick top-up (bought
            // Friday and again Saturday) or one late week doesn't move it.
            // 7, 7, 1 days -> 7 (the mean would be 5); 8, 6, 9 days -> 8.
            let typical = Self.median(of: intervals)
            guard typical >= 1 else { continue }

            // Steady enough to trust: no gap more than twice the usual one.
            guard intervals.allSatisfy({ $0 <= typical * 2 }) else { continue }

            let elapsed = Double(Self.dayIndex(of: now) - lastDay)
            guard elapsed >= typical * 0.9 else { continue }

            // Repeat the most recent entry: its name, amount, unit and people.
            guard let latest = group.max(by: {
                ($0.boughtAt ?? $0.createdAt) < ($1.boughtAt ?? $1.createdAt)
            }) else { continue }
            let people = latest.relatedUsers(in: shopList.houseUsers)
            found.append((
                ShopListSuggestion(
                    id: key,
                    kind: .usual(intervalDays: Int(typical.rounded())),
                    name: latest.name,
                    category: latest.category,
                    quantity: latest.quantity,
                    unit: latest.unitMeasurement == .undefined ? .unit : latest.unitMeasurement,
                    consumers: people.isEmpty ? nil : people
                ),
                elapsed / typical
            ))
        }
        return found
            .sorted { $0.overdue > $1.overdue }
            .prefix(maxUsual)
            .map(\.suggestion)
    }

    // MARK: - Goes with the list

    /// AI suggestions for every category that has a card on the list (up to two each), so each
    /// card can end with its own. One request per category, reused while that category's items
    /// don't change.
    private func complementItems(excluding usual: [ShopListSuggestion]) async -> [ShopListSuggestion] {
        let pending = shopList.pendingItems
        // AI suggestions are Premium; the "usual items" (no AI) stay free.
        guard !pending.isEmpty, IntelligenceManager.shared.isAvailable,
              PremiumManager.shared.allows(.shopAI) else {
            sectionIdeas = [:]
            return []
        }

        // Only the 20 most recent names, to stay well inside the model's context.
        let listNames = Array(pending.sorted { $0.createdAt > $1.createdAt }.prefix(20).map(\.name))
        let categories = ShopItemCategory.allCases.filter { category in pending.contains { $0.category == category } }

        var fresh: [ShopItemCategory: (key: String, suggestions: [ShopListSuggestion])] = [:]
        for category in categories {
            let sectionNames = pending.filter { $0.category == category }.map(\.name)
            let key = sectionNames.map(Self.key(for:)).sorted().joined(separator: "|")

            // Same items in this category as last time: keep its suggestions.
            if let cached = sectionIdeas[category], cached.key == key {
                fresh[category] = cached
                continue
            }
            guard !Task.isCancelled else { return [] }
            let names = await IntelligenceManager.shared.suggestForSection(
                category,
                sectionNames: sectionNames,
                listNames: listNames
            ) ?? []
            fresh[category] = (key, names.map { name in
                ShopListSuggestion(
                    id: Self.key(for: name),
                    kind: .goesWithList,
                    name: name,
                    category: category,
                    quantity: 1,
                    unit: .unit,
                    consumers: nil
                )
            })
        }
        sectionIdeas = fresh

        // In the list's category order, each product once, never one already suggested as usual.
        var seen = Set(usual.map(\.id))
        let complements = categories
            .flatMap { fresh[$0]?.suggestions ?? [] }
            .filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
        lastComplements = complements
        return complements
    }

    /// The middle value (mean of the two middle ones for an even count); 0 when empty.
    private static func median(of values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }

    /// Lowercased without accents or extra spaces: "Detergente " and "detergente" are one product.
    private static func key(for name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }
}

