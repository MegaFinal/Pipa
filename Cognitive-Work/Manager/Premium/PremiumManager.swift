//
//  PremiumManager.swift
//  Cognitive-Work
//

import Foundation
import CloudKit

/// Answers "is this house Premium?" for the whole app.
///
/// Premium is per house, but App Store subscriptions belong to one Apple ID. So:
/// 1. The member who subscribes has the entitlement on their device (``StoreManager``).
/// 2. That device copies the expiration date into the house record
///    (``HouseModel/premiumExpiresAt``), which every member can read.
/// 3. Everyone else is Premium while that date (plus ``gracePeriod``) hasn't passed.
///
/// The subscriber's device writes the new date again on every renewal it sees (app launch,
/// back to foreground, `Transaction.updates`).
@MainActor
@Observable
final class PremiumManager {

    static let shared = PremiumManager()

    /// Extra time the house stays Premium after the date in the record. A renewal only reaches
    /// the record when the subscriber opens the app, so this keeps housemates from losing
    /// Premium in the meantime.
    static let gracePeriod: TimeInterval = 3 * 24 * 60 * 60

    // MARK: - State

    /// Until when the house record says the house is Premium.
    private(set) var houseExpiresAt: Date?

    /// iCloud record name of the member who pays (same as ``UserModel/ownerRecordName``).
    private(set) var houseOwnerRecordName: String?

    /// The plan saved in the house record (whoever pays for it).
    private(set) var housePlan: PremiumPlan?

    /// The signed-in iCloud account's record name, read once.
    @ObservationIgnored
    private var myRecordName: String?

    private let store = StoreManager.shared

    private init() {
        store.onEntitlementsChanged = { [weak self] in
            await self?.entitlementsDidChange()
        }
    }

    // MARK: - Lifecycle

    /// Starts StoreKit (see ``StoreManager/start()``). Call once at launch.
    func start() async {
        await store.start()
    }

    // MARK: - Reading

    /// Whether the house has Premium: this Apple ID is subscribed, or a housemate is.
    var isPremium: Bool {
        store.hasActiveSubscription || isHousePremium
    }

    /// Whether the house record still grants Premium.
    ///
    /// The grace period is for *housemates*, who can't see the subscription. On the payer's own
    /// device StoreKit is the source of truth, so the house record is ignored there: once the
    /// subscription ends, it ends at once.
    private var isHousePremium: Bool {
        guard let houseExpiresAt else { return false }
        if store.hasLoadedEntitlements, let myRecordName, houseOwnerRecordName == myRecordName {
            return false
        }
        return houseExpiresAt.addingTimeInterval(Self.gracePeriod) > .now
    }

    /// Whether this person is the one paying.
    var isPaidByMe: Bool { store.hasActiveSubscription }

    /// Whether the house is Premium thanks to someone else's subscription.
    var isPaidByHousemate: Bool { !store.hasActiveSubscription && isHousePremium }

    /// When Premium ends unless renewed; `nil` for the lifetime purchase.
    var expirationDate: Date? {
        if currentPlan?.isLifetime == true { return nil }
        return store.expirationDate ?? houseExpiresAt
    }

    // MARK: - House size and price bracket

    /// How many people live in the house (one per person, see ``HouseSnapshot/users``).
    /// Reading it from the observable ``HouseDataStore`` keeps the paywall up to date when
    /// someone joins or leaves.
    var memberCount: Int {
        max(HouseDataStore.shared.snapshot?.users.count ?? 1, 1)
    }

    /// The price bracket this house belongs to today.
    var requiredTier: HouseSizeTier {
        HouseSizeTier(memberCount: memberCount)
    }

    /// The plan that pays for the house: mine if I'm subscribed, otherwise the one in the
    /// house record.
    var currentPlan: PremiumPlan? {
        store.activePlan ?? (isPremium ? housePlan : nil)
    }

    /// The house grew past the bracket it pays for (e.g. a 3-person plan and a 4th person
    /// joined). Premium keeps working — nobody loses features because a friend moved in — but
    /// the payer is asked to upgrade (the App Store prorates the difference).
    var needsUpgrade: Bool {
        guard let currentPlan else { return false }
        return !currentPlan.covers(requiredTier)
    }

    /// Whether `feature` can be used right now. Every Premium feature has the same rule today;
    /// asking per feature leaves room for a free trial of a single feature later.
    func allows(_ feature: PremiumFeature) -> Bool {
        isPremium
    }

    // MARK: - Syncing

    /// Reads the Premium fields from `house` and, if this device has the subscription, writes it
    /// into the house. Called every time the app fetches the house (``ContentViewModel``).
    func refresh(house: HouseModel?) async {
        houseExpiresAt = house?.premiumExpiresAt
        houseOwnerRecordName = house?.premiumOwnerRecordName
        housePlan = house?.premiumProductID.flatMap(PremiumPlan.init(productID:))
        guard let house else { return }
        await syncSubscription(into: house)
    }

    /// The subscription started, renewed, expired or was refunded.
    private func entitlementsDidChange() async {
        let house = try? await CloudKitManager.shared.currentHouse()
        await refresh(house: house)
    }

    /// Copies this Apple ID's subscription into the house record, writing only when something
    /// changed (every save notifies the other members' devices).
    private func syncSubscription(into house: HouseModel) async {
        guard store.hasLoadedEntitlements, let me = await currentRecordName() else { return }
        let houseDate = house.premiumExpiresAt
        let isMine = house.premiumOwnerRecordName == me

        if let myExpiration = store.entitlementEnd, let myPlan = store.activePlan {
            // Mine: keep the date and plan current (renewal, upgrade). Someone else's: take over
            // only if mine lasts longer (two members subscribed by mistake).
            let needsWrite = isMine
                ? !Self.sameMoment(houseDate, myExpiration) || house.premiumProductID != myPlan.productID
                : myExpiration > (houseDate ?? .distantPast)
            guard needsWrite else { return }
            if await house.setPremium(expiresAt: myExpiration, ownerRecordName: me, productID: myPlan.productID) {
                houseExpiresAt = myExpiration
                houseOwnerRecordName = me
                housePlan = myPlan
            }
        } else if isMine, houseDate != nil {
            // The house says I'm paying, but I'm not subscribed anymore: the period ended after a
            // cancellation, or it was refunded. Remove Premium now instead of letting the
            // housemates ride the grace period for a subscription that is known to be over.
            if await house.setPremium(expiresAt: nil, ownerRecordName: nil, productID: nil) {
                houseExpiresAt = nil
                houseOwnerRecordName = nil
                housePlan = nil
            }
        }
    }

    /// The signed-in iCloud account's record name.
    private func currentRecordName() async -> String? {
        if let myRecordName { return myRecordName }
        myRecordName = await CloudKitManager.shared.fetchCurrentUserRecordID()?.recordName
        return myRecordName
    }

    /// CloudKit keeps dates to the millisecond, so compare with a one-second tolerance;
    /// otherwise the same date would look different and be written on every launch.
    private static func sameMoment(_ lhs: Date?, _ rhs: Date?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        return abs(lhs.timeIntervalSince(rhs)) < 1
    }
}
