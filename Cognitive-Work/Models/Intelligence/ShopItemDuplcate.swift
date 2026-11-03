//
//  ShopItemDuplcate.swift
//  Cognitive-Work
//
//  Created by anshu Li on 20/10/26.
//


import Foundation
import FoundationModels

// MARK: - Finding an item that's already on the list

@Generable
nonisolated enum GeneratedSameProduct: String {
    case same, different
}

enum ShopItemDuplicateFinder {

    /// Up to `limit` pending items whose name looks like `name`, best match first.
    /// Exact names first, then names where one contains every word of the other
    /// ("leite" in "leite integral"), then names that start with the same word.
    static func candidates(for name: String, in items: [ShopListItem], limit: Int = 3) -> [ShopListItem] {
        let newWords = words(in: name)
        guard !newWords.isEmpty else { return [] }

        let scored: [(item: ShopListItem, score: Int)] = items.compactMap { item in
            let existingWords = words(in: item.name)
            guard !existingWords.isEmpty else { return nil }
            if existingWords == newWords { return (item, 3) }
            if Set(newWords).isSuperset(of: existingWords) || Set(existingWords).isSuperset(of: newWords) {
                return (item, 2)
            }
            if let first = newWords.first, first.count >= 4, first == existingWords.first {
                return (item, 1)
            }
            return nil
        }
        return scored
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map(\.item)
    }

    /// Whether the two names are the same once case and accents are ignored.
    static func isExactMatch(_ lhs: String, _ rhs: String) -> Bool {
        words(in: lhs) == words(in: rhs)
    }

    /// Lowercased words without accents; "Pão de Forma" -> ["pao", "de", "forma"].
    private static func words(in text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }
}

extension IntelligenceManager {

    /// Asks the on-device model whether two shopping-list names are the same product.
    ///
    /// - Returns: `nil` when AI is unavailable or the request fails; callers then treat the pair
    ///   as different, so nothing is merged by mistake.
    func isSameProduct(_ newName: String, as existingName: String) async -> Bool? {
        let prompt = IntelligencePrompts.SameProduct.self
        guard let answer = await generate(
            GeneratedSameProduct.self,
            prompt: prompt.prompt(newName: newName, existingName: existingName),
            instructions: instructions(task: prompt.task, output: .sameAsInput),
            promptID: prompt.id
        ) else { return nil }
        return answer == .same
    }
}
