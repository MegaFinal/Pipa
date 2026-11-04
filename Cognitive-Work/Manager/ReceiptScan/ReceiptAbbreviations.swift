//
//  ReceiptAbbreviations.swift
//  Cognitive-Work
//
//  Created by anshu Li on 04/11/26.
//

import Foundation

/// Spells out the abbreviations Brazilian supermarkets print on receipts, so a product reads
/// like a list item ("LTE COND.MOC.TP 395g" -> "Leite condensado moc tp 395g") and matches one
/// (``ReceiptItemMatcher``). Only whole words are replaced; anything not in the table stays as
/// printed. A product the table misses is learned once the person names or links it
/// (``ReceiptNameMemory``).
nonisolated enum ReceiptAbbreviations {

    /// A receipt name as the list would show it. Names printed in capitals (supermarkets) are
    /// spelled out and lowercased with a capital first letter; names already in mixed case
    /// (restaurants) are kept.
    static func expand(_ name: String) -> String {
        let letters = name.filter(\.isLetter)
        guard !letters.isEmpty, letters.filter(\.isUppercase).count * 5 >= letters.count * 4 else { return name }

        let words = name
            .split(whereSeparator: { $0.isWhitespace || $0 == "." })
            .map { piece -> String in
                let word = piece.lowercased()
                return table[folded(word)] ?? word
            }
        let text = words.joined(separator: " ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// Lowercased, without accents ("PÃO" -> "pao").
    private static func folded(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Abbreviation (lowercased, no accents) -> word. Ambiguous ones ("sab": sabão or
    /// sabonete, "mac": macarrão or maçã) are left out on purpose: a wrong word is worse than
    /// the abbreviation.
    private static let table: [String: String] = [
        // Dairy and cold cuts
        "lte": "leite", "cond": "condensado", "desn": "desnatado",
        "semidesn": "semidesnatado", "semid": "semidesnatado", "integ": "integral",
        "qj": "queijo", "qjo": "queijo", "muss": "muçarela", "mus": "muçarela", "mussar": "muçarela",
        "pres": "presunto", "presunt": "presunto", "mort": "mortadela", "mant": "manteiga",
        "marg": "margarina", "req": "requeijão", "requeij": "requeijão", "iog": "iogurte",
        "beb": "bebida", "lac": "láctea", "lact": "lactose", "fat": "fatiado", "fatiad": "fatiado",
        "cr": "creme",
        // Bakery, sweets and breakfast
        "pao": "pão", "frances": "francês", "bisc": "biscoito", "rech": "recheado",
        "choc": "chocolate", "achoc": "achocolatado", "cafe": "café", "acucar": "açúcar", 
        "caf": "café", "torr": "torrado", "moid": "moído", "acuc": "açúcar", "refin": "refinado",
        "crist": "cristal",
        // Pantry
        "arr": "arroz", "feij": "feijão", "feijao": "feijão", "macarr": "macarrão", "macarrao": "macarrão", 
        "far": "farinha", "farin": "farinha", "trig": "trigo", "mand": "mandioca",
        "azeit": "azeite", "az": "azeite", "extrav": "extravirgem", "vinag": "vinagre",
        "temp": "tempero", "mol": "molho", "molh": "molho", "tom": "tomate", "extr": "extrato",
        "maion": "maionese", "ketc": "ketchup", "most": "mostarda", "azeiton": "azeitona",
        "milh": "milho", "ervil": "ervilha", "sard": "sardinha",
        // Meat, poultry and fish
        "fgo": "frango", "frg": "frango", "peit": "peito", "cox": "coxa", "sobrec": "sobrecoxa",
        "carn": "carne", "bov": "bovina", "suin": "suína", "salm": "salmão", "salmao": "salmão", "file": "filé",
        "ling": "linguiça", "linguic": "linguiça", "salsich": "salsicha", "hamb": "hambúrguer",
        "cong": "congelado", "resf": "resfriado", "resfr": "resfriado", "ov": "ovos",
        // Produce
        "ban": "banana", "ceb": "cebola", "cebol": "cebola",
        "cenour": "cenoura", "alf": "alface", "lim": "limão", "limao": "limão", "lar": "laranja",
        "abob": "abóbora", "hort": "hortaliça",
        // Drinks
        "refrig": "refrigerante", "refri": "refrigerante", "refr": "refrigerante",
        "cerv": "cerveja", "vinh": "vinho", "energ": "energético", "isot": "isotônico",
        "min": "mineral", "nat": "natural",
        // Cleaning
        "deterg": "detergente", "det": "detergente", "liq": "líquido", "amac": "amaciante",
        "desinf": "desinfetante", "sabao": "sabão", "po": "pó", "sanit": "sanitária",
        "limp": "limpador", "louc": "louças", "roup": "roupas", "esponj": "esponja",
        // Hygiene
        "pap": "papel", "hig": "higiênico", "toal": "toalha", "dent": "dental",
        "desod": "desodorante", "sabon": "sabonete", "shamp": "shampoo", "condic": "condicionador",
        "absorv": "absorvente", "fral": "fralda", "esc": "escova",
        // Descriptions
        "bco": "branco", "verm": "vermelho", "trad": "tradicional", "tradic": "tradicional",
        "orig": "original", "peq": "pequeno", "gde": "grande", "unid": "unidade",
    ]
}
