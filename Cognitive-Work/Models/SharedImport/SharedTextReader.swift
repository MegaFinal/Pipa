//
//  SharedTextReader.swift
//  Cognitive-Work
//
//  Created by anshu Li on 18/11/26.
//

import Foundation

/// Whether a shared line becomes something to buy or a chore.
enum SharedImportKind: Equatable {
    case shopping
    case chore
}

/// Reads text shared from another app (a WhatsApp list, a note) with plain code, no AI.
///
/// This is the free plan of ``SharedImportView``, and also the first step on Premium: the text is
/// split into lines here and each line is guessed as a purchase or a chore; the AI then fills the
/// cards from those lines. The person can move any card to the other kind.
///
/// - Shopping: only name and amount ("2kg arroz" → arroz, 2 kg).
/// - Chores: only name and the day said ("lavar a louça amanhã" → lavar a louça, tomorrow), read
///   by ``ChoreDateReader``, the same code the AI path uses for dates.
enum SharedTextReader {

    /// More lines than this are cut: a shared text that long is rarely a list.
    static let maxLines = 30

    // MARK: - Lines

    /// Bullets, checkboxes and numbering copied from notes or chat apps ("- ", "• ", "☐ ", "1. ").
    private static let bulletPattern = #/^\s*(?:[-–—•*·◦▪]|\[\s?[xX✓]?\s?\]|[☐☑✅✔✓]+|\d{1,2}[.)])\s*/#

