//
//  CouponPricing.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 16/10/26.
//

import Foundation

/// Price of a chore's coupon, in coins.
///
/// A coupon spares its holder one cycle of that chore, so it costs in proportion to the work it
/// spares:
///
/// ```
/// price = max(minimumPrice, ⌈basePrice + coinsPerMinute × duration × occurrencesPerCycle⌉)
/// ```
///
/// `duration` is the chore's length in minutes and `occurrencesPerCycle` comes from its
/// frequency (``Recurrence/occurrencesPerCycle``: daily = 14, weekly = 2…). The price therefore
/// grows with both how often and how long the chore is.
struct CouponPricing: Equatable {

    /// Fixed part of every coupon's price.
    var basePrice: Double = 5

    /// Coins per minute of work the coupon spares in one cycle.
    var coinsPerMinute: Double = 0.1

    /// No coupon costs less than this.
    var minimumPrice: Int = 1

    /// The pricing the app uses.
    static let current = CouponPricing()

    /// The price of a coupon for a chore with this frequency and duration (see the formula above).
    /// - Parameters:
    ///   - frequency: How often the chore repeats.
    ///   - durationMinutes: How long the chore takes, in minutes.
    /// - Returns: The price in coins, never below ``minimumPrice``.
    func price(frequency: Recurrence, durationMinutes: Double) -> Int {
        let minutes = max(durationMinutes, 0)
        let raw = basePrice + coinsPerMinute * minutes * frequency.occurrencesPerCycle
        // The tolerance keeps floating-point noise (5 + 0.1 × 15 × 14 = 26.000000000000004) from
        // rounding up to the next coin.
        let rounded = Int((raw - 1e-9).rounded(.up))
        return max(minimumPrice, rounded)
    }

    /// The price of `chore`'s coupon.
    func price(for chore: ChoreModel) -> Int {
        price(frequency: chore.frequency, durationMinutes: chore.duration)
    }
}
