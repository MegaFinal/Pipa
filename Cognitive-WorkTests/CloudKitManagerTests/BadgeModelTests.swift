//
//  CheckItemModelTests 2.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 27/08/26.
//


import Testing
import Foundation
import CloudKit
@testable import Cognitive_Work

@MainActor
struct BadgeModelTests {

    @Test func createBadgeSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let placeholderReference = CKRecord.Reference(recordID: CKRecord.ID(recordName: "UserModel"), action: .none)
        let badge = BadgeModel(name: "CreateTestBadge", image: Data(), description: "Test description", tier: .tier1, room: placeholderReference, users: [placeholderReference])
        let savedItem = await CloudKitManager.shared.create(badge)
        
        print("ERRO:", CloudKitManager.shared.errorMessage as Any)
        
        #expect(savedItem != nil)
        await CloudKitManager.shared.delete(savedItem!)
    }
    
    @Test func fetchAllBadgesSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let badge = BadgeModel(name: "fetchTestBadge", image: Data(), description: "Test Description", tier: .tier1)
        let savedItem = await CloudKitManager.shared.create(badge)
        #expect(savedItem != nil)
        
        let items = await CloudKitManager.shared.fetchAll(BadgeModel.self)
        print("ERRO:", CloudKitManager.shared.errorMessage as Any)
        
        #expect(!items.isEmpty)
        await CloudKitManager.shared.delete(savedItem!)
    }
    
    @Test func fetchCreatedBadgesWithPredicateSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let badge = BadgeModel(name: "fetchWithPredicateTestBadge", image: Data(), description: "Test Description", tier: .tier1)
        let itemSaved = await CloudKitManager.shared.create(badge)
        #expect(itemSaved != nil)
        
        try await Task.sleep(for: .seconds(2))
        
        let predicate = NSPredicate(format: "name == %@", "fetchWithPredicateTestBadge")
        let item = await CloudKitManager.shared.fetchAll(BadgeModel.self, predicate: predicate)
        print("Error:", CloudKitManager.shared.errorMessage as Any)
        
        #expect(item.contains { $0.name == "fetchWithPredicateTestBadge" })
        
        if let savedItem = itemSaved {
            await CloudKitManager.shared.delete(savedItem)
        }
    }
    
    @Test func updateBadgesSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let badge = BadgeModel(name: "updateBadgeTest", image: Data(), description: "Test Description", tier: .tier1)
        var savedItem = await CloudKitManager.shared.create(badge)
        #expect(savedItem != nil)
        
        try await Task.sleep(for: .seconds(2))
        
        savedItem?.name = "updatedName"
        await CloudKitManager.shared.update(savedItem!)
        try await Task.sleep(for: .seconds(2))

        let predicate = NSPredicate(format: "name == %@", "updatedName")
        let updatedCheckItem = await CloudKitManager.shared.fetchAll(BadgeModel.self, predicate: predicate)
        
        #expect(updatedCheckItem.contains{$0.name == "updatedName"})
        await CloudKitManager.shared.delete(updatedCheckItem.first!)
    }
    
    @Test func deleteBadgesSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let badge = BadgeModel(name: "deleteBadgeTest", image: Data(), description: "Test Description", tier: .tier1)
        let itemSaved = await CloudKitManager.shared.create(badge)
        
        #expect(itemSaved != nil)
        try await Task.sleep(for: .seconds(2))
        
        let isDeleted = await CloudKitManager.shared.delete(itemSaved!)
        #expect(isDeleted)
    }

}
