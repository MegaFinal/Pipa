//
//  ReceiptProductCategory.swift
//  Cognitive-Work
//
//  Created by anshu Li on 05/11/26.
//

import Foundation
import FoundationModels

extension IntelligenceManager {

    /// Asks the on-device model which supermarket section a product read from a receipt
    /// belongs to. Only used when the house's memory and the word table don't know it.
    ///
    /// - Parameter name: The product's name as the review screen shows it (spelled out).
    /// - Returns: `nil` when AI is unavailable, the request fails, or the model can't tell
    ///   ("other"): the product then stays in "Outros".
    func receiptCategory(for name: String) async -> ShopItemCategory? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return nil }
        let prompt = IntelligencePrompts.ReceiptProductCategory.self
        guard let generated = await generate(
            GeneratedShopCategory.self,
            prompt: prompt.prompt(for: trimmed),
            instructions: instructions(task: prompt.task, output: .sameAsInput),
            promptID: prompt.id
        ) else { return nil }
        guard let category = ShopItemCategory(rawValue: generated.rawValue), category != .other else { return nil }
        return category
    }
}
