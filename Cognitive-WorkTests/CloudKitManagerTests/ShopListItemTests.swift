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
struct ShopListItemTests {

    @Test func createShopListItemSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let shopListItem = ShopListItem(name: "CreatTest", value: 0, quantity: 1, unitMeasurement: .gram)
        let savedItem = await CloudKitManager.shared.create(shopListItem)
        
        print("ERRO:", CloudKitManager.shared.errorMessage as Any)
        
        #expect(savedItem != nil)
        if let savedItem {
            await CloudKitManager.shared.delete(savedItem)
        }
    }
    
    @Test func fetchAllShopListItemSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let shopListItem = ShopListItem(name: "FetchTest", value: 0, quantity: 1, unitMeasurement: .gram)
        let savedItem = await CloudKitManager.shared.create(shopListItem)
        #expect(savedItem != nil)
        
        let items = await CloudKitManager.shared.fetchAll(ShopListItem.self)
        print("ERRO:", CloudKitManager.shared.errorMessage as Any)
        
        #expect(!items.isEmpty)
        await CloudKitManager.shared.delete(savedItem!)
    }
    
    @Test func fetchCreatedShopListItemWithPredicateSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let shopListItem = ShopListItem(name: "FetchWithPredicateTest", value: 0, quantity: 1, unitMeasurement: .gram)
        let itemSaved = await CloudKitManager.shared.create(shopListItem)
        #expect(itemSaved != nil)
        
        try await Task.sleep(for: .seconds(2))
        
        let predicate = NSPredicate(format: "name == %@", "FetchWithPredicateTest")
        let item = await CloudKitManager.shared.fetchAll(ShopListItem.self, predicate: predicate)
        print("Error:", CloudKitManager.shared.errorMessage as Any)
        
        #expect(item.contains { $0.name == "FetchWithPredicateTest" })
        
        if let savedItem = itemSaved {
            await CloudKitManager.shared.delete(savedItem)
        }
    }
    
    @Test func updateShopListItemSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let shopListItem = ShopListItem(name: "UpdateTest", value: 0, quantity: 1, unitMeasurement: .gram)
        var savedItem = await CloudKitManager.shared.create(shopListItem)
        #expect(savedItem != nil)
        
        try await Task.sleep(for: .seconds(2))
        
        savedItem?.name = "updatedName"
        await CloudKitManager.shared.update(savedItem!)
        try await Task.sleep(for: .seconds(2))

        let predicate = NSPredicate(format: "name == %@", "updatedName")
        let updatedCheckItem = await CloudKitManager.shared.fetchAll(ShopListItem.self, predicate: predicate)
        
        #expect(updatedCheckItem.contains{$0.name == "updatedName"})
        await CloudKitManager.shared.delete(updatedCheckItem.first!)
    }
    
    @Test func deleteShopListItemSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let shopListItem = ShopListItem(name: "DeleteTest", value: 0, quantity: 1, unitMeasurement: .gram)
        let itemSaved = await CloudKitManager.shared.create(shopListItem)
        
        #expect(itemSaved != nil)
        try await Task.sleep(for: .seconds(2))
        
        let isDeleted = await CloudKitManager.shared.delete(itemSaved!)
        #expect(isDeleted)
    }

}
