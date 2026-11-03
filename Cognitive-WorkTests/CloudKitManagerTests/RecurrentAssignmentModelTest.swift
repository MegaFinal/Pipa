//
//  RecurrentAssignmentModelTest.swift
//  Cognitive-WorkTests
//
//  Created by anshu Li on 21/09/26.
//

import Foundation
import Testing
import CloudKit
@testable import Cognitive_Work

@MainActor
struct RecurrentAssignmentModelTests {

    @Test func createRecurrentAssignmentWithIdentifierTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let assignment = RecurrentAssignmentModel(
            day: Date(),
            isCompleted: false,
            calendarEventIdentifier: "test-event-identifier-12345"
        )
        
        let savedItem = await CloudKitManager.shared.create(assignment)
        
        print("CloudKit Error (if any):", CloudKitManager.shared.errorMessage as Any)
        
        #expect(savedItem != nil)
        #expect(savedItem?.calendarEventIdentifier == "test-event-identifier-12345")
        
        if let savedItem {
            let success = await CloudKitManager.shared.delete(savedItem)
            #expect(success, "Failed to clean up test assignment from CloudKit.")
        }
    }
}
