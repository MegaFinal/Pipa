//
//  PremiumManager.swift
//  Cognitive-Work
//

import Foundation
import CloudKit
import CryptoKit

/// Answers "is this house Premium?" for the whole app.
///
/// Premium is per house, but App Store purchases belong to one Apple ID. So:
/// 1. The member who pays has the entitlement on their device (``StoreManager``).
/// 2. That device copies it into the house record (``HouseModel/premiumExpiresAt``), which every
///    member can read.
/// 3. Everyone else is Premium while that record is valid.
///
/// ## Which house a purchase covers
/// - **Subscription:** it belongs to the house where it was bought. The purchase carries the
///   house's ``purchaseToken(for:)`` (StoreKit's `appAccountToken`, kept on every renewal), and
///   only that house gets it. If the payer leaves, the house goes back to free — and joining
///   another house doesn't make that one Premium.
/// - **Lifetime:** it belongs to the person and covers whatever house they're in. When they
///   leave, the house they left goes back to free.
///
/// ## Free trial
/// A new house gets 2 months of Premium, paid by nobody (``startTrialIfEligible(for:)``). It's
/// once per person: the creator's iCloud keeps a mark that they already used it, so creating
/// another house doesn't start a new trial.
///
/// Before the payer leaves (``releaseHouseBeforeLeaving(_:)``), their device clears the house
/// record and tells the other members. If that couldn't happen (offline), the other members'
/// devices notice the payer isn't a member anymore and stop treating the house as Premium.
@MainActor
@Observable
final class PremiumManager {

    static let shared = PremiumManager()

    /// Extra time the house stays Premium after the date in the record. A renewal only reaches
    /// the record when the payer opens the app, so this keeps housemates from losing Premium
    /// in the meantime.
    static let gracePeriod: TimeInterval = 3 * 24 * 60 * 60

    // MARK: - State

    /// Until when the house record says the house is Premium.
    private(set) var houseExpiresAt: Date?

    /// iCloud record name of the member who pays (same as ``UserModel/ownerRecordName``).
    private(set) var houseOwnerRecordName: String?

    /// The plan saved in the house record (whoever pays for it).
    private(set) var housePlan: PremiumPlan?

    /// Until when the house is on its free trial.
    private(set) var houseTrialEndsAt: Date?

    /// ``purchaseToken(for:)`` of the house the person is in, or `nil` without a house.
    private(set) var currentHouseToken: UUID?

    /// The signed-in iCloud account's record name, read once.
    private var myRecordName: String?

    /// The house this device is leaving: nothing is written into it anymore, so a sync running
    /// at the same time can't put Premium back after ``releaseHouseBeforeLeaving(_:)``.
    @ObservationIgnored
    private var houseBeingLeft: String?

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

    // MARK: - House token

