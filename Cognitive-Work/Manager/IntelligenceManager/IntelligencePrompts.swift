//
//  IntelligencePrompts.swift
//  Cognitive-Work
//
//  Created by anshu Li on 16/10/26.
//

import Foundation

/// Every prompt the app sends to the on-device model, in one place.
///
/// Prompts are written in English: the model accepts prompts, instructions and output in
/// different languages, and ``IntelligenceManager/instructions(task:output:)`` sets the output
/// language from the app's current language.
enum IntelligencePrompts {

    /// category, price and who splits it.
    enum ShopItemParse {

        static let id = "shop-item-parse-v2"

        /// The unit, category, priceKind and sharing names match the cases of the `Generated…`
        /// enums in ShopItemSuggestion.swift; keep them in sync.
        /// Rules for every field of one item. Shared with ``ShopListParse`` so both read prices,
        /// units and people the same way.
        static let fieldRules = """
        name: the product only, without amount or unit, short (at most 18 characters). Write it in the same language and script the person used, exactly as they wrote it: never translate it ("咖啡" stays "咖啡", "coffee" stays "coffee", "café" stays "café").
        quantity and unit: the amount the person wrote. If they wrote no amount, use quantity 1 and unit.
        Convert fractions to gram or milliliter, for example "meio quilo" is 500 gram.
        Use package for packs, boxes, bags and bundles.
        category is the supermarket section:
        food: groceries and packaged food, including meat, dairy and bread.
        produce: fresh fruits, vegetables and herbs.
        drinks: water, juice, soda, coffee, tea, beer and wine.
        cleaning: products to clean the house, dishes and clothes.
        hygiene: personal care products and toilet paper.
        home: household items such as light bulbs, batteries and kitchen tools.
        pets: pet food and pet supplies.
        other: anything else.
        price: the price the person wrote, as a number ("R$ 12,50" is 12.5). If there is no price, use price 0 and priceKind none.
        A price written without "cada", "a unidade", "o quilo", "por pessoa" or "each" is the total for the whole amount: "6 bananas, 5 reais" is 5 for all six bananas.
        priceKind: perPerson when the price is what each person pays ("por pessoa", "cada um paga", "para cada um", "per person", "each pays"); perUnit only when the price names the product or the unit ("5 reais cada banana", "5 reais a unidade", "5 reais o quilo", "each one costs"); otherwise total. When "cada um" comes right after a price and no product or unit is named, it means each person: use perPerson.
        sharing: everyone when the item is for the whole house ("para todos", "para todas", "para a casa", "for everyone"); specificPeople when the person says who it is for, even if it is only themselves ("para mim", "só eu", "for me"); otherwise notSaid.
        people: names from the housemates list, written exactly as in the list. Leave it empty unless sharing is specificPeople.
        includesSelf: true when the person typing includes themselves ("eu", "para mim", "me", "I").
        """

        /// Worked examples, one item per line. Shared with ``ShopListParse``: the small model
        /// follows examples more than rules.
        static let examples = """
        "2kg de arroz" -> name "arroz", quantity 2, unit kilogram, category food, priceKind none, price 0, sharing notSaid
        "detergente R$ 8 para todos" -> name "detergente", quantity 1, unit unit, category cleaning, priceKind total, price 8, sharing everyone
        "6 bananas 1 real cada, eu e Ana" -> name "bananas", quantity 6, unit unit, category produce, priceKind perUnit, price 1, sharing specificPeople, people ["Ana"], includesSelf true
        "2 pacotes de papel higiênico" -> name "papel higiênico", quantity 2, unit package, category hygiene, priceKind none, price 0, sharing notSaid
        "6 bananas, 1 real por pessoa, eu e Ana" -> name "bananas", quantity 6, unit unit, category produce, priceKind perPerson, price 1, sharing specificPeople, people ["Ana"], includesSelf true
        "6 bananas, 8 reais para cada um" -> name "bananas", quantity 6, unit unit, category produce, priceKind perPerson, price 8, sharing notSaid
        "dog food $30 for Ana" -> name "dog food", quantity 1, unit unit, category pets, priceKind total, price 30, sharing specificPeople, people ["Ana"], includesSelf false
        "6 bananas, 5 reais para mim" -> name "bananas", quantity 6, unit unit, category produce, priceKind total, price 5, sharing specificPeople, people [], includesSelf true
        """

