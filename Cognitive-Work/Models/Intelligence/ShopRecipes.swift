//
//  ShopRecipes.swift
//  Cognitive-Work
//
//  Created by anshu Li on 28/10/26.
//

import Foundation
import FoundationModels

// MARK: - Dishes -> ingredients ("quero fazer lasanha")

@Generable
nonisolated struct GeneratedRecipeDish {
    @Guide(description: "The dish, short")
    var name: String

    @Guide(description: "Ingredients to buy for it, one per entry, with an amount when natural", .maximumCount(12))
    var ingredients: [String]

    @Guide(description: "Who the dish is for, as the person wrote it (\"eu\", \"eu e Ana\", \"todos\"). Empty if not said")
    var whoFor: String
}

@Generable
nonisolated struct GeneratedRecipeExpansion {
    @Guide(description: "Dishes the person wants to cook. Empty if they mention none", .maximumCount(3))
    var dishes: [GeneratedRecipeDish]

    @Guide(description: "Everything else the person wrote, copied exactly. Empty if nothing else")
    var otherItems: String
}

/// A text where the dishes were replaced by their ingredients, ready for the usual list reading.
struct RecipeExpansion {
    /// One line per ingredient, then the rest of what the person wrote.
    let text: String
    /// Each ingredient line and the dish it's for, to show "Receita: Lasanha" on its card.
    let ingredientLines: [(line: String, dish: String)]

    /// The dish a read item belongs to, found by its name inside an ingredient line.
    func dish(for itemName: String) -> String? {
        let name = Self.folded(itemName)
        guard !name.isEmpty else { return nil }
        return ingredientLines.first { Self.folded($0.line).contains(name) }?.dish
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension IntelligenceManager {

    /// First-person words: "eu quero fazer um bolo" is for the person typing.
    private static let selfWords: Set<String> = [
        "eu", "quero", "vou", "mim", "me", "i", "want",
        "yo", "quiero", "voy",
        "je", "veux", "vais", "moi"
    ]

    /// Words that say the person wants to cook something; without them the text is read as a
    /// plain list and no request is made.
    private static let recipeWords = [
        "fazer", "receita", "ingrediente", "ingredientes", "cozinhar", "preparar",
        "make", "recipe", "ingredients", "cook",
        "hacer", "receta", "cocinar",
        "faire", "recette", "cuisiner", "preparer"
    ]

    /// Chinese has no spaces between words: these are looked for inside the text.
    private static let recipePhrases = ["做", "食谱", "菜谱", "材料", "配料", "煮", "烤", "烧"]

    /// Replaces the dishes in a shopping text with their ingredients ("quero fazer lasanha" ->
    /// "massa para lasanha", "carne moída", "molho de tomate"…), keeping everything else as
    /// written. The result then goes through the usual list reading, so amounts, prices and
    /// people work the same.
    ///
    /// - Returns: `nil` when the text mentions no dish (or AI is unavailable); the caller reads
    ///   the text as it is.
    func expandRecipes(in text: String) async -> RecipeExpansion? {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let words = Set(folded.split(whereSeparator: { !$0.isLetter }).map(String.init))
        guard Self.recipeWords.contains(where: words.contains)
                || Self.recipePhrases.contains(where: folded.contains)
        else { return nil }

        let prompt = IntelligencePrompts.ShopRecipeExpansion.self
        guard let generated = await generate(
            GeneratedRecipeExpansion.self,
            prompt: prompt.prompt(for: text),
            instructions: instructions(task: prompt.task, output: .appLanguage),
            promptID: prompt.id
        ), !generated.dishes.isEmpty else { return nil }

        var lines: [(line: String, dish: String)] = []
        for dish in generated.dishes {
            let dishName = dish.name.trimmingCharacters(in: .whitespacesAndNewlines)
            var whoFor = dish.whoFor.trimmingCharacters(in: .whitespacesAndNewlines)
            if whoFor.isEmpty, !words.isDisjoint(with: Self.selfWords) || folded.contains("我") {
                whoFor = "eu"
            }
            for ingredient in dish.ingredients {
                let ingredientText = ingredient.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !ingredientText.isEmpty else { continue }
                let line = whoFor.isEmpty ? ingredientText : "\(ingredientText), \(whoFor)"
                lines.append((line, dishName))
            }
        }
        guard !lines.isEmpty else { return nil }

        let rest = generated.otherItems.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = (lines.map(\.line) + (rest.isEmpty ? [] : [rest])).joined(separator: "\n")
        return RecipeExpansion(text: text, ingredientLines: lines)
    }
}
