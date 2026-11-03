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

    /// 25 points per division.
    let step = Tier.pointsPerDivision

    @Test func startsAtNovatoDaCasa() {
        #expect(Tier(points: 0) == .novatoDaCasa)
        #expect(Tier(points: -50) == .novatoDaCasa)
    }

    @Test func climbsOneRankEveryStep() {
        #expect(Tier(points: step - 1) == .novatoDaCasa)
        #expect(Tier(points: step) == .aprendiz)
        #expect(Tier(points: step * 2 - 1) == .aprendiz)
        #expect(Tier(points: step * 2) == .ajudanteOficial)
        #expect(Tier(points: step * 6) == .guardiaoDaCasa)
    }

    @Test func almaDaCasaIsTheTopAndFinal() {
        #expect(Tier.allCases.count == 13)
        #expect(Tier(points: step * 12 - 1) == .lendaDaCasa)
        #expect(Tier(points: step * 12) == .almaDaCasa)
        #expect(Tier(points: 1_000_000) == .almaDaCasa)
        #expect(Tier.almaDaCasa.next == nil)
    }

    @Test func oldStoredValuesLandOnTheSameHeightOfTheLadder() {
        #expect(Tier(stored: "tier1") == .novatoDaCasa)
        #expect(Tier(stored: "bronze1") == .novatoDaCasa)
        #expect(Tier(stored: "Master") == .almaDaCasa)
        #expect(Tier(stored: "aprendiz") == .aprendiz)
        #expect(Tier(stored: "unknown") == .novatoDaCasa)
        #expect(Tier(stored: nil) == .novatoDaCasa)
    }

    @Test func everyTierIsOneStepOfTheLadder() {
        for (index, tier) in Tier.allCases.enumerated() {
            #expect(tier.minimumPoints == index * step)
            #expect(Tier(points: index * step) == tier)
        }
    }

    @Test func surplusCarriesOverIntoTheNextDivision() {
        let progress = Tier.progress(forPoints: step * 3 + 10)
        #expect(progress.tier == .escudeiroDaFaxina)
        #expect(progress.pointsIntoDivision == 10)
        #expect(progress.pointsToNext == step - 10)
        #expect(progress.nextTier == .vigiaDaCozinha)
    }

    @Test func topProgressHasNoNextStep() {
        let progress = Tier.progress(forPoints: step * 12 + 500)
        #expect(progress.tier == .almaDaCasa)
        #expect(progress.pointsIntoDivision == 500)
        #expect(progress.pointsToNext == nil)
    }

    @Test func userTierFollowsPoints() {
        let user = UserModel(name: "Ana", tier: .novatoDaCasa, ownerRecordName: "ana")
        user.points = step * 3
        #expect(user.tier == .escudeiroDaFaxina)
        user.points = 0
        #expect(user.tier == .novatoDaCasa)
    }
}
