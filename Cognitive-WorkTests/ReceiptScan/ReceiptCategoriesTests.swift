//
//  ReceiptCategoriesTests.swift
//  Cognitive-WorkTests
//
//  Created by anshu Li on 05/11/26.
//

import Testing
@testable import Cognitive_Work

/// The aisle guessed for products read from a receipt, with names from real receipts spelled
/// out as the review screen does.
@MainActor
struct ReceiptCategoriesTests {

    private func guess(_ printed: String) -> ShopItemCategory? {
        ReceiptCategories.guess(ReceiptAbbreviations.expand(printed))
    }

    @Test func commonProducts() {
        #expect(guess("LTE COND.MOC.TP 395g") == .food)
        #expect(guess("QJ.MUSS.AUR.FAT.150g") == .food)
        #expect(guess("BANANA NANICA FAVA NG") == .produce)
        #expect(guess("DETERG LIQ YPE 500ML") == .cleaning)
        #expect(guess("REFRIG COCA COLA 2L") == .drinks)
        #expect(guess("SABONETE DOVE 90G") == .hygiene)
        #expect(guess("RACAO PEDIGREE 1KG") == .pets)
        #expect(guess("PILHA DURACELL AA") == .home)
    }

    @Test func theFirstKnownWordDecides() {
        // A sauce, not a tomato; a brand first is skipped.
        #expect(guess("MOLHO TOMATE POMAROLA 340G") == .food)
        #expect(guess("OMO SABAO PO 1KG") == .cleaning)
    }

    @Test func twoWordNamesComeBeforeTheirFirstWord() {
        #expect(guess("AGUA SANITARIA QBOA 1L") == .cleaning)
        #expect(guess("PAPEL HIG NEVE 12UN") == .hygiene)
        #expect(guess("CREME DE LEITE NESTLE") == .food)
        #expect(guess("AGUA MIN CRYSTAL 500ML") == .drinks)
    }

    @Test func pluralsAndUnknownNames() {
        #expect(ReceiptCategories.guess("Tomates") == .produce)
        #expect(ReceiptCategories.guess("Xpt 4421") == nil)
    }

    @Test func theAisleIsRememberedUnderItsOwnKeys() {
        let line = ReceiptScanLine(itemNumber: 1, name: "Bala", quantity: 1, weightKg: 0, total: 2,
                                   warning: nil, barcode: "7891234567890", receiptName: "BALA FINI MINHOC")
        let memory = ["cat-ean:7891234567890": "food", "name:bala fini minhoc": "Bala"]
        #expect(ReceiptNameMemory.category(for: line, in: memory) == "food")
        // The aisle never shows up as a name.
        #expect(ReceiptNameMemory.name(for: line, in: memory) == "Bala")
    }
}
