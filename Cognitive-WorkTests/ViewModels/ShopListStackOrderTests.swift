//
//  ShopListStackOrderTests.swift
//  Cognitive-WorkTests
//

import Testing
import Foundation
@testable import Cognitive_Work

/// The order of the shopping list's stacked cards: closed ones first, open ones after, and each
/// group always in the sections' original order.
@MainActor
struct ShopListStackOrderTests {

    /// A list with one pending item in food, drinks, produce and cleaning (the fixed order).
    private func makeViewModel() -> ShopListViewModel {
        let items = [
            ShopListPreviewData.makeItem("Arroz", quantity: 1, category: .food),
            ShopListPreviewData.makeItem("Suco", quantity: 1, category: .drinks),
            ShopListPreviewData.makeItem("Banana", quantity: 1, category: .produce),
            ShopListPreviewData.makeItem("Detergente", quantity: 1, category: .cleaning)
        ]
        return ShopListViewModel(previewItems: items)
    }

    private func order(of viewModel: ShopListViewModel) -> [ShopItemCategory] {
        viewModel.stackEntries(for: viewModel.pendingSections).compactMap(\.section.category)
    }

    private func toggle(_ category: ShopItemCategory, in viewModel: ShopListViewModel) {
        let section = viewModel.pendingSections.first { $0.category == category }!
        viewModel.toggleCollapsed(section)
    }

    @Test func categoryCardsStartClosedInOriginalOrder() {
        let viewModel = makeViewModel()
        let entries = viewModel.stackEntries(for: viewModel.pendingSections)

        #expect(order(of: viewModel) == [.food, .drinks, .produce, .cleaning])
        #expect(entries.allSatisfy { !$0.isExpanded })
        // Every closed card overlaps the next one, except the last.
        #expect(entries.map(\.overlapsNext) == [true, true, true, false])
    }

    @Test func openingACardSendsItBelowTheClosedOnes() {
        let viewModel = makeViewModel()
        toggle(.produce, in: viewModel)

        #expect(order(of: viewModel) == [.food, .drinks, .cleaning, .produce])
    }

    @Test func openCardsKeepTheirOriginalOrder() {
        let viewModel = makeViewModel()
        toggle(.drinks, in: viewModel)
        toggle(.food, in: viewModel)

        // Food opened after drinks, but it still lands above it.
        #expect(order(of: viewModel) == [.produce, .cleaning, .food, .drinks])

        toggle(.cleaning, in: viewModel)
        #expect(order(of: viewModel) == [.produce, .food, .drinks, .cleaning])
    }

    @Test func closingACardPutsItBackInItsPlace() {
        let viewModel = makeViewModel()
        toggle(.drinks, in: viewModel)
        toggle(.food, in: viewModel)
        toggle(.food, in: viewModel)

        #expect(order(of: viewModel) == [.food, .produce, .cleaning, .drinks])
    }

    @Test func onlyAnOpeningCardIsRaised() {
        let viewModel = makeViewModel()
        toggle(.drinks, in: viewModel)
        #expect(viewModel.movingSectionID == ShopItemCategory.drinks.rawValue)

        toggle(.drinks, in: viewModel)
        #expect(viewModel.movingSectionID == nil)
    }

    @Test func listFollowsTheFixedCategoryOrder() {
        let items = [
            ShopListPreviewData.makeItem("Ração", quantity: 1, category: .pets),
            ShopListPreviewData.makeItem("Dipirona", quantity: 1, category: .hygiene),
            ShopListPreviewData.makeItem("Pilha", quantity: 1, category: .other),
            ShopListPreviewData.makeItem("Sabão", quantity: 1, category: .cleaning),
            ShopListPreviewData.makeItem("Maçã", quantity: 1, category: .produce),
            ShopListPreviewData.makeItem("Água", quantity: 1, category: .drinks),
            ShopListPreviewData.makeItem("Arroz", quantity: 1, category: .food)
        ]
        let viewModel = ShopListViewModel(previewItems: items)

        #expect(order(of: viewModel) == [.food, .drinks, .produce, .cleaning, .other, .hygiene, .pets])
    }

    @Test func onlyOpenCardsAfterAnOpenCardArePerforated() {
        let viewModel = makeViewModel()
        toggle(.food, in: viewModel)
        toggle(.drinks, in: viewModel)

        let entries = viewModel.stackEntries(for: viewModel.pendingSections)
        // produce, cleaning (closed), food, drinks (open)
        #expect(entries.map(\.followsExpanded) == [false, false, false, true])
        #expect(entries.map(\.precedesExpanded) == [false, false, true, false])
    }

    @Test func boughtCardStartsOpen() {
        let viewModel = ShopListViewModel(previewItems: [
            ShopListPreviewData.makeItem("Arroz", quantity: 1, category: .food, isBought: true)
        ])

        let entries = viewModel.stackEntries(for: [viewModel.boughtSection!])
        #expect(entries.count == 1)
        #expect(entries.first?.isExpanded == true)
    }

    @Test func sortingReordersItemsInsideEachCategoryCard() {
        // `createdAt` is set when an item is created, so create the old ones first.
        let oldFood = ShopListPreviewData.makeItem("Arroz velho", quantity: 1, category: .food)
        let oldDrink = ShopListPreviewData.makeItem("Suco velho", quantity: 1, category: .drinks)
        Thread.sleep(forTimeInterval: 0.02)
        let newFood = ShopListPreviewData.makeItem("Arroz novo", quantity: 1, category: .food)
        let newDrink = ShopListPreviewData.makeItem("Suco novo", quantity: 1, category: .drinks)
        let items = [oldFood, newFood, oldDrink, newDrink]
        let viewModel = ShopListViewModel(previewItems: items)

        // Still one card per category, in the fixed order, whatever the sort.
        viewModel.sortOption = .newestFirst
        #expect(viewModel.pendingSections.map(\.title) == [ShopItemCategory.food.displayName, ShopItemCategory.drinks.displayName])
        #expect(viewModel.pendingSections.map { $0.items.map(\.name) } == [["Arroz novo", "Arroz velho"], ["Suco novo", "Suco velho"]])

        viewModel.sortOption = .oldestFirst
        #expect(viewModel.pendingSections.map(\.title) == [ShopItemCategory.food.displayName, ShopItemCategory.drinks.displayName])
        #expect(viewModel.pendingSections.map { $0.items.map(\.name) } == [["Arroz velho", "Arroz novo"], ["Suco velho", "Suco novo"]])
    }
}
