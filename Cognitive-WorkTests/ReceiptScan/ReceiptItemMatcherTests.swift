//
//  ReceiptItemMatcherTests.swift
//  Cognitive-WorkTests
//
//  Created by anshu Li on 04/11/26.
//

import Testing
@testable import Cognitive_Work

/// Pairing receipt lines with shopping-list items by name, with names from real receipts.
@MainActor
struct ReceiptItemMatcherTests {

    private let receipt = [
        "LTE COND.MOC.TP 395g",
        "LEITE ITALAC SEMIDESN.C TPA.1L",
        "PAO FRANCES KG",
        "QJ.MUSS.AUR.FAT.150g",
        "BANANA NANICA FAVA NG",
        "SALG MILHO CHEETOS C",
        "SABAO PO OMO 1KG",
        "PAPEL TOALHA SORELLA",
        "MOLHO TOMATE POMAROLA 340G",
    ]

    /// The receipt line paired with `name`, or `nil`.
    private func line(for name: String, in list: [String]) -> String? {
        let pairs = ReceiptItemMatcher.match(receiptNames: receipt, listNames: list)
        guard let itemIndex = list.firstIndex(of: name), let lineIndex = pairs[itemIndex] else { return nil }
        return receipt[lineIndex]
    }

    @Test func abbreviationsAndAccents() {
        let list = ["Leite condensado", "Pão francês", "Queijo", "Bananas", "Sabão em pó"]
        #expect(line(for: "Leite condensado", in: list) == "LTE COND.MOC.TP 395g")
        #expect(line(for: "Pão francês", in: list) == "PAO FRANCES KG")
        #expect(line(for: "Queijo", in: list) == "QJ.MUSS.AUR.FAT.150g")
        #expect(line(for: "Bananas", in: list) == "BANANA NANICA FAVA NG")
        #expect(line(for: "Sabão em pó", in: list) == "SABAO PO OMO 1KG")
    }

    @Test func closestProductWinsAndEachLineIsUsedOnce() {
        let list = ["Leite", "Leite condensado"]
        #expect(line(for: "Leite", in: list) == "LEITE ITALAC SEMIDESN.C TPA.1L")
        #expect(line(for: "Leite condensado", in: list) == "LTE COND.MOC.TP 395g")
    }

    @Test func sharingOneWordIsNotEnough() {
        let list = ["Papel higiênico", "Molho de tomate", "Sal", "Café"]
        #expect(line(for: "Papel higiênico", in: list) == nil)
        #expect(line(for: "Sal", in: list) == nil)
        #expect(line(for: "Café", in: list) == nil)
        #expect(line(for: "Molho de tomate", in: list) == "MOLHO TOMATE POMAROLA 340G")
    }

    @Test func weighedProductsGoToTheListInGrams() {
        let cheese = ReceiptScanLine(itemNumber: 25, name: "Queijo", quantity: 1, weightKg: 0.364, total: 18.16, warning: nil)
        let cheeseAmount = ReceiptScanViewModel.listAmount(for: cheese)
        #expect(cheeseAmount.quantity == 364 && cheeseAmount.unit == .gram)

        // Past the quantity field's 1000: kilograms.
        let melon = ReceiptScanLine(itemNumber: 39, name: "Melancia", quantity: 1, weightKg: 1.845, total: 10.13, warning: nil)
        let melonAmount = ReceiptScanViewModel.listAmount(for: melon)
        #expect(melonAmount.quantity == 2 && melonAmount.unit == .kilogram)

        let milk = ReceiptScanLine(itemNumber: 11, name: "Leite", quantity: 2, weightKg: 0, total: 13.18, warning: nil)
        let milkAmount = ReceiptScanViewModel.listAmount(for: milk)
        #expect(milkAmount.quantity == 2 && milkAmount.unit == .unit)
    }

    @Test func receiptNamesLoseTheirCapitals() {
        #expect(ReceiptScanViewModel.displayName("LTE COND.MOC.TP 395g") == "Lte cond.moc.tp 395g")
        #expect(ReceiptScanViewModel.displayName("Suco Natural One") == "Suco Natural One")
    }
}
