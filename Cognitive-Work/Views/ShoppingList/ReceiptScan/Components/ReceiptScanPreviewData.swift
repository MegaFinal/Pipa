//
//  ReceiptScanPreviewData.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 06/11/26.
//

import Foundation

/// Sample receipts for the previews of the receipt scan screens, read against the shopping list
/// of ``ShopListPreviewData``. Covers every state a card can show: a product that checks off a
/// list item, a weighed one, one with a misread price, one without a price and one bought
/// outside the list.
@MainActor
enum ReceiptScanPreviewData {

    /// The list the receipts are reviewed against.
    static var shopList: ShopListViewModel { ShopListPreviewData.populatedViewModel }

    /// Products as the reader returns them. Item 003 is missing on purpose ("not read").
    static var lines: [ReceiptScanLine] {
        [
            ReceiptScanLine(itemNumber: 1, name: "DETERG LIQ YPE 500ML", quantity: 2, weightKg: 0, total: 5.98, warning: nil,
                            receiptName: "DETERG LIQ YPE 500ML"),
            ReceiptScanLine(itemNumber: 2, name: "BANANA PRATA KG", quantity: 1, weightKg: 0.364, total: 3.62, warning: nil,
                            receiptName: "BANANA PRATA KG"),
            ReceiptScanLine(itemNumber: 4, name: "REFRIG GUARANA 2L", quantity: 1, weightKg: 0, total: 8.49,
                            warning: .totalMismatch(computed: 8.49, printed: 8.94), receiptName: "REFRIG GUARANA 2L"),
            ReceiptScanLine(itemNumber: 5, name: "CHICLETE TRIDENT", quantity: 3, weightKg: 0, total: 7.50, warning: nil,
                            receiptName: "CHICLETE TRIDENT"),
            ReceiptScanLine(itemNumber: 6, name: "PAO DE QUEIJO", quantity: 1, weightKg: 0, total: 0, warning: .noAmount,
                            receiptName: "PAO DE QUEIJO")
        ]
    }

    /// What ``lines`` add up to.
    static var linesSum: Double { lines.map(\.total).reduce(0, +) }

    /// A review read from ``lines``, with the receipt's total R$ 4,90 above the products', so
    /// the summary says something is missing.
    static func review(of shopList: ShopListViewModel) -> ReceiptScanViewModel {
        review(of: shopList, lines: lines, printedTotal: linesSum + 4.90)
    }

    /// A review read from `lines`, with `printedTotal` as the receipt's total (`nil`: none was
    /// read).
    ///
    /// - Note: No default values here: they're evaluated outside the main actor and can't read
    ///   ``lines``.
    static func review(
        of shopList: ShopListViewModel,
        lines: [ReceiptScanLine],
        printedTotal: Double?
    ) -> ReceiptScanViewModel {
        let model = ReceiptScanViewModel()
        model.load(
            ReceiptScanResult(
                lines: lines,
                printedTotals: printedTotal.map { [$0] } ?? [],
                printedItemCount: 6,
                repeatedPages: 1
            ),
            linking: shopList.receiptLinkableItems,
            houseUsers: shopList.houseUsers
        )
        return model
    }

    /// A review where every product was read and the sum matches the receipt.
    static func cleanReview(of shopList: ShopListViewModel) -> ReceiptScanViewModel {
        let clean = lines.enumerated().map { index, line in
            var line = line
            line.itemNumber = index + 1
            line.warning = nil
            if line.total == 0 { line.total = 12.90 }
            return line
        }
        let model = ReceiptScanViewModel()
        model.load(
            ReceiptScanResult(lines: clean, printedTotals: [clean.map(\.total).reduce(0, +)], printedItemCount: clean.count),
            linking: shopList.receiptLinkableItems,
            houseUsers: shopList.houseUsers
        )
        return model
    }

    /// A review where nothing was read.
    static func emptyReview(of shopList: ShopListViewModel) -> ReceiptScanViewModel {
        review(of: shopList, lines: [], printedTotal: nil)
    }
}
