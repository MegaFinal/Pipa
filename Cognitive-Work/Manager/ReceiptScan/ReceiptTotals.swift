//
//  ReceiptTotals.swift
//  Cognitive-Work
//
//  Created by anshu Li on 04/11/26.
//

import Foundation

/// The amounts printed at the bottom of a receipt, read from its OCR text without any model, so
/// they can't be invented. The products' sum is checked against them.
nonisolated enum ReceiptTotals {

    /// A Brazilian amount standing on its own: "18,16", "1.630,90".
    private static let amount = try! NSRegularExpression(
        pattern: #"(?<![\d,.])(\d{1,3}(?:\.\d{3})+,\d{2}|\d{1,5}[,.]\d{2})(?![\d,.%])"#
    )
    /// Rows that hold a total or a payment.
    private static let totalRow = #"VALOR|TOTAL|PAGAR|T\.?E\.?F|CART[AÃ]O|D[EÉ]BITO|CR[EÉ]DITO|DINHEIRO|\bPIX\b"#
    /// Rows that hold other amounts: taxes, discount, change, the card's balance, tip, service.
    private static let excludedRow = #"TRIBUT|IBPT|DESCONTO|TROCO|DISP|SERVI|GORJETA"#

    /// Every amount the products' sum could legitimately equal: the ones on total and payment
    /// rows (VALOR TOTAL, TOTAL A PAGAR, T.E.F., Cartão Débito…), or on the next row when OCR
    /// split it. Restaurants' subtotal and supermarkets' total both count, so the sum is checked
    /// against all of them.
    static func candidates(in text: String) -> [Double] {
        let lines = text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var found = Set<Double>()
        for (index, line) in lines.enumerated() {
            guard line.range(of: totalRow, options: [.regularExpression, .caseInsensitive]) != nil,
                  line.range(of: excludedRow, options: [.regularExpression, .caseInsensitive]) == nil
            else { continue }
            var values = amounts(in: line)
            if values.isEmpty, index + 1 < lines.count {
                values = amounts(in: lines[index + 1])
            }
            found.formUnion(values.filter { $0 > 0 })
        }
        return found.sorted()
    }

    /// "QTD. TOTAL DE ITENS 52" -> 52: how many products the receipt says it has. OCR reads QTD
    /// as QTB, QT0 or QIO, and the count must not be the start of an amount ("793,93").
    static func printedItemCount(in text: String) -> Int? {
        let pattern = #"Q[TI][DBO0]\.?\s*TOTAL\s*DE\s*ITENS[^\d]{0,120}?(\d{1,3})(?![\d,.])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return Int(text[range])
    }

    /// Every amount in a row: "1.630,90" -> 1630.9.
    private static func amounts(in line: String) -> [Double] {
        amount.matches(in: line, range: NSRange(line.startIndex..., in: line)).compactMap { match in
            guard let range = Range(match.range(at: 1), in: line) else { return nil }
            var value = String(line[range])
            if value.contains(",") {
                value = value.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            }
            return Double(value)
        }
    }
}
