//
//  ScoreManagerTests.swift
//  Cognitive-WorkTests
//
//  Created by Jonas Melo on 19/10/26.
//

import Testing
import Foundation
import CloudKit
@testable import Cognitive_Work

@MainActor
struct ScoreManagerTests {

    private let alice = GamificationFixture.id("alice-house")

    /// A local copy of Alice with `points`, which may differ from the server.
    private func localAlice(points: Int) -> UserModel {
        UserModel(name: "alice", tier: Tier(points: points), points: points, recordID: alice, ownerRecordName: "alice")
    }

    @Test func addsToTheServerValue() async {
        let store = InMemoryAtomicRecordStore()
        store.seed(GamificationFixture.user(alice, points: 30))
        let manager = ScoreManager(store: store)
        let local = localAlice(points: 30)

        let success = await manager.assignScore(score: 15, for: local)

        #expect(success)
        #expect(GamificationFixture.points(of: alice, in: store) == 45)
        #expect(local.points == 45)
        #expect(local.tier == Tier(points: 45))
    }

    @Test func staleCopyDoesNotUndoTheReset() async {
        let store = InMemoryAtomicRecordStore()
        // The cycle was settled on another device: the score holds 0.
        store.seed(GamificationFixture.user(alice, points: 75))
        store.seed(GamificationFixture.score(for: alice, points: 0))
        let manager = ScoreManager(store: store)
        // This device still has the points from before the reset.
        let stale = localAlice(points: 75)

        await manager.assignScore(score: 15, for: stale)

        #expect(GamificationFixture.points(of: alice, in: store) == 15)
        #expect(stale.points == 15)
    }

    @Test func concurrentChangesBothCount() async {
        let store = InMemoryAtomicRecordStore()
        store.seed(GamificationFixture.user(alice, points: 0))
        let deviceA = ScoreManager(store: store)
        let deviceB = ScoreManager(store: store)
        store.holdFetches(2)

        async let first = deviceA.assignScore(score: 10, for: localAlice(points: 0))
        async let second = deviceB.assignScore(score: 20, for: localAlice(points: 0))
        let results = await [first, second]

        #expect(results == [true, true])
        #expect(GamificationFixture.points(of: alice, in: store) == 30)
        #expect(store.conflictCount >= 1)
    }

    @Test func neverGoesBelowZero() async {
        let store = InMemoryAtomicRecordStore()
        store.seed(GamificationFixture.user(alice, points: 5))
        let manager = ScoreManager(store: store)

        await manager.removeScore(score: 20, for: localAlice(points: 5))

        #expect(GamificationFixture.points(of: alice, in: store) == 0)
    }

    @Test func firstChangeCreatesTheScoreFromLegacyPoints() async {
        let store = InMemoryAtomicRecordStore()
        store.seed(GamificationFixture.user(alice, points: 30))
        let manager = ScoreManager(store: store)

        #expect(GamificationFixture.points(of: alice, in: store) == nil)
        await manager.assignScore(score: 5, for: localAlice(points: 30))

        #expect(GamificationFixture.points(of: alice, in: store) == 35)
        // The user's record is never written.
        #expect(store.stored(alice)?["points"] as? Int == 30)
    }

    @Test func userRecordNoLongerStoresPoints() {
        let user = localAlice(points: 90)
        let record = CKRecord(recordType: UserModel.recordType, recordID: alice)

        user.populate(record: record)

        #expect(record["points"] == nil)
        #expect(record["tier"] == nil)
    }

    @Test func scoresAreCopiedOntoUsers() {
        let user = localAlice(points: 0)
        let other = UserModel(name: "bob", tier: .tradicionalI, points: 7, recordID: GamificationFixture.id("bob-house"), ownerRecordName: "bob-house")
        var score = UserScoreModel(ownerRecordName: "alice-house", points: 80)
        score.recordID = GamificationFixture.scoreID(of: alice)

        UserScoreModel.apply([score], to: [user, other])

        #expect(user.points == 80)
        #expect(user.tier == Tier(points: 80))
        // No score yet: keeps the legacy points.
        #expect(other.points == 7)
    }

    @Test func failsWithoutAServerRecord() async {
        let manager = ScoreManager(store: InMemoryAtomicRecordStore())
        let local = localAlice(points: 10)

        let success = await manager.assignScore(score: 5, for: local)

        #expect(!success)
        #expect(local.points == 10)
    }

    // MARK: - Coins along the way

    /// Alice as a member of the house, so her wallet can be created.
    private func houseAlice(points: Int = 0) -> UserModel {
        UserModel(
            name: "alice", tier: Tier(points: points), points: points,
            house: CKRecord.Reference(recordID: GamificationFixture.houseID, action: .none),
            recordID: alice, ownerRecordName: "alice"
        )
    }

    @Test func pointsPayTheirCoinsRightAway() async {
        let store = InMemoryAtomicRecordStore()
        store.seed(GamificationFixture.user(alice))
        store.seed(GamificationFixture.wallet(for: alice, balance: 0))
        let manager = ScoreManager(store: store)

        await manager.assignScore(score: 37, for: houseAlice())

        #expect(GamificationFixture.balance(of: alice, in: store) == ScoreValues.coins(forPoints: 37))
    }

    @Test func coinsFollowThePointsWithinARank() async {
        let store = InMemoryAtomicRecordStore()
        store.seed(GamificationFixture.user(alice))
        store.seed(GamificationFixture.wallet(for: alice, balance: 0))
        let manager = ScoreManager(store: store)
        let local = houseAlice()
        let step = ScoreValues.pointsPerCoin

        // Still the first rank, and the coins already come in.
        await manager.assignScore(score: step, for: local)
        #expect(Tier(points: step) == .tradicionalI)
        #expect(GamificationFixture.balance(of: alice, in: store) == 1)

        // Points that don't add up to a coin yet pay nothing more, until they do.
        await manager.assignScore(score: step - 1, for: local)
        #expect(GamificationFixture.balance(of: alice, in: store) == 1)
        await manager.assignScore(score: 1, for: local)
        #expect(GamificationFixture.balance(of: alice, in: store) == 2)
    }

