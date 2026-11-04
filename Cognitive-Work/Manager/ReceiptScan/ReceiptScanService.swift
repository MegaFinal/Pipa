//
//  ReceiptScanService.swift
//  Cognitive-Work
//
//  Created by anshu Li on 04/11/26.
//

import Foundation
import UIKit

/// Reads the photos of one receipt, the way the test bench showed works best. The amounts
/// printed on the receipt's total and payment rows are the referee, so there's no need to know
/// whether it's a supermarket, a pharmacy or a restaurant:
///
/// 1. OCR that keeps the columns, plus ``ReceiptParser`` (any iPhone). Kept when its sum
///    matches a printed total.
/// 2. Otherwise, on a short receipt, photo + OCR with the on-device model (iOS 27 with Apple
///    Intelligence, ``ReceiptPhotoReading``). Kept when its sum matches.
/// 3. Neither matches: the result whose sum is closest to the total without going over it (a
///    sum above the total comes from wrong values; one below is usually missing products,
///    which the person adds).
nonisolated enum ReceiptScanService {

    /// Reads every page in order. A long receipt can be photographed in parts, one page each.
    static func read(_ pages: [UIImage]) async -> ReceiptScanResult {
        var parserLines: [ReceiptScanLine] = []
        var texts: [String] = []
        var totals = Set<Double>()
        var printedItemCount: Int?

        for page in pages {
            let text = await ReceiptTextReader.text(from: page)
            texts.append(text)
            parserLines += ReceiptParser.parse(text).map(ReceiptScanLine.init)
            totals.formUnion(ReceiptTotals.candidates(in: text))
            printedItemCount = ReceiptTotals.printedItemCount(in: text) ?? printedItemCount
        }
        parserLines = removingOverlap(parserLines)

        let printedTotals = totals.sorted()
        func result(_ lines: [ReceiptScanLine], readFromPhoto: Bool) -> ReceiptScanResult {
            ReceiptScanResult(
                lines: lines,
                printedTotals: printedTotals,
                printedItemCount: printedItemCount,
                readFromPhoto: readFromPhoto
            )
        }

        if isTrusted(parserLines, totals: printedTotals) || !canReadPhotos(texts) {
            return result(parserLines, readFromPhoto: false)
        }

        // Step 2: photo + OCR, page by page. A page the model couldn't read gives nothing.
        var photoLines: [ReceiptScanLine] = []
        for page in pages {
            let text = await ReceiptTextReader.text(from: page, style: .plain)
            photoLines += await ReceiptPhotoReading.read(page, ocrText: text) ?? []
        }

        let usesPhoto = choosesPhoto(parser: parserLines, photo: photoLines, totals: printedTotals)
        return usesPhoto ? result(photoLines, readFromPhoto: true) : result(parserLines, readFromPhoto: false)
    }

    // MARK: - Choosing

    /// Whether a result can be kept without trying another: its sum matches a printed total. A
    /// receipt with no total read is trusted when most products were confirmed by their printed
    /// price.
    static func isTrusted(_ lines: [ReceiptScanLine], totals: [Double]) -> Bool {
        guard !lines.isEmpty else { return false }
        let sum = lines.map(\.total).reduce(0, +)
        if !totals.isEmpty {
            return totals.contains { abs(sum - $0) <= max($0 * 0.01, 0.05) }
        }
        guard lines.count >= 3 else { return false }
        let confirmed = lines.filter { $0.warning == nil }.count
        return Double(confirmed) / Double(lines.count) >= 0.7
    }

    /// Whether the photo reading is worth trying: the iPhone can run it, every page is short
    /// enough for the model, and the receipt has at least two amounts (a card slip has one).
    private static func canReadPhotos(_ texts: [String]) -> Bool {
        guard ReceiptPhotoReading.isAvailable else { return false }
        let longestPage = texts.map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ").count }.max() ?? 0
        let amounts = texts.map(ReceiptTotals.amountCount(in:)).reduce(0, +)
        return longestPage <= ReceiptPhotoReading.maxOCRCharacters && amounts >= 2
    }

    /// Whether the photo result wins over the parser's: it matches a printed total, or neither
    /// matches and it's the closest to one without going over the highest (unless both go over).
    static func choosesPhoto(parser: [ReceiptScanLine], photo: [ReceiptScanLine], totals: [Double]) -> Bool {
        guard !photo.isEmpty else { return false }
        if isTrusted(photo, totals: totals) { return true }
        guard !parser.isEmpty else { return true }

        let parserSum = parser.map(\.total).reduce(0, +)
        let photoSum = photo.map(\.total).reduce(0, +)
        if let highest = totals.max() {
            let parserOver = parserSum > highest * 1.01
            let photoOver = photoSum > highest * 1.01
            if parserOver != photoOver { return parserOver }
        }
        // Without totals, more products is better.
        guard !totals.isEmpty else { return photo.count > parser.count }
        func distance(_ sum: Double) -> Double { totals.map { abs(sum - $0) }.min() ?? .infinity }
        return distance(photoSum) < distance(parserSum)
    }

    // MARK: - Pages

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
