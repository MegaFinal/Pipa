//
//  ReceiptLineDraftTests.swift
//  Cognitive-WorkTests
//
//  Created by Dayô Araújo on 06/11/26.
//

import Testing
@testable import Cognitive_Work

/// The receipt review's product form: it works on a copy (``ReceiptLineDraft``), and only a
/// confirmed copy changes the review.
@MainActor
struct ReceiptLineDraftTests {

    private let users = ShopListPreviewData.users

    /// A review with one detergent read from the receipt and the preview list to link to.
    private func makeReview(lines: [ReceiptScanLine]) -> (ReceiptScanViewModel, [ShopListItem]) {
        let items = ShopListPreviewData.items.filter { !$0.isBought }
        let model = ReceiptScanViewModel()
        model.load(
            ReceiptScanResult(lines: lines, printedTotals: []),
            linking: items,
            houseUsers: users
        )
        return (model, items)
    }

    @Test func thePriceFollowsTheQuantityInTheForm() {
        let pasta = ReceiptScanLine(itemNumber: 1, name: "Macarrão", quantity: 1, weightKg: 0, total: 5.99, warning: nil)
        let (model, _) = makeReview(lines: [pasta])
        var draft = model.draft(for: pasta)

        model.setQuantity(3, in: &draft)
        #expect(draft.priceText == "17,97")
        // Nothing changes on the review until the form is confirmed.
        #expect(model.lines[0].quantity == 1)

        model.save(draft)
        #expect(model.lines[0].quantity == 3)
        #expect(abs(model.lines[0].total - 17.97) < 0.001)
    }

    @Test func aTypedPriceClearsTheWarning() {
        let soda = ReceiptScanLine(itemNumber: 1, name: "Refrigerante", quantity: 1, weightKg: 0, total: 8.49,
                                   warning: .totalMismatch(computed: 8.49, printed: 8.94))
        let (model, _) = makeReview(lines: [soda])
        var draft = model.draft(for: soda)
        model.setPrice("8,94", in: &draft)
        model.save(draft)
        #expect(model.lines[0].warning == nil)
        #expect(abs(model.lines[0].total - 8.94) < 0.001)
    }

    @Test func closingTheFormOfANewProductRemovesIt() {
        let (model, _) = makeReview(lines: [
            ReceiptScanLine(itemNumber: 1, name: "Macarrão", quantity: 1, weightKg: 0, total: 5.99, warning: nil)
        ])
        let added = model.addLine()
        let draft = model.draft(for: added)
        #expect(draft.isNew)

        model.discard(draft)
        #expect(model.lines.count == 1)
    }

    @Test func aConfirmedNewProductStays() {
        let (model, _) = makeReview(lines: [])
        let added = model.addLine()
        var draft = model.draft(for: added)
        model.setName("Pão de queijo", in: &draft)
        model.setPrice("12,00", in: &draft)
        model.save(draft)
        model.discard(draft)

        #expect(model.lines.count == 1)
        #expect(model.lines[0].name == "Pão de queijo")
        #expect(model.newLineIDs.isEmpty)
    }

    @Test func aProductWithoutANameCantBeSaved() {
        let (model, _) = makeReview(lines: [])
        let added = model.addLine()
        let draft = model.draft(for: added)
        #expect(model.missingFieldText(in: draft) != nil)

        model.save(draft)
        #expect(model.newLineIDs.contains(added.id))
    }

    @Test func thePeopleFollowTheListItemUntilPicked() throws {
        let gum = ReceiptScanLine(itemNumber: 1, name: "Chiclete", quantity: 1, weightKg: 0, total: 2.5, warning: nil)
        let (model, items) = makeReview(lines: [gum])
        let rice = try #require(items.first { $0.name == "Arroz" })
        var draft = model.draft(for: gum)
        #expect(draft.consumers.count == users.count)

        model.setLink(rice.id, in: &draft)
        #expect(Set(draft.consumers.map(\.id)) == Set(rice.relatedUsers(in: users).map(\.id)))

        model.setConsumers([users[0]], in: &draft)
        model.setLink(nil, in: &draft)
        #expect(draft.consumers.map(\.id) == [users[0].id])
    }

    @Test func linkingMovesTheProductToTheListSection() throws {
        let gum = ReceiptScanLine(itemNumber: 1, name: "Chiclete", quantity: 1, weightKg: 0, total: 2.5, warning: nil)
        let (model, items) = makeReview(lines: [gum])
        let rice = try #require(items.first { $0.name == "Arroz" })
        var draft = model.draft(for: gum)
        model.setLink(rice.id, in: &draft)
        model.save(draft)

        #expect(model.listLines.map(\.id) == [gum.id])
        #expect(model.category(for: model.lines[0]) == rice.category)
    }
}
