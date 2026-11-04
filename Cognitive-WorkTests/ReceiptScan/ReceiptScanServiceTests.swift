//
//  ReceiptScanServiceTests.swift
//  Cognitive-WorkTests
//
//  Created by anshu Li on 04/11/26.
//

import Testing
@testable import Cognitive_Work

/// Which reading the receipt scan keeps: the parser's, or the photo's (iOS 27), with the
/// printed totals as the referee.
struct ReceiptScanServiceTests {

    private func lines(_ totals: [Double]) -> [ReceiptScanLine] {
        totals.map { ReceiptScanLine(itemNumber: nil, name: "Item", quantity: 1, weightKg: 0, total: $0, warning: nil) }
    }

    @Test func parserMatchingTheTotalIsKept() {
        #expect(ReceiptScanService.isTrusted(lines([10, 5.5]), totals: [15.5]))
        // Within 1% or 5 centavos.
        #expect(ReceiptScanService.isTrusted(lines([10, 5.47]), totals: [15.5]))
        #expect(!ReceiptScanService.isTrusted(lines([10, 4]), totals: [15.5]))
    }

    @Test func photoMatchingTheTotalWins() {
        #expect(ReceiptScanService.choosesPhoto(parser: lines([10, 4]), photo: lines([10, 5.5]), totals: [15.5]))
    }

    @Test func aSumAboveTheTotalLoses() {
        // The photo is closer (+1,00) but above the total; the parser is below (−2,00): products
        // missing, which the person adds, beat wrong values.
        #expect(!ReceiptScanService.choosesPhoto(parser: lines([10, 3.5]), photo: lines([10, 6.5]), totals: [15.5]))
    }

    @Test func closestWinsWhenBothAreBelow() {
        #expect(ReceiptScanService.choosesPhoto(parser: lines([10]), photo: lines([10, 4]), totals: [15.5]))
        #expect(!ReceiptScanService.choosesPhoto(parser: lines([10, 4]), photo: lines([10]), totals: [15.5]))
    }

    @Test func emptyPhotoNeverWins() {
        #expect(!ReceiptScanService.choosesPhoto(parser: lines([10]), photo: [], totals: [15.5]))
    }

    @Test func pricesAreFoundOnlyAsWholeNumbers() {
        #expect(ReceiptTotals.isPrinted(18.16, in: "QUEIJO 0,364KG X 49,90 18,16"))
        #expect(ReceiptTotals.isPrinted(1630.90, in: "VALOR TOTAL R$ 1.630,90"))
        #expect(!ReceiptTotals.isPrinted(8.16, in: "QUEIJO 18,16"))
        #expect(ReceiptTotals.amountCount(in: "1 UN X 10,49 10,49\nTOTAL 35,00") == 3)
    }
}
