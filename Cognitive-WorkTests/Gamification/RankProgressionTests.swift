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
        #expect(Tier(points: 0) == .novatoDaCasa)
        #expect(Tier(points: -50) == .novatoDaCasa)
    }

    @Test func climbsAtEachThreshold() {
        #expect(Tier(points: Tier.aprendiz.minimumPoints - 1) == .novatoDaCasa)
        #expect(Tier(points: Tier.aprendiz.minimumPoints) == .aprendiz)
        #expect(Tier(points: Tier.ajudanteOficial.minimumPoints - 1) == .aprendiz)
        #expect(Tier(points: Tier.ajudanteOficial.minimumPoints) == .ajudanteOficial)
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
        #expect(Tier(points: Tier.topThreshold - 1) == .lendaDaCasa)
        #expect(Tier(points: Tier.topThreshold) == .almaDaCasa)
        #expect(Tier(points: 1_000_000) == .almaDaCasa)
        #expect(Tier.almaDaCasa.next == nil)
        #expect(Tier.almaDaCasa.divisionSize == nil)
    }

    @Test func oldStoredValuesLandOnTheSameHeightOfTheLadder() {
        #expect(Tier(stored: "tier1") == .novatoDaCasa)
        #expect(Tier(stored: "bronze1") == .novatoDaCasa)
        #expect(Tier(stored: "Master") == .almaDaCasa)
        #expect(Tier(stored: "aprendiz") == .aprendiz)
        #expect(Tier(stored: "unknown") == .novatoDaCasa)
        #expect(Tier(stored: nil) == .novatoDaCasa)
    }

    @Test func everyTierStartsAtItsThreshold() {
        for (index, tier) in Tier.allCases.enumerated() {
            #expect(tier.minimumPoints == Tier.thresholds[index])
            #expect(Tier(points: Tier.thresholds[index]) == tier)
        }
    }

    @Test func surplusCarriesOverIntoTheNextDivision() {
        let start = Tier.escudeiroDaFaxina.minimumPoints
        let size = Tier.escudeiroDaFaxina.divisionSize ?? 0
        let progress = Tier.progress(forPoints: start + 10)
        #expect(progress.tier == .escudeiroDaFaxina)
        #expect(progress.pointsIntoDivision == 10)
        #expect(progress.pointsToNext == size - 10)
        #expect(progress.nextTier == .vigiaDaCozinha)
        #expect(progress.fraction == Double(10) / Double(size))
    }

    @Test func topProgressHasNoNextStep() {
        let progress = Tier.progress(forPoints: Tier.topThreshold + 500)
        #expect(progress.tier == .almaDaCasa)
        #expect(progress.pointsIntoDivision == 500)
        #expect(progress.pointsToNext == nil)
        #expect(progress.fraction == 1)
    }

    @Test func userTierFollowsPoints() {
        let user = UserModel(name: "Ana", tier: .novatoDaCasa, ownerRecordName: "ana")
        user.points = Tier.escudeiroDaFaxina.minimumPoints
        #expect(user.tier == .escudeiroDaFaxina)
        user.points = 0
        #expect(user.tier == .novatoDaCasa)
    }
}
