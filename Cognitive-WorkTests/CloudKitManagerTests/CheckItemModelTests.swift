//
//  CheckItemModelTests.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 13/08/26.
//

import Testing
import Foundation
@testable import Cognitive_Work

@MainActor
struct CheckItemModelTests {

    @Test func createCheckItemSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let checkItem = CheckItemModel(name: "checkItemCreateTest", isDone: false)
        let savedItem = await CloudKitManager.shared.create(checkItem)
        
        print("ERRO:", CloudKitManager.shared.errorMessage as Any)
        
        #expect(savedItem != nil)
    }
    
    @Test func fetchAllCheckItemsSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let checkItem = CheckItemModel(name: "checkItemFetchTest", isDone: false)
        let savedItem = await CloudKitManager.shared.create(checkItem)
        #expect(savedItem != nil)
        
        let items = await CloudKitManager.shared.fetchAll(CheckItemModel.self)
        print("ERRO:", CloudKitManager.shared.errorMessage as Any)
        
        #expect(!items.isEmpty)
    }
    
    @Test func fetchCreatedCheckItemWithPredicateSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let checkItem = CheckItemModel(name: "checkItemPredicateTest", isDone: false)
        let itemSaved = await CloudKitManager.shared.create(checkItem)
        #expect(itemSaved != nil)
        
        try await Task.sleep(for: .seconds(2))
        
        let predicate = NSPredicate(format: "name == %@", "checkItemPredicateTest")
        let item = await CloudKitManager.shared.fetchAll(CheckItemModel.self, predicate: predicate)
        print("Error:", CloudKitManager.shared.errorMessage as Any)
        
        #expect(item.contains { $0.name == "checkItemPredicateTest" })
        
        if let savedItem = itemSaved {
            await CloudKitManager.shared.delete(savedItem)
        }
    }
    
    @Test func updateCheckItemSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let checkItem = CheckItemModel(name: "checkItemUpdateTest", isDone: false)
        var savedItem = await CloudKitManager.shared.create(checkItem)
        #expect(savedItem != nil)
        
        try await Task.sleep(for: .seconds(2))
        
        savedItem?.name = "updatedName"
        await CloudKitManager.shared.update(savedItem!)
        try await Task.sleep(for: .seconds(2))

        let predicate = NSPredicate(format: "name == %@", "updatedName")
        let updatedCheckItem = await CloudKitManager.shared.fetchAll(CheckItemModel.self, predicate: predicate)
        
        #expect(updatedCheckItem.contains { $0.name == "updatedName"})
    }
    
    @Test func deleteCheckItemSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let checkItem = CheckItemModel(name: "checkITemDeleteTest", isDone: false)
        let itemSaved = await CloudKitManager.shared.create(checkItem)
        
        #expect(itemSaved != nil)
        try await Task.sleep(for: .seconds(2))
        
        let isDeleted = await CloudKitManager.shared.delete(itemSaved!)
        #expect(isDeleted)
    }

}
