//
//  ChoreModelTests.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 13/08/26.
//

import Testing
import Foundation
import CloudKit
@testable import Cognitive_Work

@MainActor
struct ChoreModelTests {

    @Test func createChoreSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let chore = ChoreModel(
            name: "choreTest",
            description: "testDescription",
            frequency: .daily,
            duration: 30.0,
            isPublic: true,
            priorityTag: .urgent,
            calendarEventIdentifier: " "
        )
        
        let savedItem = await CloudKitManager.shared.create(chore)
        
        print("ERRO:", CloudKitManager.shared.errorMessage as Any)
        
        #expect(savedItem != nil)
        
        if let savedItem {
            await CloudKitManager.shared.delete(savedItem)
        }
    }
    
    @Test
    func fetchAllChoresSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let chore = ChoreModel(
            name: "fetchChoreTest",
            description: "fetchDescription",
            frequency: .daily,
            duration: 30.0,
            isPublic: true,
            priorityTag: .urgent
        )
        
        let savedItem = await CloudKitManager.shared.create(chore)
        
        let chores = await CloudKitManager.shared.fetchAll(ChoreModel.self)
        print("ERROR:", CloudKitManager.shared.errorMessage as Any)
        
        #expect(!chores.isEmpty)
        
        if let savedItem {
            await CloudKitManager.shared.delete(savedItem)
        }
    }
    
    @Test
    func fetchCreatedChoreWithPredicateSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let chore = ChoreModel(
            name: "fetchChoreTest",
            description: "fetchDescription",
            frequency: .daily,
            duration: 30.0,
            isPublic: true,
            priorityTag: .urgent
        )
        let savedItem = await CloudKitManager.shared.create(chore)
        
        let predicate = NSPredicate(format: "name == %@", "fetchChoreTest")
        let chores = await CloudKitManager.shared.fetchAll(ChoreModel.self, predicate: predicate)
        print("ERROR:", CloudKitManager.shared.errorMessage as Any)
        
        #expect(chores.contains { $0.name == chore.name })
        
        if let savedItem {
            await CloudKitManager.shared.delete(savedItem)
        }
    }
    
    @Test
    func fetchFirstChoreSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let chores = await CloudKitManager.shared.fetchAll(ChoreModel.self)
        print("ERROR:", CloudKitManager.shared.errorMessage as Any)
        
        #expect(!chores.isEmpty)
    }
    
    @Test
    func deleteCreatedChoreSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let chore = ChoreModel(
            name: "deleteChoreTest",
            description: "deleteChoreTest",
            frequency: .daily,
            duration: 30.0,
            isPublic: true,
            priorityTag: .urgent
        )
        let savedItem = await CloudKitManager.shared.create(chore)
        
        let result = await CloudKitManager.shared.delete(savedItem!)
        
        #expect(result == true)
    }
    
    @Test
    func updateCreatedChoreSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let chore = ChoreModel(
            name: "updateChoreTest",
            description: "updateChoreTest",
            frequency: .daily,
            duration: 30.0,
            isPublic: true,
            priorityTag: .urgent
        )
        var savedItem = await CloudKitManager.shared.create(chore)
        savedItem!.name = "newName"
            
        let result = await CloudKitManager.shared.update(savedItem!)
        
        #expect(result == true)
    }
}
