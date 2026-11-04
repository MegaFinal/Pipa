//
//  ReceiptScanService.swift
//  Cognitive-Work
//
//  Created by anshu Li on 04/11/26.
//

import UIKit

/// Reads a receipt from its photos: OCR that keeps the columns (``ReceiptTextReader``), the
/// products (``ReceiptParser``) and the printed totals (``ReceiptTotals``). No language model:
/// it runs on every device in a fraction of a second, and every number comes from the receipt.
nonisolated enum ReceiptScanService {

    /// Reads every page in order. A long receipt can be photographed in parts, one page each.
    static func read(_ pages: [UIImage]) async -> ReceiptScanResult {
        var lines: [ReceiptScanLine] = []
        var totals = Set<Double>()
        var printedItemCount: Int?

        for page in pages {
            let text = await ReceiptTextReader.text(from: page)
            lines += ReceiptParser.parse(text).map(ReceiptScanLine.init)
            totals.formUnion(ReceiptTotals.candidates(in: text))
            printedItemCount = ReceiptTotals.printedItemCount(in: text) ?? printedItemCount
        }

        return ReceiptScanResult(
            lines: removingOverlap(lines),
            printedTotals: totals.sorted(),
            printedItemCount: printedItemCount
        )
    }

    /// Two photos that overlap read the products in between twice: keeps the first of each item
    /// number. Lines without a number are kept as they are.
    private static func removingOverlap(_ lines: [ReceiptScanLine]) -> [ReceiptScanLine] {
        var seen = Set<Int>()
        return lines.filter { line in
            guard let number = line.itemNumber else { return true }
            return seen.insert(number).inserted
        }
    }
}
