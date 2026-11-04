//
//  ReceiptNameMemory.swift
//  Cognitive-Work
//
//  Created by anshu Li on 04/11/26.
//

import Foundation

/// What the house called the products it scanned before: once someone links "QJ.MUSS.AUR" to
/// "Queijo", or renames it, the next receipt shows "Queijo" and links it by itself. The same
/// shops sell the same products, so this gets better with every receipt.
///
/// A product is known by its barcode (the same in every receipt of a shop, and the most
/// reliable) and by its printed name (for receipts without one, or when OCR misread a digit).
/// The memory lives in the house's shopping list record (``ShopListModel/receiptNames``), so
/// every housemate's scans use it.
nonisolated enum ReceiptNameMemory {

    /// How many products are remembered; the oldest go first.
    static let limit = 1000

    /// Separates a key from its name in the stored strings.
    private static let separator: Character = "\u{1F}"

    /// The keys a receipt line is remembered by: its barcode, when read, and its printed name.
    static func keys(for line: ReceiptScanLine) -> [String] {
        var keys: [String] = []
        if let barcode = line.barcode { keys.append("ean:\(barcode)") }
        let printed = normalized(line.receiptName.isEmpty ? line.name : line.receiptName)
        if !printed.isEmpty { keys.append("name:\(printed)") }
        return keys
    }

    /// The name the house gave this line before, if any (the barcode wins over the name).
    static func name(for line: ReceiptScanLine, in memory: [String: String]) -> String? {
        keys(for: line).lazy.compactMap { memory[$0] }.first
    }

    /// "LTE COND.MOC.TP 395g" -> "lte cond moc tp 395g": case, accents and punctuation don't
    /// tell products apart.
    static func normalized(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }

    // MARK: - Stored form

    /// The stored strings ("key␟name", oldest first) as a dictionary.
    static func decode(_ stored: [String]?) -> [String: String] {
        var memory: [String: String] = [:]
        for entry in stored ?? [] {
            let parts = entry.split(separator: separator, maxSplits: 1).map(String.init)
            if parts.count == 2 { memory[parts[0]] = parts[1] }
        }
        return memory
    }

    /// `stored` with `new` added: a key learned again moves to the end (newest), and past
    /// ``limit`` the oldest are dropped.
    static func merge(_ stored: [String]?, with new: [String: String]) -> [String] {
        var entries = (stored ?? []).filter { entry in
            guard let key = entry.split(separator: separator, maxSplits: 1).first else { return false }
            return new[String(key)] == nil
        }
        entries += new.keys.sorted().compactMap { key in
            new[key].map { "\(key)\(separator)\($0)" }
        }
        return Array(entries.suffix(limit))
    }
}
