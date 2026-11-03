//
//  ShopItemSuggestion.swift
//  Cognitive-Work
//
//  Created by anshu Li on 16/10/26.
//

import Foundation
import FoundationModels

// MARK: - Model output (Foundation Models)
//
// These types are what the on-device model generates. `@Generable` uses constrained decoding,
// so the model can only produce valid cases and values. They mirror the app's own enums
// (same raw values) so the persisted types don't depend on FoundationModels.
//
// `nonisolated`: the project defaults to MainActor isolation, but the framework generates these
// values off the main actor.

@Generable
nonisolated enum GeneratedShopCategory: String {
    case food, produce, drinks, cleaning, hygiene, home, pets, other
}

/// Mirror of ``UnitMeasurement``, without `undefined`, which the form never offers.
@Generable
nonisolated enum GeneratedShopUnit: String {
    case gram, kilogram, milliliter, liter, unit, package
}

/// What the price the person wrote refers to: one unit, the whole purchase, or each person's share.
@Generable
nonisolated enum GeneratedPriceKind: String {
    case none, perUnit, total, perPerson
}

/// Who the person said the item is for.
@Generable
nonisolated enum GeneratedSharing: String {
    case notSaid, everyone, specificPeople
}

/// One shopping-list entry read by the model.
///
/// Properties are generated in declaration order: the name comes first so the category can
/// build on it.
@Generable
nonisolated struct GeneratedShopItem {
    @Guide(description: "The product only, without amount or unit")
    var name: String

    /// Same bounds as ``QuantityStepper/allowedRange``.
    @Guide(.range(1...1000))
    var quantity: Int

    var unit: GeneratedShopUnit

    var category: GeneratedShopCategory

    // Price and split. The model only reads what the person wrote; the amount each person
    // pays is always computed in code (equal split, the same rule as ``DebtCalculator``).

    var priceKind: GeneratedPriceKind

    @Guide(description: "The price the person wrote, as a number. 0 when no price was written")
    var price: Double

    var sharing: GeneratedSharing

    @Guide(description: "Housemates the item is for, written exactly as in the housemates list", .maximumCount(10))
    var people: [String]

    @Guide(description: "Whether the person typing includes themselves, such as eu, para mim, me or I")
    var includesSelf: Bool
}

/// Several items read from one text (the shopping list page's AI button).
@Generable
nonisolated struct GeneratedShopList {
    @Guide(description: "One item per product the person listed, in the order written", .maximumCount(10))
    var items: [GeneratedShopItem]
}

// MARK: - App-side suggestion

/// What the add-item form can pre-fill, already mapped to the app's own types.
struct ShopItemSuggestion {
    /// The exact text the suggestion was made for; the form ignores results for older text.
    let input: String
    let name: String
    let quantity: Int
    let unit: UnitMeasurement
    let category: ShopItemCategory
    /// Price of ONE unit (like ``ShopListItem/value``), or `nil` when no price was written.
    let unitPrice: Double?
    /// Who consumes and splits the item, or `nil` when the person didn't say (the form keeps
    /// what it has).
    let consumers: [UserModel]?
}

extension IntelligenceManager {

    /// Suggests name, quantity, unit, category, price and who splits it for a shopping-list entry.
    ///
    /// - Parameters:
    ///   - entry: What the person typed, already trimmed.
    ///   - housemates: Everyone who can share the item; their names go in the prompt so the
    ///     model can recognize them.
    ///   - currentUser: The person typing, for "eu" / "para mim".
    ///   - selectedConsumers: Who the form already has selected; used for a per-person price
    ///     when the person didn't say who splits the item.
    /// - Returns: `nil` when AI is unavailable or the request fails.
    func suggestShopItem(
        for entry: String,
        housemates: [UserModel],
        currentUser: UserModel?,
        selectedConsumers: [UserModel]
    ) async -> ShopItemSuggestion? {
        let prompt = IntelligencePrompts.ShopItemParse.self
        guard let generated = await generate(
            GeneratedShopItem.self,
            prompt: prompt.prompt(
                for: entry,
                housemates: housemates.map(\.name),
                currentUserName: currentUser?.name
            ),
            // The product name must stay as typed, so no translation to the app's language.
            instructions: instructions(task: prompt.task, output: .sameAsInput),
            promptID: prompt.id
        ) else { return nil }

        return Self.makeSuggestion(
            from: generated,
            input: entry,
            sourceText: entry,
            housemates: housemates,
            currentUser: currentUser,
            selectedConsumers: selectedConsumers
        )
    }