        static let task = """
        You fill in one item of a household shopping list from what the person typed.
        \(fieldRules)
        Examples:
        \(examples)
        """

        /// The person's text and the housemates' names go here, never in the instructions.
        static func prompt(for entry: String, housemates: [String], currentUserName: String?) -> String {
            var lines: [String] = []
            if !housemates.isEmpty {
                lines.append("Housemates: \(housemates.joined(separator: ", "))")
            }
            if let currentUserName {
                lines.append("The person typing is: \(currentUserName)")
            }
            lines.append("Shopping list entry: \(entry)")
            return lines.joined(separator: "\n")
        }
    }

    /// Turns a text with several products, one per line, into a list of items. Used by the AI
    enum ShopListParse {

        static let id = "shop-list-parse-v2"

        static let task = """
        You turn what the person typed into household shopping list items, one item per product, in the order written.
        Each line is usually one product. Products can also be separated by ";".
        A price or names that follow a product belong to that product. "eu e Ana" names people, not two products.
        Fill in each item with these rules:
        \(ShopItemParse.fieldRules)
        Examples of single items:
        \(ShopItemParse.examples)
        Example of a list:
        "2kg de arroz, R$ 25, eu e Ana
        detergente para todos
        1 L de leite" -> three items:
        name "arroz", quantity 2, unit kilogram, category food, priceKind total, price 25, sharing specificPeople, people ["Ana"], includesSelf true
        name "detergente", quantity 1, unit unit, category cleaning, priceKind none, price 0, sharing everyone
        name "leite", quantity 1, unit liter, category food, priceKind none, price 0, sharing notSaid
        """

        /// The person's text and the housemates' names go here, never in the instructions.
        static func prompt(for text: String, housemates: [String], currentUserName: String?) -> String {
            var lines: [String] = []
            if !housemates.isEmpty {
                lines.append("Housemates: \(housemates.joined(separator: ", "))")
            }
            if let currentUserName {
                lines.append("The person typing is: \(currentUserName)")
            }
            lines.append("Shopping list text:")
            lines.append(text)
            return lines.joined(separator: "\n")
        }
    }

    /// Decides whether a new shopping-list entry is the same product as one already on the list.
    enum SameProduct {

        static let id = "same-product-v1"

        static let task = """
        You compare two entries of a household shopping list and decide if buying them means buying the same product.
        same: the same product, even with a different type, brand, size or plural ("leite" and "leite integral", "banana" and "bananas", "sabão em pó" and "sabão em pó Omo").
        different: different products, even if they share a word ("leite" and "leite condensado", "papel higiênico" and "papel toalha", "molho de tomate" and "tomate").
        Examples:
        "leite integral" / "leite" -> same
        "leite condensado" / "leite" -> different
        "arroz integral" / "arroz" -> same
        "papel toalha" / "papel higiênico" -> different
        "detergente Ypê" / "detergente" -> same
        """

        /// Both names are the person's own text, so they go in the prompt, never the instructions.
        static func prompt(newName: String, existingName: String) -> String {
            "New entry: \(newName)\nAlready on the list: \(existingName)"
        }
    }

    /// Turns dishes the person wants to cook into the ingredients to buy.
    enum ShopRecipeExpansion {

        static let id = "shop-recipe-expansion-v2"

        static let task = """
        The person writes what to add to a household shopping list. Some parts may be dishes they want to cook ("quero fazer lasanha", "ingredientes para um bolo de cenoura").
        dishes: for each dish mentioned, the ingredients usually bought to make it for about 4 people, one per entry, with an amount when natural ("500 g de carne moída", "1 pacote de massa para lasanha"). Leave out water and salt. If no dish is mentioned, return no dishes.
        whoFor: who the dish is for, as written ("eu", "eu e Ana", "todos"). When the person speaks in the first person ("eu quero fazer", "vou fazer") and names nobody else, use "eu". Empty if not said.
        otherItems: every other part of the text that is not about those dishes, copied exactly as written (items, amounts, prices, people). Empty if there is nothing else.
        Examples:
        "quero fazer lasanha, e detergente para todos" -> dishes: lasanha ["1 pacote de massa para lasanha", "500 g de carne moída", "molho de tomate", "400 g de queijo muçarela", "200 g de presunto"], whoFor: "eu", otherItems: "detergente para todos"
        "2kg de arroz, ingredientes para bolo de cenoura" -> dishes: bolo de cenoura ["3 cenouras", "1 kg de farinha de trigo", "1 kg de açúcar", "12 ovos", "óleo"], whoFor: "", otherItems: "2kg de arroz"
        """

