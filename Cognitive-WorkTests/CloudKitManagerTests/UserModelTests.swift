//
//  UserModelTests.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 13/08/26.
//

import Testing
import Foundation
import CloudKit
import _PhotosUI_SwiftUI
@testable import Cognitive_Work

@MainActor
struct UserModelTests {

    @Test func createUserSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        let defaultRecordID = CKRecord.ID(recordName: "testRecord")
        let defaultRefetence = CKRecord.Reference(recordID: defaultRecordID, action: .none)
        
        let image = UIImage(named: "defaultUser")
        let data = image?.jpegData(compressionQuality: 0.9)
        let uniqueFilename = UUID().uuidString + ".jpg"
        let tempDirectoryURL = FileManager.default.temporaryDirectory
        let fileURL = tempDirectoryURL.appendingPathComponent(uniqueFilename)
        try data?.write(to: fileURL, options: .atomic)
        let defaultAsset = CKAsset(fileURL: fileURL)

        //Write the data to disk
        
        let user = UserModel(name: "creatTest",
                             profilePicture: defaultAsset,
                             tier: .tier1,
                             coins: 0,
                             points: 10,
                             badges: [defaultRefetence],
                             tasks: [defaultRefetence],
                             availableTime: [defaultRefetence],
                             house: defaultRefetence,
                             coupons: [defaultRefetence],
                             couponLimit: 10,
                             ownerRecordName: ""
        )
        
        let itemSaved = await CloudKitManager.shared.create(user)
        CloudKitManager.shared.errorMessage == nil ? print("success") : print("ERRO:", CloudKitManager.shared.errorMessage as Any)
        
        print(CloudKitManager.shared.errorMessage as Any)
        #expect(itemSaved != nil)
        if let itemSaved = itemSaved {
            await CloudKitManager.shared.delete(itemSaved)
        }
    }
    
    @Test func fetchAllUsersSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let user = UserModel(name: "AllUser", tier: .tier1, ownerRecordName: "")
        let itemSaved = await CloudKitManager.shared.create(user)
        #expect(itemSaved != nil)
        try await Task.sleep(for: .seconds(2))

        let fetchedUser = await CloudKitManager.shared.fetchAll(UserModel.self)
        #expect(!fetchedUser.isEmpty)
        
        if let itemSaved = itemSaved {
            await CloudKitManager.shared.delete(itemSaved)
        }
    }
    
    @Test func fetchSpecificUserSuccessfully() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let user = UserModel(name: "SpecificUser", tier: .tier1, ownerRecordName: "")
        let itemSaved = await CloudKitManager.shared.create(user)
        
        #expect(itemSaved != nil)
        try await Task.sleep(for: .seconds(2))
        
        let predicate = NSPredicate(format: "name == %@", "SpecificUser")
        let fetchedUsers = await CloudKitManager.shared.fetchAll(UserModel.self, predicate: predicate)
        print(fetchedUsers)
        print("Error:", CloudKitManager.shared.errorMessage as Any)
        
        #expect(fetchedUsers.contains { $0.name == "SpecificUser" })
        
        if let itemSaved = itemSaved {
            await CloudKitManager.shared.delete(itemSaved)
        }
    }

    @Test func updateUserSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let user = UserModel(name: "SpecificUser", tier: .tier1, ownerRecordName: "")
        var itemSaved = await CloudKitManager.shared.create(user)
        
        #expect(itemSaved != nil)
        try await Task.sleep(for: .seconds(2))
        
        itemSaved?.name = "UpdatedName"
        await CloudKitManager.shared.update(itemSaved!)
        try await Task.sleep(for: .seconds(2))

        let predicate = NSPredicate(format: "name == %@", "UpdatedName")
        let updatedUsers = await CloudKitManager.shared.fetchAll(UserModel.self, predicate: predicate)
        #expect(updatedUsers.contains { $0.name == "UpdatedName"})
        
        await CloudKitManager.shared.delete(itemSaved!)
    }
    
    @Test func deleteUserSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let user = UserModel(name: "SpecificUser", tier: .tier1, ownerRecordName: " ")
        let itemSaved = await CloudKitManager.shared.create(user)
        
        #expect(itemSaved != nil)
        try await Task.sleep(for: .seconds(2))
        
        let isDeleted = await CloudKitManager.shared.delete(itemSaved!)
        #expect(isDeleted)
    }
}
