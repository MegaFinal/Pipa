//
//  ShopListItemPriceTests.swift
//  Cognitive-WorkTests
//

import Testing
import Foundation
import CloudKit
@testable import Cognitive_Work

/// The item's price is the total paid for the whole item; the price of one unit is derived
/// from it.
struct ShopListItemPriceTests {

    /// A record with the fields every item has.
    private func makeRecord(quantity: Int, unit: UnitMeasurement = .unit) -> CKRecord {
        let record = CKRecord(recordType: ShopListItem.recordType)
        record["name"] = "Pão"
        record["quantity"] = quantity
        record["unitMeasurement"] = unit.rawValue
        record["isBought"] = false
        return record
    }

    // MARK: - Reading records

    @Test func savedTotalRoundTrips() throws {
        let item = ShopListItem(name: "Queijo", totalPrice: 18.16, quantity: 364, unitMeasurement: .gram)
        let record = makeRecord(quantity: 364, unit: .gram)
        item.populate(record: record)

        #expect(record["totalPrice"] as? Double == 18.16)
        let decoded = try #require(ShopListItem(record: record))
        #expect(decoded.totalPrice == 18.16)
    }

    @Test func totalIsNotMultipliedByQuantity() throws {
        let record = makeRecord(quantity: 4)
        record["totalPrice"] = 12.0

        let item = try #require(ShopListItem(record: record))
        #expect(item.totalValue == 12)
        #expect(item.unitPrice?.amount == 3)
    }

    @Test func clearingPriceClearsField() {
        let item = ShopListItem(name: "Pão", totalPrice: nil, quantity: 4, unitMeasurement: .unit)
        let record = makeRecord(quantity: 4)
        record["totalPrice"] = 12.0
        item.populate(record: record)

        #expect(record["totalPrice"] == nil)
        #expect(item.hasPrice == false)
    }

    // MARK: - Unit price

    @Test func unitPricePerPiece() throws {
        let price = try #require(ShopListItem.unitPrice(total: 12, quantity: 4, unit: .unit))
        #expect(price.amount == 3)
        #expect(price.unit == .unit)
    }

    @Test func gramsArePricedPerKilogram() throws {
        let price = try #require(ShopListItem.unitPrice(total: 25, quantity: 500, unit: .gram))
        #expect(price.amount == 50)
        #expect(price.unit == .kilogram)
    }

    @Test func millilitersArePricedPerLiter() throws {
        let price = try #require(ShopListItem.unitPrice(total: 6, quantity: 1500, unit: .milliliter))
        #expect(abs(price.amount - 4) < 0.0001)
        #expect(price.unit == .liter)
    }

    @Test func noUnitPriceWithoutTotal() {
        #expect(ShopListItem.unitPrice(total: 0, quantity: 4, unit: .unit) == nil)
    }
}
