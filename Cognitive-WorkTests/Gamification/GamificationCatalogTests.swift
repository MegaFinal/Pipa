//
//  GamificationCatalogTests.swift
//  Cognitive-WorkTests
//
//  Created by Jonas Melo on 27/10/26.
//

import Testing
import Foundation
import CloudKit
@testable import Cognitive_Work

@MainActor
struct GamificationCatalogTests {

    let zone = CKRecordZone.ID(zoneName: "house", ownerName: CKCurrentUserDefaultName)
    let cycle = "2026-10-20"

    private func id(_ name: String) -> CKRecord.ID { CKRecord.ID(recordName: name, zoneID: zone) }

    private func ref(_ name: String) -> CKRecord.Reference {
        CKRecord.Reference(recordID: id(name), action: .none)
    }

    private func room(_ name: String, symbol: String, color: RoomColor) -> RoomModel {
        var room = RoomModel(name: name, symbol: symbol, color: color)
        room.recordID = id("room-\(name)")
        return room
    }

    private func chore(_ name: String, in room: RoomModel) -> ChoreModel {
        var chore = ChoreModel(
            name: name, description: "", frequency: .weekly, duration: 900,
            isPublic: true, priorityTag: .undefined,
            roomReference: room.recordID.map { CKRecord.Reference(recordID: $0, action: .none) }
        )
        chore.recordID = id("chore-\(name)")
        return chore
    }

    private func coupon(
        for chore: ChoreModel, tier: Tier, onSale: Bool = true,
        holder: String? = nil, boughtIn: String? = nil, consumed: String? = nil
    ) -> CouponModel {
        var coupon = CouponModel(
            name: chore.name, isOnSale: onSale, price: 10, tier: tier,
            currentUser: holder.map(ref),
            task: chore.recordID.map { CKRecord.Reference(recordID: $0, action: .deleteSelf) }
        )
        coupon.recordID = id("coupon-\(chore.name)")
        coupon.purchasedCycleKey = boughtIn
        coupon.consumedCycleKey = consumed
        return coupon
    }

    private func user(_ name: String, points: Int) -> UserModel {
        let user = UserModel(name: name, tier: Tier(points: points), points: points, ownerRecordName: name)
        user.recordID = id("user-\(name)")
        return user
    }

    @Test func couponsTakeNameColorSymbolAndTierFromTheirRoomAndChore() {
        let kitchen = room("Cozinha", symbol: "fork.knife", color: .orange)
        let dishes = chore("Louça", in: kitchen)
        let catalog = GamificationCatalog(
            coupons: [coupon(for: dishes, tier: .vigiaDaCozinha)],
            chores: [dishes], rooms: [kitchen], users: [], myUserID: nil, latestCycleKey: cycle
        )

        let entry = try! #require(catalog.entries.first)
        #expect(entry.name == "Louça")
        #expect(entry.symbol == "fork.knife")
        #expect(entry.color == .orange)
        #expect(entry.tier == .vigiaDaCozinha)
        #expect(entry.roomName == "Cozinha")
    }

    @Test func splitsAvailableAndMine() {
        let kitchen = room("Cozinha", symbol: "fork.knife", color: .orange)
        let a = chore("A", in: kitchen), b = chore("B", in: kitchen), c = chore("C", in: kitchen)
        let me = user("me", points: 0), other = user("other", points: 0)

        let catalog = GamificationCatalog(
            coupons: [
                coupon(for: a, tier: .novatoDaCasa),
                coupon(for: b, tier: .novatoDaCasa, holder: "user-me", boughtIn: cycle),
                coupon(for: c, tier: .novatoDaCasa, holder: "user-other", boughtIn: cycle)
            ],
            chores: [a, b, c], rooms: [kitchen], users: [me, other],
            myUserID: me.recordID, latestCycleKey: cycle
        )

        #expect(catalog.entries.count == 3)
        #expect(catalog.availableCoupons.map(\.name) == ["A"])
        #expect(catalog.myCoupons.map(\.name) == ["B"])
    }

    @Test func aUsedCouponIsAvailableAgain() {
        let kitchen = room("Cozinha", symbol: "fork.knife", color: .orange)
        let a = chore("A", in: kitchen)
        let me = user("me", points: 0)

        let catalog = GamificationCatalog(
            coupons: [coupon(for: a, tier: .novatoDaCasa, holder: "user-me", boughtIn: cycle, consumed: cycle)],
            chores: [a], rooms: [kitchen], users: [me], myUserID: me.recordID, latestCycleKey: cycle
        )

        #expect(catalog.myCoupons.isEmpty)
        #expect(catalog.availableCoupons.count == 1)
    }

    @Test func ignoresCouponsNotOnSaleOrWithoutRoom() {
        let kitchen = room("Cozinha", symbol: "fork.knife", color: .orange)
        let a = chore("A", in: kitchen)
        let orphan = chore("Orfã", in: room("Fantasma", symbol: "house", color: .blue))

        let catalog = GamificationCatalog(
            coupons: [coupon(for: a, tier: .novatoDaCasa, onSale: false), coupon(for: orphan, tier: .novatoDaCasa)],
            chores: [a, orphan], rooms: [kitchen], users: [], myUserID: nil, latestCycleKey: cycle
        )

        #expect(catalog.entries.isEmpty)
    }

    @Test func listsEveryTierWithItsUsersHighestPointsFirst() {
        let ana = user("ana", points: 30), bia = user("bia", points: 40), caio = user("caio", points: 0)

        let catalog = GamificationCatalog(
            coupons: [], chores: [], rooms: [], users: [ana, bia, caio], myUserID: nil, latestCycleKey: nil
        )

        #expect(catalog.tiers.map(\.tier) == Tier.allCases)
        #expect(catalog.users(in: .novatoDaCasa).map(\.name) == ["caio"])
        #expect(catalog.users(in: .aprendiz).map(\.name) == ["bia", "ana"])
        #expect(catalog.users(in: .almaDaCasa).isEmpty)
    }
}
