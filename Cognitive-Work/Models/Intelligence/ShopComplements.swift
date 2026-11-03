//
//  ShopComplements.swift
//  Cognitive-Work
//
//  Created by anshu Li on 20/10/26.
//

import Foundation
import FoundationModels

// MARK: - "Goes with your list" (on-device model)

/// Up to two products of one supermarket section that go with what's listed there.
@Generable
nonisolated struct GeneratedSectionIdeas {
    @Guide(description: "Products of this section that usually go with the ones listed and are missing. Empty when nothing clearly fits.", .maximumCount(2))
    var items: [String]
}

extension IntelligenceManager {

    /// Products of `category` that usually go with the items of that section ("detergente" ->
    /// "esponja" in cleaning), so every category card can offer its own suggestions.
    ///
    /// - Parameters:
    ///   - sectionNames: What's still to buy in that section.
    ///   - listNames: Everything still to buy, so nothing already listed is suggested.
    /// - Returns: Names in the app's language, or `nil` when AI is unavailable or the request fails.
    func suggestForSection(
        _ category: ShopItemCategory,
        sectionNames: [String],
        listNames: [String]
    ) async -> [String]? {
        let prompt = IntelligencePrompts.ShopSectionIdeas.self
        guard let generated = await generate(
            GeneratedSectionIdeas.self,
            prompt: prompt.prompt(section: category.rawValue, sectionNames: sectionNames, listNames: listNames),
            instructions: instructions(task: prompt.task, output: .appLanguage),
            promptID: prompt.id
        ) else { return nil }

        return generated.items.compactMap { item in
            let name = String(item.trimmingCharacters(in: .whitespacesAndNewlines).prefix(TextLimits.shopItemName))
            return name.isEmpty ? nil : name
        }
    }
}