    /// Reads several products from one text, one suggestion per product.
    ///
    /// - Parameters:
    ///   - text: What the person typed, usually one product per line.
    ///   - housemates: Everyone who can share the items.
    ///   - currentUser: The person typing.
    /// - Returns: `nil` when AI is unavailable or the request fails; items without a name are
    ///   dropped.
    func suggestShopItems(
        from text: String,
        housemates: [UserModel],
        currentUser: UserModel?
    ) async -> [ShopItemSuggestion]? {
        let prompt = IntelligencePrompts.ShopListParse.self
        guard let generated = await generate(
            GeneratedShopList.self,
            prompt: prompt.prompt(
                for: text,
                housemates: housemates.map(\.name),
                currentUserName: currentUser?.name
            ),
            instructions: instructions(task: prompt.task, output: .sameAsInput),
            promptID: prompt.id
        ) else { return nil }

        let sources = Self.sourceLines(for: generated.items, in: text)
        return generated.items.indices
            .map { index in
                Self.makeSuggestion(
                    from: generated.items[index],
                    input: text,
                    sourceText: sources[index],
                    housemates: housemates,
                    currentUser: currentUser,
                    // No form selection on the list page: a per-person price splits by the house.
                    selectedConsumers: []
                )
            }
            .filter { !$0.name.isEmpty }
    }

