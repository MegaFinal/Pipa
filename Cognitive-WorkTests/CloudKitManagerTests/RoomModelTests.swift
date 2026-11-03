//
//  UserModelTests.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 13/08/26.
//

import Testing
import Foundation
@testable import Cognitive_Work

@MainActor
struct RoomModelTests {

    @Test func createRoomSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let room = RoomModel(name: "roomTestName", symbol: "", color: RoomColor.blue)
        
        let itemSaved = await CloudKitManager.shared.create(room)
        CloudKitManager.shared.errorMessage == nil ? print("success") : print("ERRO:", CloudKitManager.shared.errorMessage as Any)
        
        #expect(itemSaved != nil)
        if let itemSaved = itemSaved {
            await CloudKitManager.shared.delete(itemSaved)
        }
    }
    
    @Test func fetchAllRoomsSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let room = RoomModel(name: "roomFetchAllTestName", symbol: "", color: RoomColor.blue)
        let itemSaved = await CloudKitManager.shared.create(room)
        #expect(itemSaved != nil)
        try await Task.sleep(for: .seconds(2))

        let fetchedUser = await CloudKitManager.shared.fetchAll(UserModel.self)
        #expect(!fetchedUser.isEmpty)
        
        if let itemSaved = itemSaved {
            await CloudKitManager.shared.delete(itemSaved)
        }
    }
    
    @Test func fetchSpecificRoomSuccessfully() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let room = RoomModel(name: "roomFetchSpecificTestName", symbol: "", color: RoomColor.blue)
        let itemSaved = await CloudKitManager.shared.create(room)
        
        #expect(itemSaved != nil)
        try await Task.sleep(for: .seconds(2))
        
        let predicate = NSPredicate(format: "name == %@", "roomFetchSpecificTestName")
        let fetchedRooms = await CloudKitManager.shared.fetchAll(RoomModel.self, predicate: predicate)
        print(fetchedRooms)
        print("Error:", CloudKitManager.shared.errorMessage as Any)
        
        #expect(fetchedRooms.contains { $0.name == "roomFetchSpecificTestName" })
        
        if let itemSaved = itemSaved {
            await CloudKitManager.shared.delete(itemSaved)
        }
    }

    @Test func updateRoomsSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let room = RoomModel(name: "roomUpdateTestName", symbol: "", color: RoomColor.blue)
        var itemSaved = await CloudKitManager.shared.create(room)
        
        #expect(itemSaved != nil)
        try await Task.sleep(for: .seconds(2))
        
        itemSaved?.name = "UpdatedName"
        await CloudKitManager.shared.update(itemSaved!)
        try await Task.sleep(for: .seconds(2))

        let predicate = NSPredicate(format: "name == %@", "UpdatedName")
        let updatedRooms = await CloudKitManager.shared.fetchAll(RoomModel.self, predicate: predicate)
        #expect(updatedRooms.contains { $0.name == "UpdatedName"})
        
        await CloudKitManager.shared.delete(itemSaved!)
    }
    
    @Test func deleteRoomSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let room = UserModel(name: "SpecificUser", tier: .tier1, ownerRecordName: "")
        let itemSaved = await CloudKitManager.shared.create(room)
        
        #expect(itemSaved != nil)
        try await Task.sleep(for: .seconds(2))
        
        let isDeleted = await CloudKitManager.shared.delete(itemSaved!)
        #expect(isDeleted)
    }
}
