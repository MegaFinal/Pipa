//
//  CouponPurchaseConcurrencyTests.swift
//  Cognitive-WorkTests
//
//  Created by Jonas Melo on 16/10/26.
//

import Testing
import Foundation
import CloudKit
@testable import Cognitive_Work

/// Coupon exclusivity under real concurrency: ``InMemoryAtomicRecordStore/holdFetches(_:)``
/// makes every competing purchase read the same versions before any of them saves.
@MainActor
struct CouponPurchaseConcurrencyTests {

    typealias F = GamificationFixture
    typealias PurchaseError = CouponPurchaseService.PurchaseError

    let cycleKey = "2026-10-02"
    let kitchen = F.id("kitchen")
    let bathroom = F.id("bathroom")

    /// Daily, 15 min → 26 coins with the bundled pricing.
    let dishes = F.id("dishes")
    let stove = F.id("stove")
    let shower = F.id("shower")

    let dishesCoupon = F.id("coupon-dishes")
    let stoveCoupon = F.id("coupon-stove")
    let showerCoupon = F.id("coupon-shower")

    var price: Int { CouponPricing.current.price(frequency: .daily, durationMinutes: 15) }

    func makeStore(wallets: [CKRecord.ID: Int]) -> InMemoryAtomicRecordStore {
        let store = InMemoryAtomicRecordStore()
        store.seed(F.chore("dishes", room: kitchen))
        store.seed(F.chore("stove", room: kitchen))
        store.seed(F.chore("shower", room: bathroom))
        store.seed(F.coupon("coupon-dishes", chore: dishes))
        store.seed(F.coupon("coupon-stove", chore: stove))
        store.seed(F.coupon("coupon-shower", chore: shower))
        for (user, balance) in wallets {
            store.seed(F.wallet(for: user, balance: balance))
        }
        return store
    }

    func buy(_ coupon: CKRecord.ID, by buyer: CKRecord.ID, in store: InMemoryAtomicRecordStore,
             cycle: String? = nil) async -> Result<CouponPurchaseService.Receipt, PurchaseError> {
        do {
            let receipt = try await CouponPurchaseService(store: store).purchase(
                couponID: coupon, buyerID: buyer, houseID: F.houseID, cycleKey: cycle ?? cycleKey
            )
            return .success(receipt)
        } catch let error as PurchaseError {
            return .failure(error)
        } catch {
            Issue.record("Unexpected error \(error)")
            return .failure(.tooManyConflicts)
        }
    }

    func holder(of coupon: CKRecord.ID, in store: InMemoryAtomicRecordStore) -> CKRecord.ID? {
        store.stored(coupon).flatMap(CouponModel.init(record:))?.currentUser?.recordID
    }

    // MARK: - Single purchase

    @Test func purchaseDebitsWalletAndAssignsCoupon() async throws {
        let ana = F.id("ana")
        let store = makeStore(wallets: [ana: 100])

        let result = await buy(dishesCoupon, by: ana, in: store)

        #expect(try result.get() == .init(price: price, newBalance: 100 - price))
        #expect(F.balance(of: ana, in: store) == 100 - price)
        #expect(holder(of: dishesCoupon, in: store) == ana)
        let hold = store.stored(CouponHoldModel.recordID(userID: ana, roomID: kitchen)).flatMap(CouponHoldModel.init(record:))
        #expect(hold?.cycleKey == cycleKey)
    }

    @Test func cannotBuyWithoutEnoughCoins() async {
        let ana = F.id("ana")
        let store = makeStore(wallets: [ana: price - 1])

        let result = await buy(dishesCoupon, by: ana, in: store)

        #expect(result == .failure(.insufficientCoins(balance: price - 1, price: price)))
        #expect(F.balance(of: ana, in: store) == price - 1)
        #expect(holder(of: dishesCoupon, in: store) == nil)
    }

    @Test func cannotBuyBeforeAnyCycleExists() async {
        let ana = F.id("ana")
        let store = makeStore(wallets: [ana: 100])
        do {
            _ = try await CouponPurchaseService(store: store).purchase(
                couponID: dishesCoupon, buyerID: ana, houseID: F.houseID, cycleKey: nil
            )
            Issue.record("Purchase should fail without a cycle")
        } catch {
            #expect(error as? PurchaseError == .noActiveCycle)
        }
    }

    // MARK: - One holder per coupon