    /// Finds the part of `text` each item came from, so names said for one item never leak into
    /// another. Each item's part starts where its name appears and ends at the next item's name
    /// or the end of its line, whichever comes first. This works both for a typed list, one item
    /// per line, and for a spoken one, where everything is a single sentence: "2 quilos de arroz
    /// para Carol, chá para Anshu e leite para todos".
    ///
    /// Names are searched in order, after the previous item's, so a repeated name keeps its
    /// place. When a name can't be found, the item gets its whole line if the lines and items
    /// pair up one to one, otherwise `nil` (the model's reading of the people is used then).
    /// The parts are lowercased and without accents, which is how they're read afterwards.
    private static func sourceLines(for items: [GeneratedShopItem], in text: String) -> [String?] {
        let source = folded(text)
        let isSeparator: (Character) -> Bool = { $0 == "\n" || $0 == ";" }
        let lines = source
            .split(whereSeparator: isSeparator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Where each item's name starts in the text.
        var starts: [String.Index?] = []
        var searchFrom = source.startIndex
        for item in items {
            let name = folded(item.name).trimmingCharacters(in: .whitespacesAndNewlines)
            // "banana" in the text vs "bananas" from the model: also try the first letters.
            let stem = String(name.prefix(4))
            func find(from lowerBound: String.Index) -> Range<String.Index>? {
                let range = lowerBound..<source.endIndex
                if !name.isEmpty, let found = source.range(of: name, range: range) { return found }
                if stem.count >= 3, let found = source.range(of: stem, range: range) { return found }
                return nil
            }
            // In order first; anywhere as a fallback, in case the model reordered the items.
            let found = find(from: searchFrom) ?? find(from: source.startIndex)
            starts.append(found?.lowerBound)
            if let found, found.lowerBound >= searchFrom {
                searchFrom = found.upperBound
            }
        }

        return items.indices.map { index in
            guard let start = starts[index] else {
                return lines.count == items.count ? lines[index] : nil
            }
            // The closest other item's name after this one.
            let nextStart = starts.indices
                .filter { $0 != index }
                .compactMap { starts[$0] }
                .filter { $0 > start }
                .min() ?? source.endIndex
            let lineEnd = source[start...].firstIndex(where: isSeparator) ?? source.endIndex
            return String(source[start..<min(nextStart, lineEnd)])
        }
    }

    /// Turns one model item into a suggestion the app can use. Shared by the single-item form
    /// and the list page, so both clamp, match people and compute prices the same way.
    ///
    /// - Parameter sourceText: The item's own line, used to find who it's for. `nil` when it
    ///   couldn't be found; then the model's reading of the people is used instead.
    private static func makeSuggestion(
        from generated: GeneratedShopItem,
        input: String,
        sourceText: String?,
        housemates: [UserModel],
        currentUser: UserModel?,
        selectedConsumers: [UserModel]
    ) -> ShopItemSuggestion {
        // Clamp to what the form accepts. The output is guided, but never trust it blindly.
        let name = String(
            generated.name
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(TextLimits.shopItemName)
        )
        let range = QuantityStepper.allowedRange
        let quantity = min(max(generated.quantity, range.lowerBound), range.upperBound)
        // Resolved first: a per-person price needs to know how many people split the item.
        // The people come from the item's own text, checked in code. The small model sometimes
        // copies the whole housemates list from the prompt, so its own list is only a fallback.
        var consumers: [UserModel]?
        if let sourceText {
            consumers = Self.consumersMentioned(in: sourceText, housemates: housemates, currentUser: currentUser)
        } else {
            consumers = Self.consumers(from: generated, housemates: housemates, currentUser: currentUser)
        }
        // "8 reais por pessoa" without saying who: use the people already selected in the form,
        // or the whole house when nobody is selected yet.
        if consumers == nil, generated.priceKind == .perPerson {
            if !selectedConsumers.isEmpty {
                consumers = selectedConsumers
            } else if !housemates.isEmpty {
                consumers = housemates
            }
        }

        return ShopItemSuggestion(
            input: input,
            name: name,
            quantity: quantity,
            unit: UnitMeasurement(rawValue: generated.unit.rawValue) ?? .unit,
            category: ShopItemCategory(rawValue: generated.category.rawValue) ?? .other,
            unitPrice: Self.unitPrice(from: generated, quantity: quantity, consumerCount: consumers?.count),
            consumers: consumers
        )
    }

    /// The price of one unit, the way ``ShopListItem/value`` stores it. All arithmetic happens
    /// here, in code, never in the model:
    /// - `perUnit`: the price as written.
    /// - `total`: price ÷ quantity.
    /// - `perPerson`: price × people = total, then ÷ quantity. When nobody was named, the caller
    ///   falls back to the form's selection or the whole house before calling this.
    ///
    /// The unit price is rounded to cents, so a split that doesn't divide evenly can be off by a
    /// cent per person (R$ 1 × 3 people ÷ 7 units stores R$ 0,43).
    private static func unitPrice(
        from generated: GeneratedShopItem,
        quantity: Int,
        consumerCount: Int?
    ) -> Double? {
        guard generated.price > 0, generated.price.isFinite else { return nil }
        let unit: Double
        switch generated.priceKind {
        case .none:
            return nil
        case .perUnit:
            unit = generated.price
        case .total:
            unit = generated.price / Double(quantity)
        case .perPerson:
            guard let consumerCount, consumerCount > 0 else { return nil }
            unit = generated.price * Double(consumerCount) / Double(quantity)
        }
        let cents = (unit * 100).rounded() / 100
        return cents > 0 ? cents : nil
    }

    /// Matches the names the model returned against the real housemates. Only names that match
    /// exactly one person count, so the model can never add someone who isn't in the house.
    private static func consumers(
        from generated: GeneratedShopItem,
        housemates: [UserModel],
        currentUser: UserModel?
    ) -> [UserModel]? {
        var sharing = generated.sharing
        // Safety net for the small model: "para mim" or a name with sharing left as notSaid
        // still means specific people, never the whole house by default.
        if sharing == .notSaid, generated.includesSelf || !generated.people.isEmpty {
            sharing = .specificPeople
        }

        switch sharing {
        case .notSaid:
            return nil
        case .everyone:
            return housemates.isEmpty ? nil : housemates
        case .specificPeople:
            var picked: [UserModel] = []
            func add(_ user: UserModel) {
                if !picked.contains(where: { $0.id == user.id }) { picked.append(user) }
            }
            if generated.includesSelf, let currentUser { add(currentUser) }
            for spokenName in generated.people {
                let matches = housemates.filter { nameMatches($0.name, spokenName) }
                if matches.count == 1 { add(matches[0]) }
            }
            return picked.isEmpty ? nil : picked
        }
    }

    // MARK: People mentioned in the text

    /// Words meaning "the whole house" ("para todos", "para a casa", "for everyone").
    private static let everyoneWords: Set<String> = ["todos", "todas", "casa", "geral", "everyone", "everybody", "house"]

    /// Words meaning the person typing ("eu", "para mim", "for me", "I").
    private static let selfWords: Set<String> = ["eu", "mim", "comigo", "me", "i", "myself"]

    /// Who an item is for, read straight from its own text: housemates whose first name appears
    /// in it, the person typing for "eu" / "mim" / "me", or everyone for "todos" / "casa".
    /// `nil` when the text names no one, so the review shows "não informado".
    ///
    /// Also used for chores (see ChoreSuggestion.swift), where `everyoneCounts` is `false`:
    /// "limpar a casa" names a place there, not the whole house as responsible.
    static func consumersMentioned(
        in text: String,
        housemates: [UserModel],
        currentUser: UserModel?,
        everyoneCounts: Bool = true
    ) -> [UserModel]? {
        let words = Set(
            folded(text)
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
        )

        if everyoneCounts, !words.isDisjoint(with: everyoneWords) {
            return housemates.isEmpty ? nil : housemates
        }

        var picked: [UserModel] = []
        func add(_ user: UserModel) {
            if !picked.contains(where: { $0.id == user.id }) { picked.append(user) }
        }
        if !words.isDisjoint(with: selfWords), let currentUser { add(currentUser) }
        for user in housemates where isMentioned(user.name, in: words) {
            add(user)
        }
        return picked.isEmpty ? nil : picked
    }

    /// Whether `fullName`'s first name is one of `words`, or starts one of them when it has at
    /// least 4 letters ("carol" in "carolzinha"). Shorter names must match exactly, so "Ana"
    /// isn't found in "ananás".
    private static func isMentioned(_ fullName: String, in words: Set<String>) -> Bool {
        guard let first = folded(fullName).split(separator: " ").first.map(String.init),
              !first.isEmpty
        else { return false }
        if words.contains(first) { return true }
        return first.count >= 4 && words.contains(where: { $0.hasPrefix(first) })
    }

    /// Lowercased without accents, so "Chá" and "cha", "João" and "joao" compare equal.
    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// "ana" matches "Ana Souza": same full name or same first name, ignoring case and accents.
    private static func nameMatches(_ fullName: String, _ spokenName: String) -> Bool {
        func normalized(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let full = normalized(fullName)
        let spoken = normalized(spokenName)
        guard !spoken.isEmpty else { return false }
        return full == spoken || full.split(separator: " ").first.map(String.init) == spoken
    }
}

