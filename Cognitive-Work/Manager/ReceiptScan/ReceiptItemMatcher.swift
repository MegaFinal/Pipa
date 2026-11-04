//
//  ReceiptItemMatcher.swift
//  Cognitive-Work
//
//  Created by anshu Li on 04/11/26.
//

import Foundation

/// Pairs receipt lines with shopping-list items by their names, in plain code (no AI).
///
/// Receipts abbreviate and add brands and sizes ("LTE COND.MOC.TP 395g" for "leite
/// condensado"), so a list word counts as found in a line when one of the line's words is the
/// same word (or its plural), the start of it ("COND" -> "condensado"), or its letters in order
/// with the same first letter ("LTE" -> "leite", "QJ" -> "queijo").
/// The person confirms every pair on the review screen, so a near miss is cheap; a wrong pair
/// is avoided by requiring every word of a short list name, and the list name's first word on
/// the receipt name's first word: receipts print the product type first ("IOG.BAT.NAT" is a
/// yogurt, not "batata"; "MA.QUALY C/SAL" is margarine, not "sal").
nonisolated enum ReceiptItemMatcher {

    /// For each list item (by index), the receipt line (by index) that is the same product.
    /// Each line and each item is used at most once; the best-scoring pairs win, so "Leite"
    /// takes "LEITE ITALAC" and leaves "LTE COND.MOC" to "Leite condensado".
    static func match(receiptNames: [String], listNames: [String]) -> [Int: Int] {
        let receiptWords = receiptNames.map(receiptTokens(in:))
        var pairs: [(item: Int, line: Int, score: Double)] = []

        for (itemIndex, name) in listNames.enumerated() {
            let words = listWords(in: name)
            guard !words.isEmpty else { continue }

            for (lineIndex, tokens) in receiptWords.enumerated() where !tokens.isEmpty {
                guard let firstToken = tokens.first, let firstWord = words.first,
                      quality(of: firstToken, for: firstWord) > 0 else { continue }
                // How well each list word was found in the line (0 when it wasn't).
                let qualities = words.map { word in tokens.map { quality(of: $0, for: word) }.max() ?? 0 }
                let found = qualities.filter { $0 > 0 }.count
                let coverage = Double(found) / Double(words.count)
                // Short names need every word; longer ones may miss one ("arroz branco tipo 1").
                guard coverage >= (words.count <= 2 ? 1 : 0.66) else { continue }

                // Fewer extra words on the line means a closer product.
                let score = coverage * 10 + qualities.reduce(0, +) - Double(tokens.count) * 0.1
                pairs.append((itemIndex, lineIndex, score))
            }
        }

        var result: [Int: Int] = [:]
        var usedLines = Set<Int>()
        for pair in pairs.sorted(by: { $0.score > $1.score })
        where result[pair.item] == nil && !usedLines.contains(pair.line) {
            result[pair.item] = pair.line
            usedLines.insert(pair.line)
        }
        return result
    }

    // MARK: - Words

    /// Words of a list name that identify the product: lowercased, no accents, without
    /// connectors ("Pão de forma" -> ["pao", "forma"]).
    static func listWords(in name: String) -> [String] {
        letterWords(in: name).filter { $0.count >= 2 && !connectors.contains($0) }
    }

    /// Words of a receipt line, without sizes and units ("LTE COND.MOC.TP 395g" -> ["lte",
    /// "cond", "moc", "tp"]).
    static func receiptTokens(in name: String) -> [String] {
        letterWords(in: name).filter { $0.count >= 2 && !units.contains($0) }
    }

    private static func letterWords(in text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
    }

    private static let connectors: Set<String> = ["de", "da", "do", "das", "dos", "com", "sem", "para", "em", "e", "o", "a"]
    private static let units: Set<String> = ["kg", "gr", "ml", "lt", "un", "und", "pc", "pct", "cx"]

    // MARK: - Comparing one word

    /// How surely receipt word `token` is list word `word`: 1 when equal, less for a prefix or
    /// an abbreviation, 0 when it isn't.
    static func quality(of token: String, for word: String) -> Double {
        if token == word || singular(token) == singular(word) { return 1 }
        // "cond" -> "condensado"
        if token.count >= 3, word.hasPrefix(token) { return 0.8 }
        // "detergentes" for "detergente"; not for short words ("sal" isn't "SALG", salgadinho).
        if word.count >= 4, token.hasPrefix(word) { return 0.8 }
        // "lte" -> "leite", "qj" -> "queijo". Two letters only when both are consonants, so
        // "pe" or "de" don't match half the list.
        if token.first == word.first, token.count <= word.count, isSubsequence(token, of: word) {
            if token.count >= 3 { return 0.6 }
            if token.count == 2, !token.contains(where: vowels.contains) { return 0.6 }
        }
        return 0
    }

    private static let vowels: Set<Character> = ["a", "e", "i", "o", "u"]

    private static func singular(_ word: String) -> String {
        word.count > 3 && word.hasSuffix("s") ? String(word.dropLast()) : word
    }

    private static func isSubsequence(_ short: String, of long: String) -> Bool {
        var remaining = short[...]
        for character in long where character == remaining.first {
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return true }
        }
        return remaining.isEmpty
    }
}
