//
//  CoinPayoutTests.swift
//  Cognitive-WorkTests
//
//  Created by Jonas Melo on 16/10/26.
//

import Testing
import Foundation
import CloudKit
@testable import Cognitive_Work

@MainActor
struct CoinPayoutTests {

    // MARK: - Coin table

    @Test func higherRanksNeverPayLess() {
        let amounts = Tier.allCases.map(\.cycleCoins)
        #expect(amounts == amounts.sorted())
        #expect(amounts.allSatisfy { $0 > 0 })
        #expect(Tier.almaDaCasa.cycleCoins > Tier.novatoDaCasa.cycleCoins)
    }

    // MARK: - Settlement

    private let alice = GamificationFixture.id("alice-house")
    private let bob = GamificationFixture.id("bob-house")

    /// A member whose record, with `points`, is on the server (`store`).
    private func member(_ id: CKRecord.ID, points: Int, in store: InMemoryAtomicRecordStore) -> UserModel {
        store.seed(GamificationFixture.user(id, points: points))
        return UserModel(name: id.recordName, tier: Tier(points: points), points: points, recordID: id, ownerRecordName: id.recordName)
    }

    private var closedCycle: HouseCycleModel {
        GamificationFixture.cycle(start: GamificationFixture.day(2026, 10, 2))
    }

    private var afterCycle: Date { GamificationFixture.day(2026, 10, 17) }

    @Test func paysEachMemberByRankWhenCycleCloses() async {
        let store = InMemoryAtomicRecordStore()
        let service = CycleSettlementService(store: store)

        let created = await service.prepareClosedCycles(
            [closedCycle],
            members: [member(alice, points: 650, in: store), member(bob, points: 0, in: store)],
            houseID: GamificationFixture.houseID,
            today: afterCycle
        )

        #expect(created == 2)
        let alicePayouts = await service.payouts(for: alice, cycles: [closedCycle], today: afterCycle)
        #expect(alicePayouts.count == 1)
        #expect(alicePayouts.first?.tier == .escudeiroDaFaxina)
        #expect(alicePayouts.first?.amount == Tier.escudeiroDaFaxina.cycleCoins)
        #expect(alicePayouts.first?.status == .pending)

        let history = store.storedRecords(ofType: RankHistoryModel.recordType)
            .compactMap(RankHistoryModel.init(record:))
        #expect(history.count == 2)
        #expect(history.first { $0.user.recordID == alice }?.points == 650)
    }

    @Test func settlingResetsPointsAndRank() async {
        let store = InMemoryAtomicRecordStore()
        let service = CycleSettlementService(store: store)
        let local = member(alice, points: 650, in: store)

        await service.prepareClosedCycles([closedCycle], members: [local], houseID: GamificationFixture.houseID, today: afterCycle)

        #expect(GamificationFixture.points(of: alice, in: store) == 0)
        #expect(local.points == 0)
        #expect(local.tier == .novatoDaCasa)
    }

    @Test func historyKeepsTheRankBeforeTheReset() async {
        let store = InMemoryAtomicRecordStore()
        let service = CycleSettlementService(store: store)

        await service.prepareClosedCycles([closedCycle], members: [member(alice, points: 650, in: store)], houseID: GamificationFixture.houseID, today: afterCycle)

        let entry = store.storedRecords(ofType: RankHistoryModel.recordType)
            .compactMap(RankHistoryModel.init(record:)).first
        #expect(entry?.tier == .escudeiroDaFaxina)
        #expect(entry?.points == 650)
    }

    @Test func usesTheServerPointsNotTheLocalCopy() async {
        let store = InMemoryAtomicRecordStore()
        let service = CycleSettlementService(store: store)
        let stale = member(alice, points: 10, in: store)
        store.seed(GamificationFixture.score(for: alice, points: 650))

        await service.prepareClosedCycles([closedCycle], members: [stale], houseID: GamificationFixture.houseID, today: afterCycle)

        let payouts = await service.payouts(for: alice, cycles: [closedCycle], today: afterCycle)
        #expect(payouts.first?.tier == .escudeiroDaFaxina)
    }

    @Test func eachClosedCycleStartsFromTheReset() async {
        let store = InMemoryAtomicRecordStore()
        let service = CycleSettlementService(store: store)
        let laterCycle = GamificationFixture.cycle(start: GamificationFixture.day(2026, 10, 16))

        await service.prepareClosedCycles(
            [closedCycle, laterCycle],
            members: [member(alice, points: 650, in: store)],
            houseID: GamificationFixture.houseID,
            today: GamificationFixture.day(2026, 11, 5)
        )

        let history = store.storedRecords(ofType: RankHistoryModel.recordType)
            .compactMap(RankHistoryModel.init(record:))
            .sorted { $0.cycleKey < $1.cycleKey }
        #expect(history.map(\.points) == [650, 0])
    }

    @Test func preparingAgainDoesNotResetAgain() async {
        let store = InMemoryAtomicRecordStore()
        let service = CycleSettlementService(store: store)
        await service.prepareClosedCycles([closedCycle], members: [member(alice, points: 650, in: store)], houseID: GamificationFixture.houseID, today: afterCycle)

        // Points earned after the reset, in the next cycle.
        store.seed(GamificationFixture.score(for: alice, points: 40))
        let local = UserModel(name: "alice", tier: Tier(points: 40), points: 40, recordID: alice, ownerRecordName: "alice")
        await service.prepareClosedCycles([closedCycle], members: [local], houseID: GamificationFixture.houseID, today: afterCycle)

        #expect(GamificationFixture.points(of: alice, in: store) == 40)
    }