    @Test func twoPeopleBuyingTheSameCouponAtOnceOnlyOneGetsIt() async {
        let ana = F.id("ana"), bia = F.id("bia")
        let store = makeStore(wallets: [ana: 100, bia: 100])
        store.holdFetches(2)

        async let first = buy(dishesCoupon, by: ana, in: store)
        async let second = buy(dishesCoupon, by: bia, in: store)
        let results = await [first, second]

        let winners = results.filter { if case .success = $0 { return true } else { return false } }
        #expect(winners.count == 1)
        #expect(results.contains(.failure(.alreadyTaken)))
        #expect(store.conflictCount >= 1)

        // Only the winner paid.
        let winner = holder(of: dishesCoupon, in: store)
        let loser = winner == ana ? bia : ana
        #expect(winner != nil)
        #expect(F.balance(of: winner!, in: store) == 100 - price)
        #expect(F.balance(of: loser, in: store) == 100)
    }

    @Test func manyBuyersAtOnceExactlyOneWins() async {
        let buyers = (0..<20).map { F.id("buyer-\($0)") }
        let store = makeStore(wallets: Dictionary(uniqueKeysWithValues: buyers.map { ($0, 100) }))
        store.holdFetches(buyers.count)

        let results = await withTaskGroup(of: Result<CouponPurchaseService.Receipt, PurchaseError>.self) { group in
            for buyer in buyers {
                group.addTask { @MainActor in await self.buy(self.dishesCoupon, by: buyer, in: store) }
            }
            var all: [Result<CouponPurchaseService.Receipt, PurchaseError>] = []
            for await result in group { all.append(result) }
            return all
        }

        #expect(results.filter { (try? $0.get()) != nil }.count == 1)
        #expect(results.filter { $0 == .failure(.alreadyTaken) }.count == buyers.count - 1)
        let totalSpent = buyers.reduce(0) { $0 + (100 - (F.balance(of: $1, in: store) ?? 100)) }
        #expect(totalSpent == price)
    }

    // MARK: - Balance never negative

    @Test func concurrentPurchasesCannotOverdrawTheWallet() async {
        let ana = F.id("ana")
        // Enough for one coupon, not two.
        let store = makeStore(wallets: [ana: price + 4])
        store.holdFetches(2)

        async let first = buy(dishesCoupon, by: ana, in: store)
        async let second = buy(showerCoupon, by: ana, in: store)
        let results = await [first, second]

        #expect(results.filter { (try? $0.get()) != nil }.count == 1)
        #expect(results.contains(.failure(.insufficientCoins(balance: 4, price: price))))
        #expect(F.balance(of: ana, in: store) == 4)
    }

    // MARK: - One coupon per room

    @Test func cannotHoldTwoCouponsOfTheSameRoom() async {
        let ana = F.id("ana")
        let store = makeStore(wallets: [ana: 500])

        _ = await buy(dishesCoupon, by: ana, in: store)
        let second = await buy(stoveCoupon, by: ana, in: store)
        let otherRoom = await buy(showerCoupon, by: ana, in: store)

        #expect(second == .failure(.roomLimitReached))
        #expect((try? otherRoom.get()) != nil)
    }

    @Test func concurrentPurchasesInTheSameRoomOnlyOneSucceeds() async {
        let ana = F.id("ana")
        let store = makeStore(wallets: [ana: 500])
        store.holdFetches(2)

        async let first = buy(dishesCoupon, by: ana, in: store)
        async let second = buy(stoveCoupon, by: ana, in: store)
        let results = await [first, second]

        #expect(results.filter { (try? $0.get()) != nil }.count == 1)
        #expect(results.contains(.failure(.roomLimitReached)))
        #expect(F.balance(of: ana, in: store) == 500 - price)
        let holders = [holder(of: dishesCoupon, in: store), holder(of: stoveCoupon, in: store)].compactMap { $0 }
        #expect(holders == [ana])
    }

    // MARK: - Next cycle

    @Test func couponAndRoomFreeUpInTheNextCycle() async {
        let ana = F.id("ana"), bia = F.id("bia")
        let store = makeStore(wallets: [ana: 500, bia: 500])
        _ = await buy(dishesCoupon, by: ana, in: store)

        let nextCycle = "2026-10-17"
        let biaBuysIt = await buy(dishesCoupon, by: bia, in: store, cycle: nextCycle)
        let anaBuysAnotherInKitchen = await buy(stoveCoupon, by: ana, in: store, cycle: nextCycle)

        #expect((try? biaBuysIt.get()) != nil)
        #expect((try? anaBuysAnotherInKitchen.get()) != nil)
        let coupon = store.stored(dishesCoupon).flatMap(CouponModel.init(record:))
        #expect(coupon?.currentUser?.recordID == bia)
        #expect(coupon?.lastUser?.recordID == ana)
    }

    // MARK: - Exemption from the chore