    /// A fixed UUID for a house, the same on every member's device. Sent with a purchase as
    /// StoreKit's `appAccountToken`, so the subscription stays tied to that house.
    static func purchaseToken(for houseID: CKRecord.ID) -> UUID {
        // Only the record and zone names: the zone's owner name reads differently on the
        // owner's device ("__defaultOwner__") and on the members' devices.
        let source = "pipa-house:\(houseID.zoneID.zoneName)/\(houseID.recordName)"
        var bytes = Array(SHA256.hash(data: Data(source.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50   // RFC 4122 version 5 (name-based)
        bytes[8] = (bytes[8] & 0x3F) | 0x80   // RFC 4122 variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    // MARK: - Reading

    /// Whether the house has Premium: this person pays for it, a housemate does, or it's on
    /// its free trial.
    var isPremium: Bool {
        isPaidByMe || isHousePremium || isTrialActive
    }

    /// Whether the house's 2-month free trial is still running.
    var isTrialActive: Bool {
        (houseTrialEndsAt ?? .distantPast) > .now
    }

    /// Premium only thanks to the trial: nobody pays yet. The paywall still offers the plans,
    /// so the house can subscribe before the trial ends.
    var isOnTrialOnly: Bool {
        isTrialActive && !isPaidByMe && !isHousePremium
    }

    /// Whether this person's purchase covers the house they're in: a lifetime purchase always
    /// does; a subscription only in the house where it was bought.
    var isPaidByMe: Bool {
        guard let plan = store.activePlan else { return false }
        if plan.isLifetime { return true }
        guard let currentHouseToken else { return false }
        if let token = store.activeAppAccountToken {
            return token == currentHouseToken
        }
        // Bought before subscriptions were tied to a house (no token): it covers only the house
        // whose record already says this person pays.
        return myRecordName != nil && houseOwnerRecordName == myRecordName
    }

    /// The person has a subscription, but it belongs to another house (they subscribed there and
    /// moved). It doesn't cover this house; the paywall explains it.
    var hasSubscriptionElsewhere: Bool {
        store.hasActiveSubscription && store.activePlan?.isLifetime == false && !isPaidByMe
    }

    /// Whether the house is Premium thanks to someone else's purchase.
    var isPaidByHousemate: Bool { !isPaidByMe && isHousePremium }

    /// Whether the house record still grants Premium.
    ///
    /// - On the payer's own device StoreKit is the source of truth, so the record is ignored.
    /// - The payer must still live here: someone who left doesn't pay for the house anymore,
    ///   even if their device couldn't clear the record before leaving.
    /// - The grace period covers renewals the payer's device hasn't written yet.
    private var isHousePremium: Bool {
        guard let houseExpiresAt, let owner = houseOwnerRecordName else { return false }
        if store.hasLoadedEntitlements, owner == myRecordName { return false }
        if payerLeft(owner) { return false }
        return houseExpiresAt.addingTimeInterval(Self.gracePeriod) > .now
    }

    /// Whether `owner` is no longer one of the house's members. `false` while the members
    /// aren't loaded, so a slow load never takes Premium away.
    private func payerLeft(_ owner: String) -> Bool {
        guard let snapshot = HouseDataStore.shared.snapshot, !snapshot.isPlaceholder,
              !snapshot.users.isEmpty else { return false }
        return !snapshot.users.contains { $0.ownerRecordName == owner }
    }

    /// When Premium ends unless renewed; `nil` for the lifetime purchase.
    var expirationDate: Date? {
        if currentPlan?.isLifetime == true { return nil }
        return isPaidByMe ? store.expirationDate : houseExpiresAt
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

    /// The plan that pays for the house: mine if it covers this house, otherwise the one in the
    /// house record.
    var currentPlan: PremiumPlan? {
        if isPaidByMe { return store.activePlan }
        return isHousePremium ? housePlan : nil
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

    // MARK: - Free trial

    /// How long a new house's free trial lasts.
    static let trialMonths = 2

    /// The record in the creator's private database (default zone) that says they already used
    /// the trial. It lives outside the house zone, so deleting the profile doesn't erase it.
    private static let trialMarkerID = CKRecord.ID(recordName: "premium-house-trial")
    private static let trialMarkerType = "PremiumTrialMarker"

    private var privateDatabase: CKDatabase { CloudKitManager.shared.privateDB }

    /// Starts the 2-month trial on a house the person just created, unless they already used
    /// it in another house. Best effort: if iCloud can't be read, no trial is started (it's
    /// never given twice by mistake).
    func startTrialIfEligible(for house: HouseModel) async {
        guard let houseID = house.recordID, house.premiumTrialEndsAt == nil else { return }

        do {
            _ = try await privateDatabase.record(for: Self.trialMarkerID)
            return   // already used
        } catch let error as CKError where error.code == .unknownItem {
            // Never used: go on.
        } catch {
            print("PremiumManager: couldn't check the trial mark. \(error)")
            return
        }

        guard let endsAt = Calendar.current.date(byAdding: .month, value: Self.trialMonths, to: .now) else { return }

        let marker = CKRecord(recordType: Self.trialMarkerType, recordID: Self.trialMarkerID)
        marker["houseRecordName"] = houseID.recordName
        marker["grantedAt"] = Date.now
        do {
            _ = try await privateDatabase.save(marker)
        } catch {
            print("PremiumManager: couldn't save the trial mark. \(error)")
            return
        }

        if await house.setTrial(endsAt: endsAt) {
            houseTrialEndsAt = endsAt
        }
    }

    /// The onboarding deleted the house it had just created (the person went back): gives the
    /// trial back, so the house they create next gets it.
    func trialHouseWasDiscarded(_ houseID: CKRecord.ID) async {
        guard let marker = try? await privateDatabase.record(for: Self.trialMarkerID),
              marker["houseRecordName"] as? String == houseID.recordName
        else { return }
        _ = try? await privateDatabase.deleteRecord(withID: Self.trialMarkerID)
        houseTrialEndsAt = nil
    }

    // MARK: - Leaving the house

    /// What the leave / delete-profile / switch-house confirmations add when this person pays
    /// for the house, or `nil` when they don't.
    var leaveWarning: String? {
        guard isPaidByMe, let plan = currentPlan else { return nil }
        if plan.isLifetime {
            return L10n.tr("Você paga o Premium desta casa. Seu Premium vitalício vai com você, mas esta casa volta ao plano grátis.")
        }
        return L10n.tr("Você paga o Premium desta casa. Ao sair, a casa volta ao plano grátis. A assinatura continua ativa na App Store: se não quiser mais ser cobrado, cancele em Perfil > Pipa Premium > Gerenciar assinatura antes de sair.")
    }

    /// Runs right before this person leaves `house` (leaving, deleting the profile or switching
    /// houses): if they pay for it, clears the house's Premium and tells the other members that
    /// the house is back on the free plan. Must run while the house can still be written to.
    func releaseHouseBeforeLeaving(_ house: HouseModel) async {
        guard let houseID = house.recordID,
              let me = await currentRecordName(),
              house.premiumOwnerRecordName == me
        else { return }

        houseBeingLeft = houseID.recordName
        let snapshot = await HouseDataStore.shared.current()
        let payerName = snapshot.houseUser?.name ?? snapshot.privateUser?.name ?? ""

        await NotificationManager.shared.notifyPremiumEnded(payerName: payerName, to: snapshot.users)
        _ = await house.setPremium(expiresAt: nil, ownerRecordName: nil, productID: nil)
        clearLocalHouseState()
    }

    /// Leaving failed: the person is still in the house, so their purchase applies again.
    func leavingFailed() async {
        houseBeingLeft = nil
        await entitlementsDidChange()
    }

    // MARK: - Syncing

    /// Reads the Premium fields from `house` and, if this person's purchase covers it, writes it
    /// into the house. Called every time the app fetches the house (``ContentViewModel``).
    func refresh(house: HouseModel?) async {
        houseExpiresAt = house?.premiumExpiresAt
        houseOwnerRecordName = house?.premiumOwnerRecordName
        housePlan = house?.premiumProductID.flatMap(PremiumPlan.init(productID:))
        houseTrialEndsAt = house?.premiumTrialEndsAt
        currentHouseToken = house?.recordID.map(Self.purchaseToken(for:))
        _ = await currentRecordName()
        guard let house, house.recordID?.recordName != houseBeingLeft else { return }
        if houseBeingLeft != nil { houseBeingLeft = nil }   // a different house: the leave is over
        await syncSubscription(into: house)
    }

    /// The purchase started, renewed, expired or was refunded.
    private func entitlementsDidChange() async {
        let house = try? await CloudKitManager.shared.currentHouse()
        await refresh(house: house)
    }

    /// Keeps the house record in line with who pays, writing only when something changed
    /// (every save notifies the other members' devices).
    private func syncSubscription(into house: HouseModel) async {
        guard store.hasLoadedEntitlements, let me = await currentRecordName() else { return }
        let houseDate = house.premiumExpiresAt
        let owner = house.premiumOwnerRecordName
        let isMine = owner == me

        if isPaidByMe, let myExpiration = store.entitlementEnd, let myPlan = store.activePlan {
            // Mine: keep the date and plan current (renewal, upgrade). Someone else's: take over
            // only if mine lasts longer (two members paid by mistake).
            let needsWrite = isMine
                ? !Self.sameMoment(houseDate, myExpiration) || house.premiumProductID != myPlan.productID
                : myExpiration > (houseDate ?? .distantPast) || owner.map(payerLeft) == true
            guard needsWrite else { return }
            if await house.setPremium(expiresAt: myExpiration, ownerRecordName: me, productID: myPlan.productID) {
                houseExpiresAt = myExpiration
                houseOwnerRecordName = me
                housePlan = myPlan
            }
        } else if houseDate != nil, let owner, isMine || payerLeft(owner) {
            // The record says Premium, but nobody pays for this house anymore: the period ended
            // after a cancellation, it was refunded, or the payer left without clearing it.
            if await house.setPremium(expiresAt: nil, ownerRecordName: nil, productID: nil) {
                clearLocalHouseState()
            }
        }
    }

    private func clearLocalHouseState() {
        houseExpiresAt = nil
        houseOwnerRecordName = nil
        housePlan = nil
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
