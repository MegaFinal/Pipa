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

    /// The receipt line paired with `name`, or `nil`. Names are spelled out first, as the
    /// review screen does.
    private func line(for name: String, in list: [String]) -> String? {
        let pairs = ReceiptItemMatcher.match(receiptNames: receipt.map(ReceiptAbbreviations.expand), listNames: list)
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

    @Test func lettersInOrderAreNotAnAbbreviation() {
        // "DT" (an item number misread) isn't "desodorante"; "pão" isn't "pimentão".
        let pairs = ReceiptItemMatcher.match(receiptNames: ["Dt queijo", "pão"], listNames: ["desodorante", "pimentão", "pão"])
        #expect(pairs[0] == nil)
        #expect(pairs[1] == nil)
        #expect(pairs[2] == 1)
    }

    @Test func aWordInTheMiddleIsNotTheProduct() {
        // Seen on a Krill receipt: yogurt "BAT" (batido), beer "BR" (Brahma), margarine "C/SAL".
        let names = ["IOG.BAT.NAT.IN.160g", "CE.BR.DU.MA.LT.269ml", "MA.QUALY C/SAL 250g", "BANANA PRATA kg"]
            .map(ReceiptAbbreviations.expand)
        let list = ["batata", "bombril", "sal", "iogurte", "banana"]
        let pairs = ReceiptItemMatcher.match(receiptNames: names, listNames: list)
        #expect(pairs[0] == nil)
        #expect(pairs[1] == nil)
        #expect(pairs[2] == nil)
        #expect(pairs[3] == 0)
        #expect(pairs[4] == 3)
    }

    @Test func changingTheQuantityScalesThePrice() {
        let model = ReceiptScanViewModel()
        let pasta = ReceiptScanLine(itemNumber: 11, name: "Macarrão", quantity: 1, weightKg: 0, total: 5.99, warning: nil)
        model.lines = [pasta]
        model.setQuantity(2, for: pasta)
        #expect(model.lines[0].quantity == 2)
        #expect(abs(model.lines[0].total - 11.98) < 0.001)
        // Never below one.
        model.setQuantity(0, for: pasta)
        #expect(model.lines[0].quantity == 2)
    }

    @Test func weighedProductsGoToTheListInGrams() {
        let cheese = ReceiptScanLine(itemNumber: 25, name: "Queijo", quantity: 1, weightKg: 0.364, total: 18.16, warning: nil)
        let cheeseAmount = ReceiptScanViewModel.listAmount(for: cheese)
        #expect(cheeseAmount.quantity == 364 && cheeseAmount.unit == .gram)

        // Past the quantity field's 1000: kilograms.
        let melon = ReceiptScanLine(itemNumber: 39, name: "Melancia", quantity: 1, weightKg: 1.845, total: 10.13, warning: nil)
        let melonAmount = ReceiptScanViewModel.listAmount(for: melon)
        #expect(melonAmount.quantity == 2 && melonAmount.unit == .kilogram)

        // A weight past the quantity field's 1000 g.
        #expect(ReceiptScanViewModel.listAmount(weightKg: 0.364).quantity == 364)
        #expect(ReceiptScanViewModel.listAmount(weightKg: 2.525).unit == .kilogram)

        let milk = ReceiptScanLine(itemNumber: 11, name: "Leite", quantity: 2, weightKg: 0, total: 13.18, warning: nil)
        let milkAmount = ReceiptScanViewModel.listAmount(for: milk)
        #expect(milkAmount.quantity == 2 && milkAmount.unit == .unit)
    }

    @Test func abbreviationsAreSpelledOut() {
        #expect(ReceiptAbbreviations.expand("LTE COND.MOC.TP 395g") == "Leite condensado moc tp 395g")
        #expect(ReceiptAbbreviations.expand("QJ.MUSS.AUR.FAT.150g") == "Queijo muçarela aur fatiado 150g")
        #expect(ReceiptAbbreviations.expand("PAP HIG NEVE 30M") == "Papel higiênico neve 30m")
        // Restaurants print in mixed case: kept as is.
        #expect(ReceiptAbbreviations.expand("Suco Natural One") == "Suco Natural One")
    }

    @Test func spelledOutNamesMatchTheList() {
        let names = ["LTE COND.MOC.TP 395g", "DETERG LIQ YPE 500ML", "REFRIG GUARANA 2L"].map(ReceiptAbbreviations.expand)
        let list = ["Detergente", "Refrigerante", "Leite condensado"]
        let pairs = ReceiptItemMatcher.match(receiptNames: names, listNames: list)
        #expect(pairs == [0: 1, 1: 2, 2: 0])
    }

    @Test func rememberedNamesComeBack() {
        let cheese = ReceiptScanLine(itemNumber: 4, name: "Queijo muçarela", quantity: 1, weightKg: 0, total: 10.49,
                                     warning: nil, barcode: "07891164027117", receiptName: "QJ.MUSS.AUR.FAT.150g")
        #expect(ReceiptNameMemory.keys(for: cheese) == ["ean:07891164027117", "name:qj muss aur fat 150g"])

        let stored = ReceiptNameMemory.merge(nil, with: ["ean:07891164027117": "Queijo"])
        let memory = ReceiptNameMemory.decode(stored)
        #expect(ReceiptNameMemory.name(for: cheese, in: memory) == "Queijo")

        // Same product, another receipt where OCR misread the barcode: the name still finds it.
        let byName = ReceiptNameMemory.decode(ReceiptNameMemory.merge(stored, with: ["name:qj muss aur fat 150g": "Queijo fatiado"]))
        var misread = cheese
        misread.barcode = "07891164027118"
        #expect(ReceiptNameMemory.name(for: misread, in: byName) == "Queijo fatiado")
    }

    @Test func memoryKeepsTheNewestWithinItsLimit() {
        var stored: [String] = []
        for index in 0..<(ReceiptNameMemory.limit + 5) {
            stored = ReceiptNameMemory.merge(stored, with: ["name:item \(index)": "Item \(index)"])
        }
        #expect(stored.count == ReceiptNameMemory.limit)
        let memory = ReceiptNameMemory.decode(stored)
        #expect(memory["name:item 0"] == nil)
        #expect(memory["name:item \(ReceiptNameMemory.limit + 4)"] != nil)
    }
}