    /// One line per item, without bullets, titles ("Lista do mercado:") or empty lines.
    static func lines(in text: String) -> [(text: String, kind: SharedImportKind)] {
        text
            .split(whereSeparator: \.isNewline)
            .map { line in
                String(line)
                    .replacing(bulletPattern, with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;")))
            }
            .filter { !$0.isEmpty && !$0.hasSuffix(":") }
            .prefix(maxLines)
            .map { (text: $0, kind: kind(of: $0)) }
    }

    // MARK: - Purchase or chore

    /// Words that ask to buy something; they start a purchase and are dropped from its name.
    private static let buyPrefixes = [
        "comprar ", "compra ", "compre ", "falta ", "faltou ", "acabou o ", "acabou a ", "acabou ",
        "buy ", "get ", "acheter ", "買う", "买", "사기 "
    ]

    /// Verbs (infinitive, imperative and 3rd person) that start a house chore, folded (no
    /// accents, lowercase). Portuguese first, then English, Spanish and French.
    private static let choreVerbs: Set<String> = [
        // Portuguese
        "lavar", "lava", "lave", "limpar", "limpa", "limpe", "varrer", "varre", "varra",
        "passar", "passa", "passe", "tirar", "tira", "tire", "arrumar", "arruma", "arrume",
        "organizar", "organiza", "organize", "trocar", "troca", "troque", "regar", "rega", "regue",
        "levar", "leva", "leve", "pagar", "paga", "pague", "fazer", "faz", "faca",
        "estender", "estende", "estenda", "dobrar", "dobra", "dobre", "aspirar", "aspira", "aspire",
        "passear", "alimentar", "cozinhar", "cozinha", "recolher", "recolhe", "esvaziar", "esvazia",
        "guardar", "guarda", "guarde", "consertar", "conserta", "desentupir", "secar", "seca",
        "lustrar", "colocar", "coloca", "coloque", "botar", "bota", "cuidar", "cuida", "jogar",
        "joga", "separar", "separa", "descongelar", "buscar", "busca", "busque", "agendar",
        "marcar", "ligar", "liga", "tomar", "esfregar", "esfrega", "higienizar", "desinfetar",
        "polir", "encerar", "trocar", "abastecer", "repor", "dar",
        // English
        "wash", "clean", "sweep", "mop", "vacuum", "tidy", "take", "do", "make", "cook", "fold",
        "iron", "water", "walk", "feed", "pay", "empty", "fix", "change", "dust", "scrub", "put",
        // Spanish
        "limpiar", "limpia", "barrer", "barre", "fregar", "friega", "sacar", "saca", "ordenar",
        "ordena", "planchar", "plancha", "cocinar", "cocina", "doblar", "dobla", "regar", "riega",
        "tender", "tiende", "pasear", "hacer", "haz", "recoger", "recoge", "vaciar", "vacia",
        // French
        "laver", "nettoyer", "balayer", "ranger", "repasser", "cuisiner", "sortir", "plier",
        "arroser", "faire", "passer", "vider", "aspirer", "promener", "nourrir", "payer"
    ]

    /// Chore words for languages without spaces between words (Chinese, Japanese, Korean).
    private static let choreFragments = [
        "洗", "打扫", "扫地", "拖地", "倒垃圾", "整理", "收拾", "做饭", "晾", "叠", "擦",
        "掃除", "片付け", "ゴミ", "料理", "洗濯", "皿洗い",
        "청소", "설거지", "빨래", "정리", "쓰레기", "요리", "닦"
    ]

    /// Units and quantity words typical of shopping lists, folded.
    private static let shoppingHints: Set<String> = [
        "kg", "g", "gr", "l", "lt", "ml", "un", "und", "unid", "pct", "pacote", "pacotes",
        "caixa", "caixas", "duzia", "lata", "latas", "garrafa", "garrafas", "litro", "litros",
        "quilo", "quilos", "kilo", "kilos", "maco", "rolo", "rolos", "pack", "box", "bottle"
    ]

    /// A first guess: chores start with a verb ("lavar a louça"), shopping lists are nouns
    /// ("leite", "2kg arroz"). Anything else counts as shopping, the more common kind of list.
    static func kind(of line: String) -> SharedImportKind {
        let lower = line.lowercased()
        if buyPrefixes.contains(where: { lower.hasPrefix($0) }) { return .shopping }

        let words = folded(line)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        if let first = words.first {
            if first.first?.isNumber == true { return .shopping } // "2 leite"
            if words.contains(where: shoppingHints.contains) { return .shopping } // "arroz 5 kg"
            if choreVerbs.contains(first) { return .chore }
        }
        if choreFragments.contains(where: { line.contains($0) }) { return .chore }
        return .shopping
    }

    // MARK: - Shopping: name and amount

    /// Units written in shopping lists, folded, with how they're saved. A dozen is saved as 12
    /// units.
    private static let units: [String: (unit: UnitMeasurement, multiplier: Double)] = [
        "kg": (.kilogram, 1), "kgs": (.kilogram, 1), "quilo": (.kilogram, 1), "quilos": (.kilogram, 1),
        "kilo": (.kilogram, 1), "kilos": (.kilogram, 1),
        "g": (.gram, 1), "gr": (.gram, 1), "grs": (.gram, 1), "grama": (.gram, 1), "gramas": (.gram, 1),
        "l": (.liter, 1), "lt": (.liter, 1), "lts": (.liter, 1), "litro": (.liter, 1), "litros": (.liter, 1),
        "ml": (.milliliter, 1),
        "un": (.unit, 1), "und": (.unit, 1), "unid": (.unit, 1), "unidade": (.unit, 1),
        "unidades": (.unit, 1), "x": (.unit, 1),
        "duzia": (.unit, 12), "duzias": (.unit, 12),
        "pct": (.package, 1), "pcts": (.package, 1), "pacote": (.package, 1), "pacotes": (.package, 1),
        "caixa": (.package, 1), "caixas": (.package, 1), "lata": (.package, 1), "latas": (.package, 1),
        "garrafa": (.package, 1), "garrafas": (.package, 1), "rolo": (.package, 1), "rolos": (.package, 1),
        "pack": (.package, 1), "packs": (.package, 1)
    ]

    /// "2kg de arroz", "2 kg arroz", "12 ovos", "x2 leite".
    private static let leadingAmount = #/^(?:x\s*)?(\d+(?:[.,]\d+)?)\s*([^\d\s]*)\s+(?:(?:de|of|d')\s+)?(.+)$/#.ignoresCase()
    /// "arroz 2kg", "arroz - 2 kg", "leite x2", "ovos (12)".
    private static let trailingAmount = #/^(.+?)\s*[-–:(]?\s*(?:x\s*)?(\d+(?:[.,]\d+)?)\s*([^\d\s)]*)\)?$/#.ignoresCase()

    /// Name and amount of a purchase line. Category, price and people stay for the person (or
    /// the AI on Premium) to fill.
    static func shopItem(from line: String) -> ShopItemSuggestion {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if let prefix = buyPrefixes.first(where: { text.lowercased().hasPrefix($0) }) {
            text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }

        var name = text
        var amount: (quantity: Int, unit: UnitMeasurement) = (1, .unit)

        if let match = text.firstMatch(of: leadingAmount),
           let parsed = amountFrom(number: String(match.1), unitWord: String(match.2)) {
            name = String(match.3)
            amount = parsed
        } else if let match = text.firstMatch(of: leadingAmount),
                  String(match.2).isEmpty || unitFor(String(match.2)) == nil,
                  let number = number(from: String(match.1)) {
            // "2 leite": the word after the number is the product, not a unit.
            name = (String(match.2) + " " + String(match.3)).trimmingCharacters(in: .whitespaces)
            amount = (clamped(number), .unit)
        } else if let match = text.firstMatch(of: trailingAmount),
                  let parsed = amountFrom(number: String(match.2), unitWord: String(match.3)) {
            name = String(match.1)
            amount = parsed
        }

        return ShopItemSuggestion(
            input: line,
            name: cleanedName(name, limit: TextLimits.shopItemName),
            quantity: amount.quantity,
            unit: amount.unit,
            category: .other,
            totalPrice: nil,
            consumers: nil
        )
    }

    private static func unitFor(_ word: String) -> (unit: UnitMeasurement, multiplier: Double)? {
        let key = folded(word).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return key.isEmpty ? (.unit, 1) : units[key]
    }

    private static func number(from text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    /// Turns "1,5" + "kg" into 1500 g (quantities are whole numbers in the form).
    private static func amountFrom(number text: String, unitWord: String) -> (quantity: Int, unit: UnitMeasurement)? {
        guard let value = number(from: text), value > 0, let found = unitFor(unitWord) else { return nil }
        var quantity = value * found.multiplier
        var unit = found.unit
        if quantity.rounded() != quantity {
            switch unit {
            case .kilogram: quantity *= 1000; unit = .gram
            case .liter: quantity *= 1000; unit = .milliliter
            default: break
            }
        }
        return (clamped(quantity), unit)
    }

    private static func clamped(_ value: Double) -> Int {
        let range = QuantityStepper.allowedRange
        return min(max(Int(value.rounded()), range.lowerBound), range.upperBound)
    }

    // MARK: - Chores: name and day

    /// Day words removed from a chore's name once ``ChoreDateReader`` read the date
    /// ("lavar a louça amanhã" → "lavar a louça").
    private static let dayPattern = #/(?:\s+|^)(?:(?:no|na|nesta|neste|esta|este|pr[oó]xim[oa]|on|next|this|el|la|le|ce)\s+)?(?:depois\s+de\s+amanh[ãa]|amanh[ãa]|hoje|today|tomorrow|ma[ñn]ana|hoy|demain|aujourd'hui|segunda(?:-feira)?|ter[çc]a(?:-feira)?|quarta(?:-feira)?|quinta(?:-feira)?|sexta(?:-feira)?|s[áa]bado|domingo|monday|tuesday|wednesday|thursday|friday|saturday|sunday|lunes|martes|mi[ée]rcoles|jueves|viernes|lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche|dia\s+\d{1,2}(?:/\d{1,2})?|\d{1,2}/\d{1,2})(?=\s|$|[,.!])/#.ignoresCase()

    /// Name and day of a chore line. Room, frequency and people stay for the person (or the AI
    /// on Premium) to fill.
    static func chore(from line: String) -> (name: String, date: Date?) {
        let date = ChoreDateReader.date(in: line)
        var name = line
        if date != nil {
            name = line.replacing(dayPattern, with: "")
        }
        return (cleanedName(name, limit: TextLimits.choreName), date)
    }

    // MARK: - Helpers

    /// Trims leftovers ("- ", ","), capitalizes the first letter and keeps it within the form's
    /// limit.
    private static func cleanedName(_ name: String, limit: Int) -> String {
        let trimmed = name.trimmingCharacters(
            in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;:-–—.()"))
        )
        let capitalized = trimmed.prefix(1).uppercased(with: L10n.locale) + trimmed.dropFirst()
        return String(capitalized.prefix(limit)).trimmingCharacters(in: .whitespaces)
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
