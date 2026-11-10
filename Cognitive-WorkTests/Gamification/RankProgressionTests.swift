//
//  RankProgressionTests.swift
//  Cognitive-WorkTests
//
//  Created by Jonas Melo on 16/10/26.
//

import Testing
import Foundation
@testable import Cognitive_Work

@MainActor
struct RankProgressionTests {

    @Test func startsAtNovatoDaCasa() {
        #expect(Tier(points: 0) == .tradicionalI)
        #expect(Tier(points: -50) == .tradicionalI)
    }

    @Test func climbsAtEachThreshold() {
        #expect(Tier(points: Tier.tradicionalII.minimumPoints - 1) == .tradicionalI)
        #expect(Tier(points: Tier.tradicionalII.minimumPoints) == .tradicionalII)
        #expect(Tier(points: Tier.tradicionalIII.minimumPoints - 1) == .tradicionalII)
        #expect(Tier(points: Tier.tradicionalIII.minimumPoints) == .tradicionalIII)
    }

    @Test func stepsGrowUpTheLadder() {
        let thresholds = Tier.thresholds
        #expect(thresholds.count == Tier.allCases.count)
        #expect(thresholds.first == 0)
        for index in 2..<thresholds.count {
            let previousStep = thresholds[index - 1] - thresholds[index - 2]
            let step = thresholds[index] - thresholds[index - 1]
            #expect(step >= previousStep)
        }
    }

    @Test func almaDaCasaIsTheTopAndFinal() {
        #expect(Tier.allCases.count == 13)
        #expect(Tier(points: Tier.topThreshold - 1) == .quatorzeBisIII)
        #expect(Tier(points: Tier.topThreshold) == .dragaoChines)
        #expect(Tier(points: 1_000_000) == .dragaoChines)
        #expect(Tier.dragaoChines.next == nil)
        #expect(Tier.dragaoChines.divisionSize == nil)
    }

    @Test func oldStoredValuesLandOnTheSameHeightOfTheLadder() {
        #expect(Tier(stored: "tier1") == .tradicionalI)
        #expect(Tier(stored: "bronze1") == .tradicionalI)
        #expect(Tier(stored: "Master") == .dragaoChines)
        #expect(Tier(stored: "aprendiz") == .tradicionalII)
        #expect(Tier(stored: "unknown") == .tradicionalI)
        #expect(Tier(stored: nil) == .tradicionalI)
    }

    @Test func everyTierStartsAtItsThreshold() {
        for (index, tier) in Tier.allCases.enumerated() {
            #expect(tier.minimumPoints == Tier.thresholds[index])
            #expect(Tier(points: Tier.thresholds[index]) == tier)
        }
    }

    @Test func surplusCarriesOverIntoTheNextDivision() {
        let start = Tier.deltaI.minimumPoints
        let size = Tier.deltaI.divisionSize ?? 0
        let progress = Tier.progress(forPoints: start + 10)
        #expect(progress.tier == .deltaI)
        #expect(progress.pointsIntoDivision == 10)
        #expect(progress.pointsToNext == size - 10)
        #expect(progress.nextTier == .deltaII)
        #expect(progress.fraction == Double(10) / Double(size))
    }

    @Test func topProgressHasNoNextStep() {
        let progress = Tier.progress(forPoints: Tier.topThreshold + 500)
        #expect(progress.tier == .dragaoChines)
        #expect(progress.pointsIntoDivision == 500)
        #expect(progress.pointsToNext == nil)
        #expect(progress.fraction == 1)
    }

    @Test func userTierFollowsPoints() {
        let user = UserModel(name: "Ana", tier: .tradicionalI, ownerRecordName: "ana")
        user.points = Tier.deltaI.minimumPoints
        #expect(user.tier == .deltaI)
        user.points = 0
        #expect(user.tier == .tradicionalI)
    }
}
