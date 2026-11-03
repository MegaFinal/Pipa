//
//  HouseModelTests.swift
//  Cognitive-WorkTests
//
//  Created by Carolina Sun on 13/08/26.
//

import Foundation
import Testing
import Foundation
import CloudKit
@testable import Cognitive_Work

@MainActor
struct HouseModelTests {
    @Test func createHouseSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let house = HouseModel(name: "houseNameTest", description: "houseDescriptionTest")
        let itemSaved = await CloudKitManager.shared.create(house)
        
        print("ERRO:", CloudKitManager.shared.errorMessage as Any)
        
        #expect(itemSaved != nil)
        
        if let itemSaved {
            await CloudKitManager.shared.delete(itemSaved)
        }
    }
    @Test func fetchAllHousesSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let house = HouseModel(name: "houseNameTest", description: "houseDescriptionTest")
        let itemSaved = await CloudKitManager.shared.create(house)
        
        #expect(itemSaved != nil)
        try await Task.sleep(for: .seconds(2))
        
        let fetchedHouse = await CloudKitManager.shared.fetchAll(HouseModel.self)
        for house in fetchedHouse{
            print("\n", house)
        }
        print("ERROR:", CloudKitManager.shared.errorMessage as Any)
        #expect(!fetchedHouse.isEmpty)
        
        if let itemSaved = itemSaved {
            await CloudKitManager.shared.delete(itemSaved)
        }
    }
    
    @Test func fetchSpecificHouseSuccessfully() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let house =  HouseModel(name: "SpecificHouseNameTest", description: "houseDescriptionTest")
        let itemSaved = await CloudKitManager.shared.create(house)
        
        #expect(itemSaved != nil)
        try await Task.sleep(for: .seconds(2))
        
        let predicate = NSPredicate(format: "name == %@", "SpecificHouseNameTest")
        let fetchedHouses = await CloudKitManager.shared.fetchAll(HouseModel.self, predicate: predicate)
        print(fetchedHouses)
        print("Error:", CloudKitManager.shared.errorMessage as Any)
        
        #expect(fetchedHouses.contains { $0.name == "SpecificHouseNameTest" })
        
        if let itemSaved = itemSaved {
            await CloudKitManager.shared.delete(itemSaved)
        }
    }
    
    @Test func updateHouseSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let house = HouseModel(name: "houseNameTest", description: "houseDescriptionTest")
        var itemSaved = await CloudKitManager.shared.create(house)
        
        #expect(itemSaved != nil)
        try await Task.sleep(for: .seconds(2))
        
        itemSaved?.name = "UpdatedHouseName"
        await CloudKitManager.shared.update(itemSaved!)
        try await Task.sleep(for: .seconds(2))

        let predicate = NSPredicate(format: "name == %@", "UpdatedHouseName")
        let updatedUsers = await CloudKitManager.shared.fetchAll(HouseModel.self, predicate: predicate)
        #expect(updatedUsers.contains { $0.name == "UpdatedHouseName"})
        
        await CloudKitManager.shared.delete(itemSaved!)
    }
    
    @Test func deleteHouseSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let house =  HouseModel(name: "SpecificHouseNameTest", description: "houseDescriptionTest")
        let itemSaved = await CloudKitManager.shared.create(house)
        
        #expect(itemSaved != nil)
        try await Task.sleep(for: .seconds(2))
        
        let isDeleted = await CloudKitManager.shared.delete(itemSaved!)
        #expect(isDeleted)
    }
}

