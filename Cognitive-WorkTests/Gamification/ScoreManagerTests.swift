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
        let other = UserModel(name: "bob", tier: .novatoDaCasa, points: 7, recordID: GamificationFixture.id("bob-house"), ownerRecordName: "bob-house")
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
}
