//
//  NormalizationTest.swift
//  Cognitive-WorkTests
//
//  Created by anshu Li on 20/08/26.
//

import Testing
import Foundation
import CloudKit
@testable import Cognitive_Work

@MainActor
struct NormalizationTest {
    
    // MARK: - Teste Normalization Logic
        @Test func normalizationFunctionTests() async {
            // min = 0, max = 10, value = 5, result 0.5
            let normalResult = TaskSchedulerEngine.normalization(value: 5.0, min: 0.0, max: 10.0)
            #expect(normalResult == 0.5)
            
            let overflowResult = TaskSchedulerEngine.normalization(value: 15.0, min: 0.0, max: 10.0)
            #expect(overflowResult == 1.0)
            
            let underflowResult = TaskSchedulerEngine.normalization(value: -5.0, min: 0.0, max: 10.0)
            #expect(underflowResult == 0.0)
            
            let zeroDivisionResult = TaskSchedulerEngine.normalization(value: 5.0, min: 10.0, max: 10.0)
            #expect(zeroDivisionResult == 0.0)
        }

        // MARK: - Teste Normalized Weight Calculation
        @Test func normalizedWeightCalculationTests() async {

            var chore = ChoreModel(
                name: "TestTask",
                description: "Desc",
                frequency: .none,
                duration: 1 * 60, // timeNormalized = 0.0
                isPublic: true,
                priorityTag: .low  // priorityNormalized = 0.0
            )
            
            let minWeight = TaskSchedulerEngine.normalizedWeight(chore: chore)
            #expect(minWeight == 0.0) // 0.0 * 0.7 + 0.0 * 0.3 = 0.0
            
            chore.priorityTag = .urgent // priorityNormalized = 1.0
            chore.duration = 8 * 60     // timeNormalized = 1.0
            
            let maxWeight = TaskSchedulerEngine.normalizedWeight(chore: chore)
            #expect(maxWeight == 1.0) // 1.0 * 0.7 + 1.0 * 0.3 = 1.0
        }
}
