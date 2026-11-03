//
//  StoreManager.swift
//  Cognitive-Work
//

import Foundation
import StoreKit

/// Talks to the App Store (StoreKit 2): knows whether *this Apple ID* has an active Premium
/// subscription and keeps listening for renewals, refunds and purchases made elsewhere.
///
/// It doesn't know about houses. ``PremiumManager`` combines this with the house record to
/// decide whether the house is Premium.
///
/// The purchase screen itself is StoreKit's `SubscriptionStoreView` (see ``PremiumView``), so
/// this class doesn't load products or call `purchase()`; it only verifies and finishes the
/// transactions and reads the entitlements.
@MainActor
@Observable
final class StoreManager {

    static let shared = StoreManager()

    // MARK: - State

    /// The verified transaction that currently gives this Apple ID Premium (a subscription or
    /// the lifetime purchase), or `nil`.
    private(set) var activeTransaction: Transaction?

    /// The plan this Apple ID owns (see ``PremiumPlan``), or `nil`.
    var activePlan: PremiumPlan? {
        guard hasActiveSubscription, let activeTransaction else { return nil }
        return PremiumPlan(productID: activeTransaction.productID)
    }

    /// `false` until the entitlements were read at least once. Before that, "no subscription"
    /// only means "not checked yet".
    private(set) var hasLoadedEntitlements = false

    /// Whether this Apple ID is subscribed right now. Also checks the date, because the period
    /// can end while the app is open (``refreshEntitlements()`` runs again on foreground).
    var hasActiveSubscription: Bool {
        guard let activeTransaction else { return false }
        return (activeTransaction.expirationDate ?? .distantFuture) > .now
    }

    /// When the current period ends (it renews automatically unless cancelled). `nil` for the
    /// lifetime purchase, which never ends.
    var expirationDate: Date? { activeTransaction?.expirationDate }

    /// Until when this Apple ID has Premium: the end of the period, or ``lifetimeDate`` for the
    /// lifetime purchase. `nil` when not subscribed.
    var entitlementEnd: Date? {
        guard hasActiveSubscription else { return nil }
        return expirationDate ?? Self.lifetimeDate
    }

    /// The date written to the house for a lifetime purchase (1 Jan 2100).
    static let lifetimeDate = Date(timeIntervalSince1970: 4_102_444_800)

    /// Called whenever ``activeTransaction`` changes. ``PremiumManager`` uses it to copy the
    /// subscription into the house record.
    @ObservationIgnored
    var onEntitlementsChanged: (() async -> Void)?

    /// Listens to `Transaction.updates` for the whole app session.
    @ObservationIgnored
    private var updatesTask: Task<Void, Never>?

    private init() {}

    // MARK: - Lifecycle

    /// Starts listening for transactions and reads the current entitlements.
    ///
    /// Call it as early as possible (app launch): a renewal, a refund or a purchase approved by
    /// "Ask to Buy" arrives through `Transaction.updates`, and if nobody listens the transaction
    /// stays unfinished. Calling it again does nothing.
    func start() async {
        guard updatesTask == nil else { return }
        updatesTask = Task {
            for await update in Transaction.updates {
                await self.handle(update)
            }
        }
        await refreshEntitlements()
    }

    // MARK: - Transactions

    /// Verifies and finishes a transaction (from a purchase or from `Transaction.updates`), then
    /// reads the entitlements again.
    ///
    /// Unverified transactions (the JWS signature doesn't match) are ignored and never unlock
    /// anything.
    func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else {
            print("StoreManager: ignoring unverified transaction")
            return
        }
        await transaction.finish()
        await refreshEntitlements()
    }

    /// Reads `Transaction.currentEntitlements` and keeps the one that lasts the longest (the
    /// lifetime purchase, with no expiration date, wins over any subscription).
    ///
    /// `currentEntitlements` already leaves out expired and refunded purchases; the extra
    /// checks only make that explicit.
    func refreshEntitlements() async {
        var best: Transaction?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  PremiumPlan.allProductIDs.contains(transaction.productID),
                  transaction.revocationDate == nil
            else { continue }
            if let expiration = transaction.expirationDate, expiration < .now { continue }

            let bestExpiration = best?.expirationDate ?? .distantPast
            if (transaction.expirationDate ?? .distantFuture) > bestExpiration {
                best = transaction
            }
        }

        let changed = best?.id != activeTransaction?.id
            || best?.expirationDate != activeTransaction?.expirationDate
            || !hasLoadedEntitlements
        activeTransaction = best
        hasLoadedEntitlements = true

        if changed {
            await onEntitlementsChanged?()
        }
    }

    /// "Restaurar compras": asks the App Store for this Apple ID's purchases (it may ask for the
    /// password). Only needed when the subscription doesn't show up by itself, e.g. on a new
    /// device.
    func restore() async throws {
        try await AppStore.sync()
        await refreshEntitlements()
    }
}
