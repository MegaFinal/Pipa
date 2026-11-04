//
//  GamificationSchemaSeedTests.swift
//  Cognitive-WorkTests
//
//  Created by Jonas Melo on 16/10/26.
//

import Testing
import Foundation
import CloudKit
@testable import Cognitive_Work

/// Saves one record of each gamification record type to the CloudKit **development** database,
/// with every field filled in, so CloudKit creates the record types and their fields.
///
/// After running it, in the CloudKit Console (Schema → Indexes) add `recordName` as
/// **Queryable** for `HouseCycleModel` and `RankHistoryModel` (both are read with queries).
/// `CoinWalletModel`, `CoinPayoutModel` and `CouponHoldModel` are only read by ID and need no index.
/// `UserScoreModel` is read both ways (by ID, and with a query when the house data loads), so it
/// needs `recordName` **Queryable** too.
/// Then deploy the schema to production.
///
/// The records are deleted at the end; the schema stays.
@MainActor
@Suite(.serialized)
struct GamificationSchemaSeedTests {

    private var zone: CKRecordZone.ID { CloudKitManager.shared.houseZoneID }

    private func placeholder(_ name: String) -> CKRecord.Reference {
        CKRecord.Reference(recordID: CKRecord.ID(recordName: "schema-seed-\(name)", zoneID: zone), action: .none)
    }

    /// Creates `item`, checks it was saved, then deletes it.
    private func seed<T: CloudKitSyncable>(_ item: T) async {
        await CloudKitManager.shared.createZoneIfNeeded()
        let saved = await CloudKitManager.shared.create(item)
        print("\(T.recordType) error:", CloudKitManager.shared.errorMessage as Any)
        #expect(saved != nil, "\(T.recordType) was not saved")
        if let saved {
            await CloudKitManager.shared.delete(saved)
        }
    }

    @Test func seedHouseCycleModel() async {
        let start = Calendar.current.startOfDay(for: .now)
        await seed(HouseCycleModel(startDate: start, endDate: start.addingTimeInterval(14 * 86_400)))
    }

    @Test func seedUserScoreModel() async {
        await seed(UserScoreModel(ownerRecordName: "schema-seed-owner", points: 10))
    }

    @Test func seedCoinWalletModel() async {
        await seed(CoinWalletModel(user: placeholder("user"), balance: 10))
    }

    @Test func seedCoinPayoutModel() async {
        await seed(CoinPayoutModel(
            user: placeholder("user"),
            cycleKey: "2026-01-01",
            tier: .protetorDoLar,
            points: 1500,
            amount: 34,
            status: .confirmed,
            confirmedAt: .now
        ))
    }

    @Test func seedRankHistoryModel() async {
        await seed(RankHistoryModel(
            user: placeholder("user"),
            cycleKey: "2026-01-01",
            cycleStart: .now,
            cycleEnd: .now,
            tier: .protetorDoLar,
            points: 1500
        ))
    }

    @Test func seedCouponHoldModel() async {
        await seed(CouponHoldModel(
            user: placeholder("user"),
            room: placeholder("room"),
            coupon: placeholder("coupon"),
            cycleKey: "2026-01-01"
        ))
    }

    /// Adds the `purchasedCycleKey` and `consumedCycleKey` fields to the existing `CouponModel` type.
    @Test func seedCouponModelPurchasedCycleKey() async {
        var coupon = CouponModel(
            name: "schema-seed-coupon",
            isOnSale: true,
            price: 1,
            tier: .novatoDaCasa,
            currentUser: placeholder("user"),
            lastUser: placeholder("user"),
            task: placeholder("chore")
        )
        coupon.purchasedCycleKey = "2026-01-01"
        coupon.consumedCycleKey = "2026-01-01"
        await seed(coupon)
    }
}
