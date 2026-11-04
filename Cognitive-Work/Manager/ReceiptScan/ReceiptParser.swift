//
//  ReceiptParser.swift
//  Cognitive-Work
//
//  Created by anshu Li on 04/11/26.
//
//  Reads the products of a receipt from its OCR text (rows in reading order, columns kept; see
//  ``ReceiptTextReader``). Tuned on real receipts: supermarkets' NFC-e and restaurants' bills.
//
//  - Products are cut at their quantity line ("<qty>UN X <unit price>", "<weight>KG X <price per
//    kg>", "1 UN x R$ 18,00", or "2.000UN 17,90 35,80" without an X), not at the item numbers,
//    which OCR misreads near folds.
//  - The line total is COMPUTED (quantity or weight × unit price, rounded to cents). The printed
//    VL.ITEM value only checks it: the candidate closest to the computed total wins, and a
//    difference is flagged for the person to look at.
//  - Parsing stops at the footer (QTD. TOTAL, VALOR TOTAL…), so footer amounts never become a
//    product's price.
//  - Products whose quantity line OCR mangled are kept, with the total printed on their rows.
//

import Foundation

nonisolated enum ReceiptParser {

    struct Item {
        /// The printed item number (001 -> 1), when OCR read it.
        var itemNumber: Int?
        var name: String
        /// Units bought; 1 for products sold by weight.
        var quantity: Int
        /// Kilograms for products sold by weight, otherwise 0.
        var weightKg: Double
        var unitPrice: Double
        /// Quantity (or weight) × unit price, rounded to cents. 0 when the quantity line is missing.
        var computedTotal: Double
        /// The VL.ITEM value printed on the receipt closest to the computed total, when found.
        var printedTotal: Double?
        /// The product's barcode (EAN), when printed and read.
        var barcode: String? = nil

        /// Whether the printed total confirms the computed one (one cent of tolerance: some
        /// stores truncate instead of rounding).
        var isConfirmed: Bool {
            guard let printedTotal, computedTotal > 0 else { return false }
            return abs(printedTotal - computedTotal) <= 0.015
        }
    }

    // MARK: - Patterns

    /// The amount before the unit: "10", "0,364", "T" (OCR reads 1 as T, I or l). Lazy, so "10N"
    /// reads as 1 + 0N while "10UN" still reads as 10 + UN. Not glued to a word, and
    /// case-sensitive: a case-insensitive digit class would read the "1L" of "LIMAO 1L" as a
    /// quantity. It may be missing ("UN X 62,90": OCR glued the 1 to the name); it is then 1.
    private static let amountPattern = #"(?:(?<![A-Za-z])([0-9OIlT]{1,3}?(?:[,.][0-9O]{1,3})?)|(?<![A-Za-z0-9]))"#
    /// The unit, ignoring case, with OCR's misreads: UN as 0N, UV, UA, U4, Ul, 01 or a lone U;
    /// KG as K6, KQ or K0.
    private static let unitPattern = #"((?i:UNID|UND|UN|UV|UA|U4|UI|Ul|U1|0N|ON|0V|OV|KG|K6|KQ|K0|KO|PCT|PC|CX|LT|U)|01|0l|Ol|O1)\b\.?\s*"#
    /// The X, also read as ×, a Cyrillic Х or к, or *.
    private static let timesPattern = #"[Xx×Х*к]\s*"#

    /// "10UN X 0,17", "0,364KG X 49,90", "TUN X 10,89", and restaurants' "1 UN x R$ 18,00".
    private static let quantityLine = regex(
        amountPattern + #"\s*"# + unitPattern + timesPattern + #"(?:R\$\s*)?([0-9O]{1,4}[,.][0-9O]{2,3})"#
    )
    /// "1 UN x R$" with no price after it: OCR pushed the prices onto the name row
    /// ("SUCO LIMAO 300ML 12,90 = R$ 12,90"). The unit price is then the name row's first amount.
    private static let quantityWithoutPrice = regex(
        amountPattern + #"\s*"# + unitPattern + timesPattern + #"(?:R\$?|RE)?\s*$"#
    )
    /// No X at all: "2.000UN 17,90 35,80" (quantity with three decimals, unit price, total), as
    /// some restaurants' systems print it.
    private static let quantityColumns = regex(
        #"(?<![\d,.])(\d{1,3}[.,]\d{3})\s*((?i:UN|UND|KG|PC|CX|LT))\b\.?\s+(?:R\$\s*)?([0-9O]{1,4}[,.][0-9O]{2})(?![\d])"#
    )

    /// How a quantity line was found: with its unit price, without it (the name row has it), or
    /// in columns without an X.
    private enum QuantityKind { case full, priceless, columns }

    /// The first quantity line in `line`, trying the three shapes in order.
    private static func findQuantity(in line: String) -> (match: NSTextCheckingResult, kind: QuantityKind)? {
        let range = fullRange(line)
        if let match = quantityLine.firstMatch(in: line, range: range) { return (match, .full) }
        if let match = quantityWithoutPrice.firstMatch(in: line, range: range) { return (match, .priceless) }
        if let match = quantityColumns.firstMatch(in: line, range: range) { return (match, .columns) }
        return nil
    }

    /// A Brazilian amount standing on its own: "1,70", "101,11", "1.250,50".
    private static let money = regex(#"(?<![\d,.])(\d{1,3}(?:\.\d{3})+,\d{2}|\d{1,5}[,.]\d{2})(?![\d,.%])"#)
    /// The item number that opens a product line: "001", "O35", "02C" (OCR misreads 0 as O or
    /// C), followed by a space, a dot or a dash ("021.0789…", "024-0789…").
    private static let itemNumber = regex(#"^\s*([0-9OIl][0-9OIl][0-9OIlC])(?:[\s.\-·]+)\S"#)
    /// The item number and its separator, to strip from a product line.
    private static let leadingItemNumber = regex(#"^\s*[0-9OIl][0-9OIl][0-9OIlC][\s.\-·]*"#)
    /// A row starting with a barcode and then a name: a product whose item number OCR lost.
    private static let barcodeRow = regex(#"^\s*[0-9OIl]{8,}\s+\S*[A-Za-z]"#)
    /// A product line that OCR glued to the end of another row: item number + barcode.
    private static let gluedProduct = regex(#"\b([0-9OIl]{3})\s+[0-9OIl]{8,}"#)
    /// Where the product table ends.
    private static let footer = regex(
        // "V?ALOR" and "T?OTAL": photos often crop the receipt's first letter.
        #"Q[TI][DBO0]\.?\s*TOTAL|V?ALOR\s+TOTAL|T?OTAL\s+A\s+PAGAR|VALOR\s+A\s+PAGAR|SUB\s*TOTAL|FORMA\s+DE\s+PAGAMENTO|^\s*TOTAL\b"#,
        caseInsensitive: true
    )
    /// Tax columns: "T18,00%", "T4,50%", "F1", "I1", "N1".
    private static let tax = regex(#"\bT\s*\d{1,2}[,.]\d{2}\s*%?|\b[FIN][1-9]\b"#)

    private static func regex(_ pattern: String, caseInsensitive: Bool = false) -> NSRegularExpression {
        // The patterns are literals in this file, so a failure here is a programming error.
        try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    }

    // MARK: - Parsing

    /// Reads every product of one page of OCR text (rows in reading order).
    static func parse(_ text: String) -> [Item] {
        // A barcode glued to the name with a dash: "07891021002127-FILTRO".
        let text = text.replacingOccurrences(of: #"(\d{8,})[-–](?=[A-Za-z])"#, with: "$1 ", options: .regularExpression)
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var items: [Item] = []
        /// Rows since the last quantity line: the next product's name, maybe stray amounts.
        var pending: [String] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            index += 1
            // The column header can say "Subtotal" too: a row only ends the table once a product
            // was read or when it carries an amount.
            if matches(footer, line), !items.isEmpty || !amounts(in: line).isEmpty { break }

            guard let found = findQuantity(in: line),
                  let matchRange = Range(found.match.range, in: line)
            else {
                pending.append(line)
                continue
            }
            let quantity = found.match
            let kind = found.kind

            let before = String(line[..<matchRange.lowerBound])
            var after = String(line[matchRange.upperBound...])

            // A next product glued after this quantity line belongs to the next product.
            var carry: [String] = []
            if let glued = gluedProduct.firstMatch(in: after, range: fullRange(after)),
               let gluedRange = Range(glued.range, in: after) {
                carry.append(String(after[gluedRange.lowerBound...]))
                after = String(after[..<gluedRange.lowerBound])
            }

            // Whose quantity line is this? A product row still waiting (with its item number)
            // comes first; then a name glued before the quantity on this same row; then any
            // waiting row with words.
            let waitingProduct = pending.last(where: isProductRow)
            let owner: String?
            /// Waiting rows that never got a quantity line; listed with their printed totals.
            var earlier: [String] = []
            let nextIsBareQuantity = index < lines.count && isBareQuantity(lines[index])
            if let waitingProduct, isProductRow(before),
               !amounts(in: removingLeadingCode(waitingProduct)).isEmpty, !nextIsBareQuantity {
                // "046 … MISTURA … 1UN X 7,99" after "045 … 10,89": the waiting row already
                // carries its amount, so it stands alone and this quantity is 046's own. Unless
                // the next row is a bare quantity line: then that one is the glued product's, and
                // this one the waiting row's (its amount was the previous product's, shifted).
                owner = before
                earlier = pending
            } else if let waitingProduct {
                // A bare waiting name row: this quantity is its own, even when OCR glued it to
                // the next product's row ("002 CACHACA" + "003 AMACIANTE … UN X 62,90").
                owner = waitingProduct
                if let ownerIndex = pending.lastIndex(of: waitingProduct) {
                    earlier = Array(pending[..<ownerIndex])
                }
                if isProductRow(before) { carry.insert(before, at: 0) }
            } else if letterCount(before) >= 3 {
                owner = before
            } else {
                owner = pending.last(where: { letterCount($0) >= 3 })
            }

            // The unit price: after the X, or on the name row when OCR moved it there.
            let ownerAmounts = owner.map { amounts(in: removingLeadingCode($0)) } ?? []
            let unitPrice: Double
            switch kind {
            case .full, .columns:
                unitPrice = number(normalizeDigits(line, quantity.range(at: 3))) ?? 0
            case .priceless:
                guard let first = ownerAmounts.first else {
                    // A bare "1 UN x R$" with no price anywhere: not usable.
                    pending.append(line)
                    continue
                }
                unitPrice = first
            }
            items += incompleteProducts(in: earlier)

            let hasAmount = quantity.range(at: 1).location != NSNotFound
            let unit = substring(line, quantity.range(at: 2)).uppercased()
            let isWeight = unit.hasPrefix("K")
            let amount = hasAmount ? (number(normalizeDigits(line, quantity.range(at: 1))) ?? 1) : 1
            var counted = isWeight ? amount : amount.rounded()
            var computed = (counted * unitPrice * 100).rounded() / 100

            // Printed VL.ITEM candidates: on the owner's row, after the quantity, on rows waiting
            // in between, and on the next row when it holds only an amount.
            var candidates = amounts(in: after) + ownerAmounts
            // Rows with an item number belong to other products, even when OCR lost their words.
            for row in pending where row != owner && letterCount(row) < 3 && !isProductRow(row) {
                candidates += amounts(in: row)
            }
            if index < lines.count, letterCount(lines[index]) < 3, !isProductRow(lines[index]),
               !amounts(in: lines[index]).isEmpty, findQuantity(in: lines[index]) == nil {
                candidates += amounts(in: lines[index])
                index += 1
            }
            var printed = candidates.min { abs($0 - computed) < abs($1 - computed) }

            if isWeight, !hasAmount, let largest = candidates.max(), unitPrice > 0 {
                // Weight missing ("KG X 31,99"): the printed total gives it back.
                printed = largest
                counted = (largest / unitPrice * 1000).rounded() / 1000
                computed = largest
            } else if let printedValue = printed, abs(printedValue - computed) > 0.015 {
                // Decimal point lost by OCR ("374KG" for "0,374KG"): a power of ten makes it match.
                for factor in [10.0, 100.0, 1000.0] where isWeight || counted >= 10 {
                    let scaled = (counted / factor * unitPrice * 100).rounded() / 100
                    if abs(scaled - printedValue) <= 0.015 {
                        counted = isWeight ? counted / factor : max(1, (counted / factor).rounded())
                        computed = scaled
                        break
                    }
                }
            }

            items.append(Item(
                itemNumber: owner.flatMap(itemNumberValue),
                name: owner.map(cleanName) ?? "(sem nome)",
                quantity: isWeight ? 1 : max(1, Int(counted)),
                weightKg: isWeight ? counted : 0,
                unitPrice: unitPrice,
                computedTotal: computed,
                printedTotal: printed,
                barcode: owner.flatMap(barcodeValue)
            ))
            pending = carry
        }

        // Products whose quantity line never came (unreadable, or cut between two photos).
        items += incompleteProducts(in: pending)
        fixItemNumbers(&items)
        return items
    }

    /// Products in `rows` that have no quantity line: each one with the last amount printed on
    /// its own rows (the VL.ITEM column), and `computedTotal` 0 so the screen flags them.
    private static func incompleteProducts(in rows: [String]) -> [Item] {
        var result: [Item] = []
        var index = 0
        while index < rows.count {
            guard isProductRow(rows[index]) else { index += 1; continue }
            let productRow = rows[index]
            var amountsFound = amounts(in: removingLeadingCode(productRow))
            index += 1
            // Its following rows, up to the next product.
            while index < rows.count, !isProductRow(rows[index]) {
                amountsFound += amounts(in: rows[index])
                index += 1
            }
            result.append(Item(
                itemNumber: itemNumberValue(productRow),
                name: cleanName(productRow),
                quantity: 1,
                weightKg: 0,
                unitPrice: 0,
                computedTotal: 0,
                printedTotal: amountsFound.last,
                barcode: barcodeValue(productRow)
            ))
        }
        return result
    }

    /// Item numbers run 001, 002, 003… in printed order. Fills a number OCR couldn't read when
    /// its neighbors leave exactly that gap, and replaces one that doesn't fit the order
    /// ("048" between 042 and 046 is really 043).
    private static func fixItemNumbers(_ items: inout [Item]) {
        for index in items.indices {
            let previous = items[..<index].last(where: { $0.itemNumber != nil })?.itemNumber
            let next = items[(index + 1)...].first(where: { $0.itemNumber != nil })?.itemNumber
            guard let previous else { continue }
            let expected = previous + 1
            if let next, expected >= next { continue }

            if let current = items[index].itemNumber {
                // Out of order: can't come after the previous one or after the next one.
                if current <= previous || (next.map { current >= $0 } ?? false) {
                    items[index].itemNumber = expected
                }
            } else {
                items[index].itemNumber = expected
            }
        }
    }

    // MARK: - Helpers

    private static func fullRange(_ text: String) -> NSRange {
        NSRange(text.startIndex..<text.endIndex, in: text)
    }

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: fullRange(text)) != nil
    }

    private static func substring(_ text: String, _ range: NSRange) -> String {
        Range(range, in: text).map { String(text[$0]) } ?? ""
    }

    /// The captured digits with OCR's usual letter swaps undone (O/C -> 0, I/l/T -> 1).
    private static func normalizeDigits(_ text: String, _ range: NSRange) -> String {
        substring(text, range)
            .replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "C", with: "0")
            .replacingOccurrences(of: "I", with: "1")
            .replacingOccurrences(of: "l", with: "1")
            .replacingOccurrences(of: "T", with: "1")
    }

    /// "0,364" -> 0.364, "1.250,50" -> 1250.5.
    private static func number(_ text: String) -> Double? {
        var value = text
        if value.contains(",") {
            value = value.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        }
        return Double(value)
    }

    /// Every standalone amount in a row, tax columns removed first.
    private static func amounts(in row: String) -> [Double] {
        let clean = tax.stringByReplacingMatches(in: row, range: fullRange(row), withTemplate: " ")
        return money.matches(in: clean, range: fullRange(clean)).compactMap { match in
            number(substring(clean, match.range(at: 1)))
        }
    }

    /// A product's row: it starts with an item number, or with a barcode followed by a name
    /// when OCR lost the number ("00000000115056 AZEITONA VDE.RECH.KG").
    private static func isProductRow(_ row: String) -> Bool {
        hasItemNumber(row) || matches(barcodeRow, row)
    }

    /// A quantity line on its own row, not glued to a product.
    private static func isBareQuantity(_ row: String) -> Bool {
        guard let found = findQuantity(in: row), let range = Range(found.match.range, in: row) else { return false }
        return !isProductRow(row) && letterCount(String(row[..<range.lowerBound])) < 3
    }

    private static func hasItemNumber(_ row: String) -> Bool {
        matches(itemNumber, row)
    }

    private static func itemNumberValue(_ row: String) -> Int? {
        guard let match = itemNumber.firstMatch(in: row, range: fullRange(row)) else { return nil }
        return Int(normalizeDigits(row, match.range(at: 1)))
    }

    private static func letterCount(_ row: String) -> Int {
        row.filter(\.isLetter).count
    }

    /// The row without its item number and barcode.
    private static func removingLeadingCode(_ row: String) -> String {
        let withoutNumber = hasItemNumber(row)
            ? leadingItemNumber.stringByReplacingMatches(in: row, range: fullRange(row), withTemplate: "")
            : row
        var parts = withoutNumber.split(whereSeparator: \.isWhitespace).map(String.init)
        // The barcode: a long token made mostly of digits.
        if let first = parts.first, first.count >= 7, first.filter(\.isNumber).count >= first.count / 2 {
            parts.removeFirst()
        }
        return parts.joined(separator: " ")
    }

    /// The barcode at the start of a product row (after its item number), with OCR's letter
    /// misreads of digits fixed ("0789:64027117" stays out: it isn't all digits). `nil` when
    /// there is none or it's too short to be one.
    private static func barcodeValue(_ row: String) -> String? {
        let withoutNumber = hasItemNumber(row)
            ? leadingItemNumber.stringByReplacingMatches(in: row, range: fullRange(row), withTemplate: "")
            : row
        guard let first = withoutNumber.split(whereSeparator: \.isWhitespace).first else { return nil }
        let digits = String(first)
            .replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "I", with: "1")
            .replacingOccurrences(of: "l", with: "1")
        guard digits.count >= 8, digits.allSatisfy(\.isNumber) else { return nil }
        return digits
    }

    /// The product name: no item number, barcode, amounts or tax columns.
    private static func cleanName(_ row: String) -> String {
        var parts = removingLeadingCode(row).split(whereSeparator: \.isWhitespace).map(String.init)
        // Names only: also drop leading tokens without letters ("2", ")3", a second barcode).
        while let first = parts.first,
              !first.contains(where: \.isLetter) || (first.count >= 7 && first.filter(\.isNumber).count >= first.count / 2) {
            parts.removeFirst()
        }
        var name = parts.joined(separator: " ")
        // "= R$" left over from restaurant rows.
        name = name.replacingOccurrences(of: #"=\s*R?\$?"#, with: " ", options: .regularExpression)
        name = tax.stringByReplacingMatches(in: name, range: fullRange(name), withTemplate: " ")
        name = money.stringByReplacingMatches(in: name, range: fullRange(name), withTemplate: " ")
        return name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
