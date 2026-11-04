//
//  ChoreDurationTests.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 30/09/26.
//

import Testing
import Foundation
import CloudKit
@testable import Cognitive_Work

/// `duration` is always in minutes; records saved in seconds by older builds are converted.
@MainActor
struct ChoreDurationTests {
    
    private func record(withDuration duration: Double) -> CKRecord {
        let chore = ChoreModel(name: "Lavar", description: "", frequency: .daily, duration: 15, isPublic: true, priorityTag: .low)
        let record = CKRecord(recordType: ChoreModel.recordType)
        chore.populate(record: record)
        record["duration"] = duration
        return record
    }
    
    @Test func durationSavedInSecondsIsReadAsMinutes() throws {
        let chore = try #require(ChoreModel(record: record(withDuration: 1800)))
        
        #expect(chore.duration == 30)
        #expect(chore.needsDurationMigration)
    }
    
    @Test func durationSavedInMinutesIsKept() throws {
        let chore = try #require(ChoreModel(record: record(withDuration: 45)))
        
        #expect(chore.duration == 45)
        #expect(!chore.needsDurationMigration)
    }
    
    @Test func onlyWholeMinutesFromFiveHoursUpAreLegacySeconds() {
        #expect(ChoreModel.isLegacySecondsDuration(300))
        #expect(ChoreModel.isLegacySecondsDuration(7200))
        #expect(!ChoreModel.isLegacySecondsDuration(120))
        #expect(!ChoreModel.isLegacySecondsDuration(301))
    }
    
    @Test func pickingATierStoresMinutesThatMapBackToTheSameTier() {
        for tier in ChoreDurationTier.allCases where tier != .undefined {
            #expect(ChoreDurationTier.from(minutes: tier.minutes) == tier)
        }
    }
}
