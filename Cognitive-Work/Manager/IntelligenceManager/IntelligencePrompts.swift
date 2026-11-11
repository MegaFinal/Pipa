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

    /// The examples written in the app's current language (English when a language has none).
    ///
    /// For text the model writes for people (ingredients, product ideas, chore names, checklist
    /// steps), the small on-device model copies the language of its examples more than it follows
    /// "You MUST respond in …": Portuguese examples gave Portuguese ingredients in an English app.
    /// So those prompts carry their examples in every app language.
    static func localized(_ examples: [AppLanguage: String]) -> String {
        examples[LanguageManager.shared.current] ?? examples[.english] ?? ""
    }

    /// category, price and who splits it.
    enum ShopItemParse {

        static let id = "shop-item-parse-v3"

        /// The unit, category, priceKind and sharing names match the cases of the `Generated…`
        /// enums in ShopItemSuggestion.swift; keep them in sync.
        /// Rules for every field of one item. Shared with ``ShopListParse`` so both read prices,
        /// units and people the same way.
        static let fieldRules = """
        name: the product only, without amount or unit, short (at most 18 characters). Write it in the same language and script the person used, exactly as they wrote it: never translate it ("咖啡" stays "咖啡", "コーヒー" stays "コーヒー", "커피" stays "커피", "coffee" stays "coffee", "café" stays "café").
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

        static let id = "shop-list-parse-v3"

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

    /// Puts a product read from a receipt in its supermarket section, when neither the house's
    /// memory nor the words of its name tell (see ``ReceiptCategories``).
    enum ReceiptProductCategory {

        static let id = "receipt-product-category-v1"

        /// The section names match the cases of ``GeneratedShopCategory``; keep them in sync.
        static let task = """
        You put a product bought at a store into its supermarket section. The name was printed on a receipt, so it may be abbreviated, cut short or start with a brand.
        food: groceries and packaged food, including meat, dairy, bread, sweets and snacks.
        produce: fresh fruits, vegetables and herbs.
        drinks: water, juice, soda, coffee, tea, beer and wine.
        cleaning: products to clean the house, dishes and clothes.
        hygiene: personal care products, medicine and toilet paper.
        home: household items such as light bulbs, batteries and kitchen tools.
        pets: pet food and pet supplies.
        other: when you can't tell what the product is.
        Examples:
        "Bala fini minhoc" -> food
        "Scotch brite esponja" -> cleaning
        "Golden formula adulto" -> pets
        "Duracell aa" -> home
        "Antarctica 2l" -> drinks
        "Colgate total 12" -> hygiene
        "Xpt 4421" -> other
        """

        /// The product's name comes from the receipt, so it goes in the prompt, never the
        /// instructions.
        static func prompt(for name: String) -> String {
            "Product: \(name)"
        }
    }

    /// Turns dishes the person wants to cook into the ingredients to buy.
    enum ShopRecipeExpansion {

        static let id = "shop-recipe-expansion-v3"

        /// Read when a request starts, so the examples follow the app's current language.
        static var task: String {
            """
            The person writes what to add to a household shopping list. Some parts may be dishes they want to cook.
            dishes: for each dish mentioned, its name and the ingredients usually bought to make it for about 4 people, one per entry, with an amount when natural. Leave out water and salt. If no dish is mentioned, return no dishes.
            Write the dish names and the ingredients in the same language as the examples below.
            whoFor: who the dish is for, as written ("eu e Ana", "me and Ana", "todos", "everyone"). When the person speaks in the first person ("I want to make", "quero fazer") and names nobody else, use "eu". Empty if not said.
            otherItems: every other part of the text that is not about those dishes, copied exactly as written (items, amounts, prices, people). Empty if there is nothing else.
            Examples:
            \(IntelligencePrompts.localized(examples))
            """
        }

        /// Two worked examples per app language: a dish with other items, and a list with a dish.
        static let examples: [AppLanguage: String] = [
            .portuguese: """
            "quero fazer lasanha, e detergente para todos" -> dishes: lasanha ["1 pacote de massa para lasanha", "500 g de carne moída", "molho de tomate", "400 g de queijo muçarela", "200 g de presunto"], whoFor: "eu", otherItems: "detergente para todos"
            "2kg de arroz, ingredientes para bolo de cenoura" -> dishes: bolo de cenoura ["3 cenouras", "1 kg de farinha de trigo", "1 kg de açúcar", "12 ovos", "óleo"], whoFor: "", otherItems: "2kg de arroz"
            """,
            .english: """
            "I want to make lasagna, and dish soap for everyone" -> dishes: lasagna ["1 box of lasagna noodles", "500 g ground beef", "tomato sauce", "400 g mozzarella", "200 g ham"], whoFor: "eu", otherItems: "dish soap for everyone"
            "2kg of rice, ingredients for a carrot cake" -> dishes: carrot cake ["3 carrots", "1 kg flour", "1 kg sugar", "12 eggs", "vegetable oil"], whoFor: "", otherItems: "2kg of rice"
            """,
            .spanish: """
            "quiero hacer lasaña, y detergente para todos" -> dishes: lasaña ["1 paquete de pasta para lasaña", "500 g de carne molida", "salsa de tomate", "400 g de queso mozzarella", "200 g de jamón"], whoFor: "eu", otherItems: "detergente para todos"
            "2kg de arroz, ingredientes para un pastel de zanahoria" -> dishes: pastel de zanahoria ["3 zanahorias", "1 kg de harina", "1 kg de azúcar", "12 huevos", "aceite"], whoFor: "", otherItems: "2kg de arroz"
            """,
            .french: """
            "je veux faire des lasagnes, et du liquide vaisselle pour tous" -> dishes: lasagnes ["1 paquet de pâtes à lasagnes", "500 g de bœuf haché", "sauce tomate", "400 g de mozzarella", "200 g de jambon"], whoFor: "eu", otherItems: "liquide vaisselle pour tous"
            "2 kg de riz, ingrédients pour un gâteau aux carottes" -> dishes: gâteau aux carottes ["3 carottes", "1 kg de farine", "1 kg de sucre", "12 œufs", "huile"], whoFor: "", otherItems: "2 kg de riz"
            """,
            .chinese: """
            "我想做千层面，还有洗洁精给大家" -> dishes: 千层面 ["1 盒千层面皮", "500 克牛肉末", "番茄酱", "400 克马苏里拉奶酪", "200 克火腿"], whoFor: "eu", otherItems: "洗洁精给大家"
            "2公斤大米，胡萝卜蛋糕的材料" -> dishes: 胡萝卜蛋糕 ["3 根胡萝卜", "1 公斤面粉", "1 公斤糖", "12 个鸡蛋", "食用油"], whoFor: "", otherItems: "2公斤大米"
            """,
            .japanese: """
            "ラザニアを作りたい、あと食器用洗剤をみんなに" -> dishes: ラザニア ["ラザニア用パスタ 1箱", "牛ひき肉 500g", "トマトソース", "モッツァレラチーズ 400g", "ハム 200g"], whoFor: "eu", otherItems: "食器用洗剤をみんなに"
            "お米2kg、キャロットケーキの材料" -> dishes: キャロットケーキ ["にんじん 3本", "小麦粉 1kg", "砂糖 1kg", "卵 12個", "サラダ油"], whoFor: "", otherItems: "お米2kg"
            """,
            .korean: """
            "라자냐 만들고 싶어, 그리고 주방세제는 모두를 위해" -> dishes: 라자냐 ["라자냐 면 1팩", "다진 소고기 500g", "토마토 소스", "모차렐라 치즈 400g", "햄 200g"], whoFor: "eu", otherItems: "주방세제는 모두를 위해"
            "쌀 2kg, 당근 케이크 재료" -> dishes: 당근 케이크 ["당근 3개", "밀가루 1kg", "설탕 1kg", "달걀 12개", "식용유"], whoFor: "", otherItems: "쌀 2kg"
            """,
        ]

        /// The person's text goes in the prompt, never in the instructions.
        static func prompt(for text: String) -> String {
            "Text: \(text)"
        }
    }

    /// Suggests products for one supermarket section, from what's listed in it.
    enum ShopSectionIdeas {

        static let id = "shop-section-ideas-v3"

        /// Read when a request starts, so the examples follow the app's current language.
        static var task: String {
            """
            You help complete one section of a household shopping list. Suggest at most 2 products from that same supermarket section that people usually buy along with the ones listed there.
            Sections: food (groceries, meat, dairy, bread), produce (fruits, vegetables, herbs), drinks, cleaning (house, dishes and clothes), hygiene (personal care, toilet paper), home (household items), pets, other.
            Never suggest something already on the list, or a variant of it (another brand, size or type), nor anything under "Do not suggest". Only common, clear choices; if nothing fits, return an empty list.
            name: a short, common product name, in the same language as the examples below.
            Examples:
            \(IntelligencePrompts.localized(examples))
            """
        }

        static let examples: [AppLanguage: String] = [
            .portuguese: """
            cleaning: "detergente" -> "esponja", "sabão em pó"
            produce: "tomate, cebola" -> "alho", "alface"
            food: "macarrão" -> "molho de tomate", "queijo ralado"
            drinks: "café" -> "leite"
            """,
            .english: """
            cleaning: "dish soap" -> "sponge", "laundry detergent"
            produce: "tomato, onion" -> "garlic", "lettuce"
            food: "pasta" -> "tomato sauce", "grated cheese"
            drinks: "coffee" -> "milk"
            """,
            .spanish: """
            cleaning: "detergente" -> "esponja", "jabón en polvo"
            produce: "tomate, cebolla" -> "ajo", "lechuga"
            food: "pasta" -> "salsa de tomate", "queso rallado"
            drinks: "café" -> "leche"
            """,
            .french: """
            cleaning: "liquide vaisselle" -> "éponge", "lessive"
            produce: "tomate, oignon" -> "ail", "laitue"
            food: "pâtes" -> "sauce tomate", "fromage râpé"
            drinks: "café" -> "lait"
            """,
            .chinese: """
            cleaning: "洗洁精" -> "海绵", "洗衣粉"
            produce: "番茄, 洋葱" -> "大蒜", "生菜"
            food: "意大利面" -> "番茄酱", "芝士碎"
            drinks: "咖啡" -> "牛奶"
            """,
            .japanese: """
            cleaning: "食器用洗剤" -> "スポンジ", "洗濯洗剤"
            produce: "トマト, 玉ねぎ" -> "にんにく", "レタス"
            food: "パスタ" -> "トマトソース", "粉チーズ"
            drinks: "コーヒー" -> "牛乳"
            """,
            .korean: """
            cleaning: "주방세제" -> "수세미", "세탁세제"
            produce: "토마토, 양파" -> "마늘", "상추"
            food: "파스타" -> "토마토 소스", "파마산 치즈"
            drinks: "커피" -> "우유"
            """,
        ]

        /// The names are the person's text, so they go in the prompt.
        ///
        /// - Parameter avoiding: Products already shown or hidden; at most the 10 latest, to keep
        ///   the prompt short.
        static func prompt(section: String, sectionNames: [String], listNames: [String], avoiding: [String] = []) -> String {
            var lines = [
                "Section: \(section)",
                "In this section: \(sectionNames.joined(separator: ", "))",
                "Whole list: \(listNames.joined(separator: ", "))"
            ]
            if !avoiding.isEmpty {
                lines.append("Do not suggest: \(avoiding.suffix(10).joined(separator: ", "))")
            }
            return lines.joined(separator: "\n")
        }
    }

    /// Turns a chore description ("lavar a louça toda semana, urgente") into name, room,
    /// frequency, duration and priority. People are read by code, not by the model.
    enum ChoreParse {

        static let id = "chore-parse-v6"

        /// The frequency, duration and priority names match the `Generated…` enums in
        /// ChoreSuggestion.swift; keep them in sync. Read when a request starts, so the examples
        /// follow the app's current language.
        static var task: String {
            """
            You fill in a household chore form from what the person wrote or said.
            name: the chore itself, in the same language as the examples below, short (at most 18 characters), without frequency, dates or weekdays, room, people or urgency. Start with a verb when possible, like the examples.
            room: one name copied exactly from the house's rooms list, the room where the chore happens. Use "none" when no room clearly fits.
            frequency: what the person said ("todo dia", "todos os dias", "diariamente", "every day" -> daily; "toda semana", "every week" -> weekly; "a cada 15 dias", "every two weeks" -> fortnightly; "uma vez por mês", "once a month" -> monthly; "só hoje", "uma vez", "just today", "once" -> once; a single day without how often, like "amanhã", "sábado" or "dia 30" -> once). If they didn't say, choose how often this chore is usually done in a home: daily, weekly, fortnightly or monthly.
            duration: what the person said, or else how long the chore usually takes: quick (under 20 minutes), moderate (20 to 59 minutes), slow (60 to 89 minutes) or verySlow (90 minutes or more).
            priority: only when the person says how urgent it is: low ("sem pressa", "no rush"), medium, high ("importante", "important"), urgent ("urgente", "hoje", "urgent", "today"). Otherwise notSaid.
            details: how-to details the person said that fit no other field ("usar luva", "depois do jantar"), as a short sentence in their words. Never repeat the frequency, people, room or urgency there, and never add your own advice. Empty if there are none.
            steps: the parts or steps the person listed ("o vaso, a pia e o box" -> "Vaso", "Pia", "Box"), one short item each. Empty if they listed none; do not invent steps.
            Examples:
            \(IntelligencePrompts.localized(examples))
            """
        }

        /// Five worked examples per app language. Room names are the default rooms as shown in
        /// that language (the prompt lists the rooms translated).
        static let examples: [AppLanguage: String] = [
            .portuguese: """
            "eu vou lavar a louça todos os dias depois do jantar" -> name "Lavar a louça", room "Cozinha", frequency daily, duration quick, priority notSaid, details "Depois do jantar.", steps []
            "limpar o banheiro toda semana, urgente, usar luva, limpar o vaso, a pia e o box" -> name "Limpar o banheiro", room "Banheiro", frequency weekly, duration moderate, priority urgent, details "Usar luva.", steps ["Vaso", "Pia", "Box"]
            "tirar o lixo" -> name "Tirar o lixo", room "Cozinha", frequency daily, duration quick, priority notSaid, details "", steps []
            "trocar a roupa de cama a cada 15 dias" -> name "Trocar roupa de cama", room "Quarto", frequency fortnightly, duration moderate, priority notSaid, details "", steps []
            "limpar a geladeira" -> name "Limpar a geladeira", room "Cozinha", frequency monthly, duration slow, priority notSaid, details "", steps []
            """,
            .english: """
            "I'll wash the dishes every day after dinner" -> name "Wash the dishes", room "Kitchen", frequency daily, duration quick, priority notSaid, details "After dinner.", steps []
            "clean the bathroom every week, urgent, use gloves, clean the toilet, the sink and the shower" -> name "Clean the bathroom", room "Bathroom", frequency weekly, duration moderate, priority urgent, details "Use gloves.", steps ["Toilet", "Sink", "Shower"]
            "take out the trash" -> name "Take out the trash", room "Kitchen", frequency daily, duration quick, priority notSaid, details "", steps []
            "change the bed sheets every 15 days" -> name "Change bed sheets", room "Bedroom", frequency fortnightly, duration moderate, priority notSaid, details "", steps []
            "clean the fridge" -> name "Clean the fridge", room "Kitchen", frequency monthly, duration slow, priority notSaid, details "", steps []
            """,
            .spanish: """
            "voy a lavar los platos todos los días después de cenar" -> name "Lavar los platos", room "Cocina", frequency daily, duration quick, priority notSaid, details "Después de cenar.", steps []
            "limpiar el baño cada semana, urgente, usar guantes, limpiar el inodoro, el lavabo y la ducha" -> name "Limpiar el baño", room "Baño", frequency weekly, duration moderate, priority urgent, details "Usar guantes.", steps ["Inodoro", "Lavabo", "Ducha"]
            "sacar la basura" -> name "Sacar la basura", room "Cocina", frequency daily, duration quick, priority notSaid, details "", steps []
            "cambiar la ropa de cama cada 15 días" -> name "Cambiar sábanas", room "Dormitorio", frequency fortnightly, duration moderate, priority notSaid, details "", steps []
            "limpiar la nevera" -> name "Limpiar la nevera", room "Cocina", frequency monthly, duration slow, priority notSaid, details "", steps []
            """,
            .french: """
            "je vais faire la vaisselle tous les jours après le dîner" -> name "Faire la vaisselle", room "Cuisine", frequency daily, duration quick, priority notSaid, details "Après le dîner.", steps []
            "nettoyer les toilettes chaque semaine, urgent, mettre des gants, la cuvette, le lavabo et le sol" -> name "Nettoyer les WC", room "Salle de bain", frequency weekly, duration moderate, priority urgent, details "Mettre des gants.", steps ["Cuvette", "Lavabo", "Sol"]
            "sortir la poubelle" -> name "Sortir la poubelle", room "Cuisine", frequency daily, duration quick, priority notSaid, details "", steps []
            "changer les draps tous les 15 jours" -> name "Changer les draps", room "Chambre", frequency fortnightly, duration moderate, priority notSaid, details "", steps []
            "nettoyer le frigo" -> name "Nettoyer le frigo", room "Cuisine", frequency monthly, duration slow, priority notSaid, details "", steps []
            """,
            .chinese: """
            "我每天晚饭后洗碗" -> name "洗碗", room "厨房", frequency daily, duration quick, priority notSaid, details "晚饭后。", steps []
            "每周打扫浴室，很急，戴手套，清洁马桶、洗手台和淋浴间" -> name "打扫浴室", room "浴室", frequency weekly, duration moderate, priority urgent, details "戴手套。", steps ["马桶", "洗手台", "淋浴间"]
            "倒垃圾" -> name "倒垃圾", room "厨房", frequency daily, duration quick, priority notSaid, details "", steps []
            "每 15 天换一次床单" -> name "换床单", room "卧室", frequency fortnightly, duration moderate, priority notSaid, details "", steps []
            "清洁冰箱" -> name "清洁冰箱", room "厨房", frequency monthly, duration slow, priority notSaid, details "", steps []
            """,
            .japanese: """
            "毎日夕食後に食器を洗う" -> name "食器を洗う", room "キッチン", frequency daily, duration quick, priority notSaid, details "夕食後。", steps []
            "毎週浴室を掃除する、急ぎ、手袋を使う、トイレと洗面台とシャワー" -> name "浴室を掃除する", room "バスルーム", frequency weekly, duration moderate, priority urgent, details "手袋を使う。", steps ["トイレ", "洗面台", "シャワー"]
            "ゴミ出し" -> name "ゴミ出し", room "キッチン", frequency daily, duration quick, priority notSaid, details "", steps []
            "15日ごとにシーツを替える" -> name "シーツを替える", room "寝室", frequency fortnightly, duration moderate, priority notSaid, details "", steps []
            "冷蔵庫を掃除する" -> name "冷蔵庫を掃除する", room "キッチン", frequency monthly, duration slow, priority notSaid, details "", steps []
            """,
            .korean: """
            "매일 저녁 먹고 설거지할게" -> name "설거지하기", room "주방", frequency daily, duration quick, priority notSaid, details "저녁 식사 후.", steps []
            "매주 욕실 청소, 급함, 장갑 끼기, 변기랑 세면대랑 샤워부스" -> name "욕실 청소", room "욕실", frequency weekly, duration moderate, priority urgent, details "장갑 끼기.", steps ["변기", "세면대", "샤워부스"]
            "쓰레기 버리기" -> name "쓰레기 버리기", room "주방", frequency daily, duration quick, priority notSaid, details "", steps []
            "15일마다 침대 시트 교체" -> name "침대 시트 교체", room "침실", frequency fortnightly, duration moderate, priority notSaid, details "", steps []
            "냉장고 청소" -> name "냉장고 청소", room "주방", frequency monthly, duration slow, priority notSaid, details "", steps []
            """,
        ]

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

        static let id = "chore-checklist-ideas-v3"

        /// Read when a request starts, so the examples follow the app's current language.
        static var task: String {
            """
            You suggest a checklist for a household chore: up to 5 short, concrete steps or parts (at most 40 characters each) that people usually do for it, in the same language as the examples below.
            Only physical steps, no advice or safety tips. Never repeat an item already on the checklist or one under "Do not suggest". If the chore is too simple to split, or nothing new fits, return an empty list.
            Examples:
            \(IntelligencePrompts.localized(examples))
            """
        }

        static let examples: [AppLanguage: String] = [
            .portuguese: """
            "Limpar o banheiro" -> "Vaso", "Pia", "Box", "Espelho", "Trocar as toalhas"
            "Lavar a louça" -> "Pratos e copos", "Panelas", "Secar e guardar", "Limpar a pia"
            "Tirar o lixo" -> "Lixo da cozinha", "Lixo do banheiro", "Separar recicláveis"
            """,
            .english: """
            "Clean the bathroom" -> "Toilet", "Sink", "Shower", "Mirror", "Change the towels"
            "Wash the dishes" -> "Plates and glasses", "Pots and pans", "Dry and put away", "Clean the sink"
            "Take out the trash" -> "Kitchen trash", "Bathroom trash", "Sort recyclables"
            """,
            .spanish: """
            "Limpiar el baño" -> "Inodoro", "Lavabo", "Ducha", "Espejo", "Cambiar las toallas"
            "Lavar los platos" -> "Platos y vasos", "Ollas", "Secar y guardar", "Limpiar el fregadero"
            "Sacar la basura" -> "Basura de la cocina", "Basura del baño", "Separar reciclables"
            """,
            .french: """
            "Nettoyer la salle de bain" -> "Toilettes", "Lavabo", "Douche", "Miroir", "Changer les serviettes"
            "Faire la vaisselle" -> "Assiettes et verres", "Casseroles", "Essuyer et ranger", "Nettoyer l’évier"
            "Sortir la poubelle" -> "Poubelle de la cuisine", "Poubelle de la salle de bain", "Trier le recyclage"
            """,
            .chinese: """
            "打扫浴室" -> "马桶", "洗手台", "淋浴间", "镜子", "更换毛巾"
            "洗碗" -> "盘子和杯子", "锅具", "擦干收好", "清洁水槽"
            "倒垃圾" -> "厨房垃圾", "浴室垃圾", "分类回收"
            """,
            .japanese: """
            "浴室を掃除する" -> "浴槽", "洗面台", "シャワー", "鏡", "タオルを替える"
            "食器を洗う" -> "お皿とコップ", "鍋", "拭いて片付ける", "シンクを掃除"
            "ゴミ出し" -> "キッチンのゴミ", "浴室のゴミ", "資源ゴミを分ける"
            """,
            .korean: """
            "욕실 청소" -> "변기", "세면대", "샤워부스", "거울", "수건 교체"
            "설거지하기" -> "접시와 컵", "냄비", "물기 닦고 정리", "싱크대 청소"
            "쓰레기 버리기" -> "주방 쓰레기", "욕실 쓰레기", "분리수거"
            """,
        ]

        /// The chore's name and what's already listed are the person's text, so they go here.
        ///
        /// - Parameter avoiding: Ideas already shown or hidden; at most the 10 latest, to keep the
        ///   prompt short.
        static func prompt(name: String, room: String?, existing: [String], avoiding: [String] = []) -> String {
            var lines = ["Chore: \(name)"]
            if let room { lines.append("Room: \(room)") }
            if !existing.isEmpty { lines.append("Already on the checklist: \(existing.joined(separator: ", "))") }
            if !avoiding.isEmpty { lines.append("Do not suggest: \(avoiding.suffix(10).joined(separator: ", "))") }
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
