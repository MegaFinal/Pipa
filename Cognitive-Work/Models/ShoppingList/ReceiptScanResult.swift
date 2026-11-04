//
//  ReceiptScanResult.swift
//  Cognitive-Work
//
//  Created by anshu Li on 04/11/26.
//

import Foundation

/// Something on a read line the person should look at before trusting it.
nonisolated enum ReceiptLineWarning: Equatable {
    /// Quantity × unit price doesn't match the total printed beside it (OCR misread a digit in
    /// one of them). The computed value is used.
    case totalMismatch(computed: Double, printed: Double)
    /// The quantity line was unreadable: the total printed on the product's rows is used.
    case quantityNotRead
    /// Neither a quantity nor a total was found (the product may be cut between two photos).
    case noAmount
    /// Read from the photo by the model, but the price isn't printed anywhere on the receipt
    /// (OCR reads digits exactly): probably misread.
    case notOnReceipt
}

/// One product read from a receipt; the review screen lets the person fix it.
nonisolated struct ReceiptScanLine: Identifiable, Equatable {
    let id = UUID()
    /// The printed item number (001 -> 1), when there is one.
    var itemNumber: Int?
    var name: String
    /// Units bought; 1 for products sold by weight.
    var quantity: Int
    /// Kilograms for products sold by weight, otherwise 0.
    var weightKg: Double
    /// What was paid for the whole line.
    var total: Double
    var warning: ReceiptLineWarning?
    /// The product's barcode, when read (see ``ReceiptNameMemory``).
    var barcode: String? = nil
    /// The name as printed, before it's spelled out or renamed; empty when it's ``name``.
    var receiptName = ""
}

extension ReceiptScanLine {
    /// From the parser's result, turning its checks into a warning (only the ones worth a look:
    /// a computed total without a printed one to compare is normal and not flagged).
    init(_ item: ReceiptParser.Item) {
        let warning: ReceiptLineWarning?
        let total: Double
        if item.computedTotal == 0, let printed = item.printedTotal {
            warning = .quantityNotRead
            total = printed
        } else if item.computedTotal == 0 {
            warning = .noAmount
            total = 0
        } else if let printed = item.printedTotal, !item.isConfirmed {
            warning = .totalMismatch(computed: item.computedTotal, printed: printed)
            total = item.computedTotal
        } else {
            warning = nil
            total = item.computedTotal
        }
        self.init(
            itemNumber: item.itemNumber,
            name: item.name,
            quantity: item.quantity,
            weightKg: item.weightKg,
            total: total,
            warning: warning,
            barcode: item.barcode
        )
    }
}

/// Everything read from the photos of one receipt.
nonisolated struct ReceiptScanResult {
    var lines: [ReceiptScanLine]
    /// The amounts on the receipt's total and payment rows (see ``ReceiptTotals``).
    var printedTotals: [Double]
    /// "QTD. TOTAL DE ITENS", when printed.
    var printedItemCount: Int?
    /// Whether the products came from the photo reading (``ReceiptPhotoReading``) instead of
    /// the parser.
    var readFromPhoto = false

    /// Item numbers between 1 and the last one (or the printed count) that weren't read:
    /// products the reader lost, for the person to add.
    var missingItemNumbers: [Int] {
        let numbers = Set(lines.compactMap(\.itemNumber))
        guard !numbers.isEmpty else { return [] }
        let last = max(numbers.max() ?? 0, printedItemCount ?? 0)
        return (1...last).filter { !numbers.contains($0) }
    }
}