        /// The person's text goes in the prompt, never in the instructions.
        static func prompt(for text: String) -> String {
            "Text: \(text)"
        }
    }

    /// Suggests products for one supermarket section, from what's listed in it.
    enum ShopSectionIdeas {

        static let id = "shop-section-ideas-v1"

        static let task = """
        You help complete one section of a household shopping list. Suggest at most 2 products from that same supermarket section that people usually buy along with the ones listed there.
        Sections: food (groceries, meat, dairy, bread), produce (fruits, vegetables, herbs), drinks, cleaning (house, dishes and clothes), hygiene (personal care, toilet paper), home (household items), pets, other.
        Never suggest something already on the list, or a variant of it (another brand, size or type). Only common, clear choices; if nothing fits, return an empty list.
        name: a short, common product name.
        Examples:
        cleaning: "detergente" -> "esponja", "sabão em pó"
        produce: "tomate, cebola" -> "alho", "alface"
        food: "macarrão" -> "molho de tomate", "queijo ralado"
        drinks: "café" -> "leite"
        """

        /// The names are the person's text, so they go in the prompt.
        static func prompt(section: String, sectionNames: [String], listNames: [String]) -> String {
            """
            Section: \(section)
            In this section: \(sectionNames.joined(separator: ", "))
            Whole list: \(listNames.joined(separator: ", "))
            """
        }
    }

    /// Turns a chore description ("lavar a louça toda semana, urgente") into name, room,
    /// frequency, duration and priority. People are read by code, not by the model.
    enum ChoreParse {

        static let id = "chore-parse-v5"

        /// The frequency, duration and priority names match the `Generated…` enums in
        /// ChoreSuggestion.swift; keep them in sync.
        static let task = """
        You fill in a household chore form from what the person wrote or said.
        name: the chore itself, short (at most 18 characters), without frequency, dates or weekdays, room, people or urgency. Start with a verb when possible ("Lavar a louça").
        room: one name copied exactly from the house's rooms list, the room where the chore happens. Use "none" when no room clearly fits.
        frequency: what the person said ("todo dia", "todos os dias", "diariamente" -> daily; "toda semana" -> weekly; "a cada 15 dias" -> fortnightly; "uma vez por mês" -> monthly; "só hoje", "uma vez" -> once; a single day without how often, like "amanhã", "sábado" or "dia 30" -> once). If they didn't say, choose how often this chore is usually done in a home: daily, weekly, fortnightly or monthly.
        duration: what the person said, or else how long the chore usually takes: quick (under 20 minutes), moderate (20 to 59 minutes), slow (60 to 89 minutes) or verySlow (90 minutes or more).
        priority: only when the person says how urgent it is: low ("sem pressa"), medium, high ("importante"), urgent ("urgente", "hoje"). Otherwise notSaid.
        details: how-to details the person said that fit no other field ("usar luva", "depois do jantar"), as a short sentence in their words. Never repeat the frequency, people, room or urgency there, and never add your own advice. Empty if there are none.
        steps: the parts or steps the person listed ("o vaso, a pia e o box" -> "Vaso", "Pia", "Box"), one short item each. Empty if they listed none; do not invent steps.
        Examples:
        "eu vou lavar a louça todos os dias depois do jantar" -> name "Lavar a louça", room "Cozinha", frequency daily, duration quick, priority notSaid, details "Depois do jantar.", steps []
        "limpar o banheiro toda semana, urgente, usar luva, limpar o vaso, a pia e o box" -> name "Limpar o banheiro", room "Banheiro", frequency weekly, duration moderate, priority urgent, details "Usar luva.", steps ["Vaso", "Pia", "Box"]
        "tirar o lixo" -> name "Tirar o lixo", room "Cozinha", frequency daily, duration quick, priority notSaid, details "", steps []
        "trocar a roupa de cama a cada 15 dias" -> name "Trocar roupa de cama", room "Quarto", frequency fortnightly, duration moderate, priority notSaid, details "", steps []
        "limpar a geladeira" -> name "Limpar a geladeira", room "Cozinha", frequency monthly, duration slow, priority notSaid, details "", steps []
        """

