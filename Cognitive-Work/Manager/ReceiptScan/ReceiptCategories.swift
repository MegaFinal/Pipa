//
//  ReceiptCategories.swift
//  Cognitive-Work
//
//  Created by anshu Li on 05/11/26.
//

import Foundation

/// Guesses the aisle of a product read from a receipt that wasn't on the list, from the words
/// of its name once spelled out (``ReceiptAbbreviations``): "Leite condensado" -> Alimentos,
/// "Detergente líquido" -> Produtos de limpeza. Plain words, no model.
///
/// In Portuguese the product comes first and its details after ("Molho de tomate" is a sauce,
/// not a tomato), so the first word the table knows decides; a few two-word names are checked
/// before their first word ("Água sanitária" isn't a drink). A brand first ("OMO SABAO PO") is
/// skipped, since the table doesn't know it.
enum ReceiptCategories {

    /// The aisle of `name`, or `nil` when no word of it is known.
    static func guess(_ name: String) -> ShopItemCategory? {
        let words = ReceiptNameMemory.normalized(name).split(separator: " ").map(String.init)
        for index in words.indices {
            if index + 1 < words.count {
                let pair = words[index] + " " + words[index + 1]
                if let category = phrases[pair] { return category }
                // "Creme de leite", "Papel de alumínio".
                if index + 2 < words.count, ["de", "da", "do"].contains(words[index + 1]),
                   let category = phrases[words[index] + " " + words[index + 2]] {
                    return category
                }
            }
            if let category = category(of: words[index]) { return category }
        }
        return nil
    }

    /// One word, or the word without a plural "s" or "es" ("bananas" -> "banana"). Plurals that
    /// change more ("limões", "pães") are in the table themselves.
    private static func category(of word: String) -> ShopItemCategory? {
        if let category = words[word] { return category }
        if word.count >= 4, word.hasSuffix("s"), let category = words[String(word.dropLast())] { return category }
        if word.count >= 5, word.hasSuffix("es"), let category = words[String(word.dropLast(2))] { return category }
        return nil
    }

    /// Two-word names whose first word alone would point elsewhere (lowercased, no accents).
    private static let phrases: [String: ShopItemCategory] = [
        "agua sanitaria": .cleaning, "papel toalha": .cleaning, "saco lixo": .cleaning,
        "la aco": .cleaning, "tira manchas": .cleaning, "papel higienico": .hygiene,
        "creme dental": .hygiene, "pasta dente": .hygiene, "fio dental": .hygiene,
        "escova dente": .hygiene, "escova dental": .hygiene, "creme leite": .food,
        "leite coco": .food, "bebida lactea": .food, "batata palha": .food, "milho verde": .food,
        "papel aluminio": .home, "filme pvc": .home, "areia gato": .pets, "areia sanitaria": .pets,
        "agua coco": .drinks, "cha gelado": .drinks, "alcool gel": .hygiene,
    ]

    /// Words that tell the aisle (lowercased, no accents). Ambiguous ones ("creme", "papel",
    /// "salsa") are left out: "Outros" is better than a wrong aisle.
    private static let words: [String: ShopItemCategory] = {
        var table: [String: ShopItemCategory] = [:]
        func add(_ category: ShopItemCategory, _ list: String) {
            for word in list.split(separator: " ") { table[String(word)] = category }
        }
        add(.food, """
            leite queijo presunto mortadela salame manteiga margarina requeijao iogurte coalhada \
            pao bisnaguinha torrada biscoito bolacha wafer cookie rosquinha bolo chocolate bombom \
            bala chiclete pirulito doce geleia mel achocolatado nescau toddy acucar adocante cafe \
            arroz feijao macarrao lasanha nhoque farinha farofa fuba aveia granola cereal tapioca \
            polvilho amido fermento gelatina pudim azeite oleo vinagre sal tempero caldo molho \
            extrato maionese ketchup catchup mostarda azeitona milho ervilha sardinha atum frango \
            carne peito coxa sobrecoxa asa linguica salsicha hamburguer bacon file salmao tilapia \
            peixe camarao picanha alcatra patinho acem costela lombo bisteca pernil peru nuggets \
            empanado ovo ovos pizza salgadinho chips pipoca amendoim castanha sorvete polpa \
            iogurtes requeijoes queijos paes
            """)
        add(.produce, """
            banana maca laranja limao limoes tomate cebola alho batata cenoura alface abobora \
            abobrinha pepino pimentao berinjela brocolis couve repolho mandioca aipim mamao \
            melancia melao abacaxi uva morango manga pera kiwi abacate goiaba maracuja tangerina \
            mexerica coentro cebolinha salsinha rucula agriao espinafre beterraba chuchu quiabo \
            hortalica gengibre inhame vagem jilo maxixe caqui ameixa pessego
            """)
        add(.drinks, """
            agua refrigerante refri suco cerveja vinho espumante energetico isotonico cha \
            kombucha coca guarana pepsi fanta sprite schweppes heineken brahma skol budweiser \
            stella amstel vodka whisky cachaca gin rum licor bebida
            """)
        add(.cleaning, """
            detergente sabao amaciante desinfetante alvejante limpador multiuso esponja bombril \
            pano rodo vassoura lustra cera cloro lysoform pinho ype omo comfort ariel brilhante \
            veja sapolio flanela
            """)
        add(.hygiene, """
            sabonete shampoo xampu condicionador desodorante absorvente fralda fraldas lenco \
            cotonete algodao barbear lamina protetor hidratante enxaguante antisseptico curativo \
            dipirona paracetamol ibuprofeno remedio vitamina escova
            """)
        add(.home, """
            lampada pilha pilhas vela fosforo isqueiro carvao extensao descartavel guardanapo \
            filtro tomada
            """)
        add(.pets, """
            racao petisco whiskas pedigree areia
            """)
        return table
    }()
}