    @Test func holderIsSparedTheChoreInTheNextDivision() {
        let ana = F.id("ana")
        var coupon = CouponModel(name: "dishes", isOnSale: true, price: 26, tier: .novatoDaCasa,
                                 currentUser: CKRecord.Reference(recordID: ana, action: .none),
                                 task: CKRecord.Reference(recordID: dishes, action: .none))
        coupon.purchasedCycleKey = "2026-10-02"
        let bought = F.cycle(start: F.day(2026, 10, 2))
        let next = F.cycle(start: F.day(2026, 10, 17))

        // Generating the division after the purchase cycle: Ana is left out…
        #expect(CouponExemption.forNextDivision(coupons: [coupon], cycles: [bought], newCycleKey: next.key)[dishes] == [ana])
        // …and that division uses the coupon.
        coupon.consumedCycleKey = next.key
        // While it runs, she still may not pick the chore…
        #expect(CouponExemption.active(coupons: [coupon], cycles: [bought, next])[dishes] == [ana])
        // …the coupon can be bought again…
        #expect(coupon.isAvailable(latestCycleKey: next.key))
        #expect(!coupon.isHeld(by: ana, inCycle: "2026-10-02"))
        // …and the division after it no longer spares her.
        #expect(CouponExemption.forNextDivision(coupons: [coupon], cycles: [bought, next], newCycleKey: "2026-10-31")[dishes] == nil)
    }

    /// Generating the division again on the day the latest one was generated rewrites the same
    /// cycle (same key): the coupon is used all the same, and stays applied to the replacement.
    @Test func couponIsUsedWhenTheDivisionIsGeneratedAgainTheSameDay() {
        let ana = F.id("ana")
        let latest = F.cycle(start: F.day(2026, 10, 21))
        var coupon = CouponModel(name: "dishes", isOnSale: true, price: 26, tier: .novatoDaCasa,
                                 currentUser: CKRecord.Reference(recordID: ana, action: .none),
                                 task: CKRecord.Reference(recordID: dishes, action: .none))
        coupon.purchasedCycleKey = latest.key

        #expect(CouponExemption.forNextDivision(coupons: [coupon], cycles: [latest], newCycleKey: latest.key)[dishes] == [ana])
        coupon.consumedCycleKey = latest.key

        // Used: free to buy again although the cycle didn't change.
        #expect(coupon.isAvailable(latestCycleKey: latest.key))
        #expect(!coupon.isHeld(by: ana, inCycle: latest.key))
        // Generated once more the same day: still applied, not lost.
        #expect(CouponExemption.forNextDivision(coupons: [coupon], cycles: [latest], newCycleKey: latest.key)[dishes] == [ana])
        #expect(CouponExemption.active(coupons: [coupon], cycles: [latest])[dishes] == [ana])
        // A later division doesn't apply it again.
        let later = F.cycle(start: F.day(2026, 11, 4))
        #expect(CouponExemption.forNextDivision(coupons: [coupon], cycles: [latest], newCycleKey: later.key)[dishes] == nil)
    }

    @Test func usedCouponAndItsRoomCanBeBoughtAgainInTheSameCycle() async {
        let ana = F.id("ana"), bia = F.id("bia")
        let store = makeStore(wallets: [ana: 500, bia: 500])
        _ = await buy(dishesCoupon, by: ana, in: store)

        let bought = store.stored(dishesCoupon).flatMap(CouponModel.init(record:))
        await CouponExemption.consume([bought].compactMap { $0 }, inCycle: cycleKey, store: store)
        #expect(store.stored(dishesCoupon).flatMap(CouponModel.init(record:))?.consumedCycleKey == cycleKey)

        // Ana's kitchen hold no longer counts, and the coupon itself is free.
        let anaBuysStove = await buy(stoveCoupon, by: ana, in: store)
        let biaBuysDishes = await buy(dishesCoupon, by: bia, in: store)

        #expect((try? anaBuysStove.get()) != nil)
        #expect((try? biaBuysDishes.get()) != nil)
        let coupon = store.stored(dishesCoupon).flatMap(CouponModel.init(record:))
        #expect(coupon?.currentUser?.recordID == bia)
        #expect(coupon?.consumedCycleKey == nil)
    }

    @Test func consumingLeavesANewPurchaseAlone() async {
        let ana = F.id("ana"), bia = F.id("bia")
        let store = makeStore(wallets: [ana: 500, bia: 500])
        _ = await buy(dishesCoupon, by: ana, in: store)
        let anasPurchase = store.stored(dishesCoupon).flatMap(CouponModel.init(record:))

        // Bia bought it in the next cycle before the division marked Ana's purchase as used.
        _ = await buy(dishesCoupon, by: bia, in: store, cycle: "2026-10-17")
        await CouponExemption.consume([anasPurchase].compactMap { $0 }, inCycle: "2026-10-17", store: store)

        let coupon = store.stored(dishesCoupon).flatMap(CouponModel.init(record:))
        #expect(coupon?.currentUser?.recordID == bia)
        #expect(coupon?.consumedCycleKey == nil)
    }
}
