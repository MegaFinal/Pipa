//
//  CouponPricingTests.swift
//  Cognitive-WorkTests
//
//  Created by Jonas Melo on 16/10/26.
//

import Testing
import Foundation
@testable import Cognitive_Work

@MainActor
struct CouponPricingTests {

    /// base 5, 0.1 coin/min, daily = 14, weekly = 2, fortnightly/monthly/none = 1.
    let pricing = CouponPricing()

    @Test func followsTheFormula() {
        // 5 + 0.1 × 15 × 14 = 26 (not 27: floating-point noise must not round up)
        #expect(pricing.price(frequency: .daily, durationMinutes: 15) == 26)
        // 5 + 0.1 × 30 × 2 = 11
        #expect(pricing.price(frequency: .weekly, durationMinutes: 30) == 11)
        // 5 + 0.1 × 120 × 1 = 17
        #expect(pricing.price(frequency: .monthly, durationMinutes: 120) == 17)
        // 5 + 0.1 × 25 × 1 = 7.5 → 8
        #expect(pricing.price(frequency: .none, durationMinutes: 25) == 8)
    }

    @Test func moreFrequentChoresCostMore() {
        let daily = pricing.price(frequency: .daily, durationMinutes: 30)
        let weekly = pricing.price(frequency: .weekly, durationMinutes: 30)
        let fortnightly = pricing.price(frequency: .fortnightly, durationMinutes: 30)
        #expect(daily > weekly)
        #expect(weekly > fortnightly)
    }

    @Test func longerChoresCostMore() {
        let durations: [Double] = [5, 15, 30, 60, 120]
        let prices = durations.map { pricing.price(frequency: .weekly, durationMinutes: $0) }
        #expect(prices == prices.sorted())
        #expect(Set(prices).count == prices.count)
    }

    @Test func neverBelowMinimumPrice() {
        let cheap = CouponPricing(basePrice: 0, minimumPrice: 3)
        #expect(cheap.price(frequency: .none, durationMinutes: 0) == 3)
        #expect(cheap.price(frequency: .none, durationMinutes: -10) == 3)
    }

    @Test func parametersCanBeChanged() {
        let custom = CouponPricing(basePrice: 10, coinsPerMinute: 1)
        // 10 + 1 × 20 × 2 = 50
        #expect(custom.price(frequency: .weekly, durationMinutes: 20) == 50)
    }

    @Test func pricesAChoreByItsFrequencyAndDuration() {
        let chore = ChoreModel(name: "Louça", description: "", frequency: .daily, duration: 15,
                               isPublic: true, priorityTag: .medium)
        #expect(pricing.price(for: chore) == 26)
    }
}