    @Test func removingPointsTakesTheirCoinsBack() async {
        let store = InMemoryAtomicRecordStore()
        store.seed(GamificationFixture.user(alice))
        store.seed(GamificationFixture.wallet(for: alice, balance: 10))
        let manager = ScoreManager(store: store)
        let local = houseAlice()

        await manager.assignScore(score: Tier.tradicionalIII.minimumPoints, for: local)
        await manager.removeScore(score: Tier.tradicionalIII.minimumPoints, for: local)

        #expect(GamificationFixture.balance(of: alice, in: store) == 10)
    }

    @Test func spentCoinsCantBePaidTwice() async {
        let store = InMemoryAtomicRecordStore()
        store.seed(GamificationFixture.user(alice))
        store.seed(GamificationFixture.wallet(for: alice, balance: 0))
        let manager = ScoreManager(store: store)
        let local = houseAlice()
        let rank = Tier.tradicionalIII

        await manager.assignScore(score: rank.minimumPoints, for: local)
        // The coins are spent (a coupon) before the points are undone.
        store.seed(GamificationFixture.wallet(for: alice, balance: 0))
        await manager.removeScore(score: rank.minimumPoints, for: local)
        await manager.assignScore(score: rank.minimumPoints, for: local)

        // Going back up doesn't pay again what couldn't be taken back.
        #expect(GamificationFixture.balance(of: alice, in: store) == 0)
    }

    // MARK: - Points for completing a chore

    /// A low-priority, 5-minute chore.
    private func chore(_ frequency: Recurrence) -> ChoreModel {
        ChoreModel(name: "chore", description: "", frequency: frequency, duration: 5, isPublic: true, priorityTag: .low)
    }

    /// What `chore` is worth done on time.
    private func onTime(_ chore: ChoreModel) -> Int {
        ScoreValues.choreCompletion(minutes: chore.duration, priority: chore.priorityTag)
    }

    private func day(_ offset: Int, from date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: date)!
    }

    @Test func choreDoneOnTimeOrLateIsWorthItsFullEffort() {
        let manager = ScoreManager(store: InMemoryAtomicRecordStore())
        let daily = chore(.daily)
        let today = Date.now

        #expect(manager.points(forCompleting: daily, dueOn: nil, completedAt: today) == onTime(daily))
        #expect(manager.points(forCompleting: daily, dueOn: today, completedAt: today) == onTime(daily))
        #expect(manager.points(forCompleting: daily, dueOn: day(-3, from: today), completedAt: today) == onTime(daily))
    }

    @Test func checkingOffNextDaysOfADailyChoreIsWorthLittle() {
        let manager = ScoreManager(store: InMemoryAtomicRecordStore())
        let daily = chore(.daily)
        let today = Date.now

        #expect(manager.points(forCompleting: daily, dueOn: day(1, from: today), completedAt: today) == onTime(daily) >> 1)
        #expect(manager.points(forCompleting: daily, dueOn: day(13, from: today), completedAt: today) == 0)
    }

    @Test func weeklyChoreCanBeDoneAnyDayOfItsWeek() {
        let manager = ScoreManager(store: InMemoryAtomicRecordStore())
        let weekly = chore(.weekly)
        let today = Date.now

        #expect(manager.points(forCompleting: weekly, dueOn: day(6, from: today), completedAt: today) == onTime(weekly))
        #expect(manager.points(forCompleting: weekly, dueOn: day(7, from: today), completedAt: today) == onTime(weekly) >> 1)
    }

    // MARK: - Balance

    @Test func completionFollowsEffort() {
        // About a point per minute, on top of a fixed base.
        #expect(ScoreValues.choreCompletion(minutes: 30, priority: .low) == ScoreValues.choreCompletionBase + 30)
        // A long chore is worth more than a short urgent one.
        #expect(ScoreValues.choreCompletion(minutes: 60, priority: .low) > ScoreValues.choreCompletion(minutes: 10, priority: .urgent))
        // Priority adds, but never as much as the effort itself.
        #expect(ScoreValues.choreCompletion(minutes: 30, priority: .urgent) > ScoreValues.choreCompletion(minutes: 30, priority: .low))
        // The duration that counts is capped.
        #expect(ScoreValues.choreCompletion(minutes: 999, priority: .low) == ScoreValues.choreCompletion(minutes: ScoreValues.maximumChoreMinutes, priority: .low))
    }

    @Test func planningIsWorthLessThanTheShortestChore() {
        let shortest = ScoreValues.choreCompletion(minutes: 5, priority: .low)

        #expect(ScoreValues.choreCreation(hasFullDetails: true) < shortest)
        #expect(ScoreValues.choreCreation(hasFullDetails: false) < ScoreValues.choreCreation(hasFullDetails: true))
        #expect(ScoreValues.shoppingItemAdded.points < shortest)
        #expect(ScoreValues.shoppingPurchase(hasPrice: true) == ScoreValues.shoppingPurchase(hasPrice: false) + 1)
    }

    @Test func creationBonusesCantClimbTheLadderAlone() {
        // A whole cycle of creating chores up to the daily limit stays far from the top.
        let days = 14
        let perDay = ScoreValues.dailyChoreCreationBonusLimit * ScoreValues.choreCreation(hasFullDetails: true)
        #expect(days * perDay < Tier.topThreshold / 4)
    }
}