        /// The person's text goes in the prompt (never in the instructions), with the house's rooms.
        static func prompt(for text: String, rooms: [String]) -> String {
            """
            Rooms: \(rooms.isEmpty ? "none" : rooms.joined(separator: ", "))
            Chore: \(text)
            """
        }
    }

    /// Typical checklist steps for a chore the person named, shown as chips to tap.
    enum ChoreChecklistIdeas {

        static let id = "chore-checklist-ideas-v1"

        static let task = """
        You suggest a checklist for a household chore: up to 5 short, concrete steps or parts (at most 40 characters each) that people usually do for it.
        Only physical steps, no advice or safety tips. Never repeat an item already on the checklist. If the chore is too simple to split, return an empty list.
        Examples:
        "Limpar o banheiro" -> "Vaso", "Pia", "Box", "Espelho", "Trocar as toalhas"
        "Lavar a louça" -> "Pratos e copos", "Panelas", "Secar e guardar", "Limpar a pia"
        "Tirar o lixo" -> "Lixo da cozinha", "Lixo do banheiro", "Separar recicláveis"
        """

        /// The chore's name and what's already listed are the person's text, so they go here.
        static func prompt(name: String, room: String?, existing: [String]) -> String {
            var lines = ["Chore: \(name)"]
            if let room { lines.append("Room: \(room)") }
            if !existing.isEmpty { lines.append("Already on the checklist: \(existing.joined(separator: ", "))") }
            return lines.joined(separator: "\n")
        }
    }

    /// Decides whether a new chore repeats one the house already has.
    enum SameChore {

        static let id = "same-chore-v1"

        static let task = """
        You compare two household chores and decide if they are the same task.
        same: the same work, even with other words ("Lavar louça" and "Lavar a louça", "Faxina no banheiro" and "Limpar o banheiro", "Tirar o lixo" and "Levar o lixo para fora").
        different: different work, even if they share a word ("Limpar o banheiro" and "Trocar as toalhas do banheiro", "Lavar roupa" and "Passar roupa", "Lavar a louça" and "Guardar a louça").
        """

        /// Both names are the person's text, so they go in the prompt.
        static func prompt(newName: String, existingName: String) -> String {
            "New chore: \(newName)\nExisting chore: \(existingName)"
        }
    }

    /// Where a chore fits in the day, to suggest the order of today's chores.
    enum ChorePhase {

        static let id = "chore-phase-v1"

        /// The phase names match ``GeneratedChorePhase``; keep them in sync.
        static let task = """
        You classify one household chore by when it happens in the day's flow.
        tidyUp: putting things away before cleaning ("arrumar a sala", "organizar o quarto").
        cooking: preparing food ("fazer o almoço", "cozinhar o jantar").
        afterMeal: cleaning up after a meal ("lavar a louça", "limpar o fogão", "limpar a mesa", "limpar a pia").
        dusting: dusting or wiping furniture and surfaces ("tirar o pó", "limpar os móveis").
        floorDry: sweeping or vacuuming ("varrer a casa", "aspirar a sala").
        floorWet: mopping or washing the floor ("passar pano", "lavar o quintal").
        laundryWash: washing clothes ("lavar roupa", "colocar roupa na máquina").
        laundryDry: hanging or drying clothes ("estender roupa", "tirar roupa do varal").
        laundryFold: folding, ironing or putting clothes away ("dobrar roupa", "passar roupa").
        trash: taking out the trash ("tirar o lixo", "levar o lixo para fora").
        other: anything that doesn't depend on other chores ("regar as plantas", "limpar o banheiro", "dar comida ao gato").
        """

        /// The chore's name is the person's text, so it goes in the prompt.
        static func prompt(for name: String) -> String {
            "Chore: \(name)"
        }
    }
}