    @Test func settlingDoesNotTouchTheUserRecord() async {
        let store = InMemoryAtomicRecordStore()
        let service = CycleSettlementService(store: store)

        await service.prepareClosedCycles([closedCycle], members: [member(alice, points: 650, in: store)], houseID: GamificationFixture.houseID, today: afterCycle)

        // Only the score is reset; the user's record keeps its (legacy) value.
        #expect(store.stored(alice)?["points"] as? Int == 650)
        #expect(GamificationFixture.points(of: alice, in: store) == 0)
    }

    @Test func doesNotPayCycleThatIsStillRunning() async {
        let store = InMemoryAtomicRecordStore()
        let service = CycleSettlementService(store: store)

        let created = await service.prepareClosedCycles(
            [closedCycle],
            members: [member(alice, points: 650, in: store)],
            houseID: GamificationFixture.houseID,
            today: GamificationFixture.day(2026, 10, 16)
        )

        #expect(created == 0)
        #expect(store.storedRecords(ofType: CoinPayoutModel.recordType).isEmpty)
    }

    @Test func preparingTwiceCreatesNothingNew() async {
        let store = InMemoryAtomicRecordStore()
        let service = CycleSettlementService(store: store)
        let members = [member(alice, points: 650, in: store)]

        await service.prepareClosedCycles([closedCycle], members: members, houseID: GamificationFixture.houseID, today: afterCycle)
        let second = await service.prepareClosedCycles([closedCycle], members: members, houseID: GamificationFixture.houseID, today: afterCycle)

        #expect(second == 0)
        #expect(store.storedRecords(ofType: CoinPayoutModel.recordType).count == 1)
    }

    @Test func twoDevicesPreparingAtOnceCreateOnePayoutEach() async {
        let store = InMemoryAtomicRecordStore()
        let members = [member(alice, points: 650, in: store), member(bob, points: 10, in: store)]
        let deviceA = CycleSettlementService(store: store)
        let deviceB = CycleSettlementService(store: store)
        store.holdFetches(2)

        async let first = deviceA
            .prepareClosedCycles([closedCycle], members: members, houseID: GamificationFixture.houseID, today: afterCycle)
        async let second = deviceB
            .prepareClosedCycles([closedCycle], members: members, houseID: GamificationFixture.houseID, today: afterCycle)
        let total = await first + second

        #expect(total == 2)
        #expect(store.storedRecords(ofType: CoinPayoutModel.recordType).count == 2)
        #expect(store.storedRecords(ofType: RankHistoryModel.recordType).count == 2)
        #expect(GamificationFixture.points(of: alice, in: store) == 0)
    }

    @Test func confirmingCreditsWalletOnce() async throws {
        let store = InMemoryAtomicRecordStore()
        store.seed(GamificationFixture.wallet(for: alice, balance: 5))
        let service = CycleSettlementService(store: store)
        await service.prepareClosedCycles([closedCycle], members: [member(alice, points: 650, in: store)], houseID: GamificationFixture.houseID, today: afterCycle)
        let amount = Tier.escudeiroDaFaxina.cycleCoins

        let first = try await service.confirmPendingPayouts(for: alice, cycles: [closedCycle], houseID: GamificationFixture.houseID, legacyCoins: 0, today: afterCycle)
        let second = try await service.confirmPendingPayouts(for: alice, cycles: [closedCycle], houseID: GamificationFixture.houseID, legacyCoins: 0, today: afterCycle)

        #expect(first.credited == amount)
        #expect(second.credited == 0)
        #expect(GamificationFixture.balance(of: alice, in: store) == 5 + amount)
        let payouts = await service.payouts(for: alice, cycles: [closedCycle], today: afterCycle)
        #expect(payouts.first?.status == .confirmed)
    }

    @Test func concurrentConfirmationsCreditOnce() async throws {
        let store = InMemoryAtomicRecordStore()
        let service = CycleSettlementService(store: store)
        await service.prepareClosedCycles([closedCycle], members: [member(alice, points: 650, in: store)], houseID: GamificationFixture.houseID, today: afterCycle)
        let amount = Tier.escudeiroDaFaxina.cycleCoins

        store.holdFetches(2)
        async let first = service.confirmPendingPayouts(for: alice, cycles: [closedCycle], houseID: GamificationFixture.houseID, legacyCoins: 0, today: afterCycle)
        async let second = service.confirmPendingPayouts(for: alice, cycles: [closedCycle], houseID: GamificationFixture.houseID, legacyCoins: 0, today: afterCycle)
        let results = try await [first, second]

        #expect(results.map(\.credited).sorted() == [0, amount])
        #expect(GamificationFixture.balance(of: alice, in: store) == amount)
        #expect(store.conflictCount >= 1)
    }

    @Test func newWalletIsSeededWithLegacyCoins() async throws {
        let store = InMemoryAtomicRecordStore()
        let service = CycleSettlementService(store: store)
        await service.prepareClosedCycles([closedCycle], members: [member(alice, points: 0, in: store)], houseID: GamificationFixture.houseID, today: afterCycle)

        let result = try await service.confirmPendingPayouts(for: alice, cycles: [closedCycle], houseID: GamificationFixture.houseID, legacyCoins: 40, today: afterCycle)

        #expect(result.newBalance == 40 + Tier.novatoDaCasa.cycleCoins)
    }
}
