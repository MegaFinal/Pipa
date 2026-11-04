//
//  ChoreCompletionPersistenceTests.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 29/09/26.
//

import Testing
import Foundation
import CloudKit
@testable import Cognitive_Work

/// Who completed a chore or occurrence must survive a round trip through a `CKRecord`,
/// otherwise undoing it can't take the points back from the right person.
@MainActor
struct ChoreCompletionPersistenceTests {
    
    private let doer = CKRecord.Reference(recordID: CKRecord.ID(recordName: "doer"), action: .none)
    
    @Test func occurrenceKeepsWhoCompletedIt() throws {
        let assignment = RecurrentAssignmentModel(day: Date(), isCompleted: true)
        assignment.userThatHaveDoneReference = doer
        
        let record = CKRecord(recordType: RecurrentAssignmentModel.recordType)
        assignment.populate(record: record)
        let decoded = try #require(RecurrentAssignmentModel(record: record))
        
        #expect(decoded.isCompleted)
        #expect(decoded.userThatHaveDoneReference?.recordID == doer.recordID)
    }
    
    @Test func undoingAnOccurrenceClearsWhoCompletedIt() throws {
        let record = CKRecord(recordType: RecurrentAssignmentModel.recordType)
        record["userThatHaveDone"] = doer
        
        let assignment = RecurrentAssignmentModel(day: Date(), isCompleted: false)
        assignment.populate(record: record)
        
        #expect(record["userThatHaveDone"] == nil)
    }
    
    @Test func undoingAChoreClearsWhoCompletedIt() {
        let record = CKRecord(recordType: ChoreModel.recordType)
        record["userThatHaveDone"] = doer
        
        let chore = ChoreModel(name: "Lavar", description: "", frequency: .none, duration: 300, isPublic: true, priorityTag: .low)
        chore.populate(record: record)
        
        #expect(record["userThatHaveDone"] == nil)
    }
    
    @Test func listQueriesFetchWhoCompletedAChore() {
        #expect(ChoreModel.listDesiredKeys?.contains("userThatHaveDone") == true)
    }
}
