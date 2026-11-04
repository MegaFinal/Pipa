//
//  CheckItemModelTests 2.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 27/08/26.
//


import Testing
import Foundation
import CloudKit
import SwiftUI
@testable import Cognitive_Work

@MainActor
struct TagModelTests {

    @Test func createTagModelSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let tagModel = TagModel(name: "CreatTest", color: .gray)
        let savedItem = await CloudKitManager.shared.create(tagModel)
        
        print("ERRO:", CloudKitManager.shared.errorMessage as Any)
        
        #expect(savedItem != nil)
        if let savedItem {
            await CloudKitManager.shared.delete(savedItem)
        }
    }
    
    @Test func fetchAllTagModelSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let tagModel = TagModel(name: "FetchTest", color: .gray)
        let savedItem = await CloudKitManager.shared.create(tagModel)
        
        #expect(savedItem != nil)
        
        let items = await CloudKitManager.shared.fetchAll(TagModel.self)
        print("ERRO:", CloudKitManager.shared.errorMessage as Any)
        
        #expect(!items.isEmpty)
        await CloudKitManager.shared.delete(savedItem!)
    }
    
    @Test func fetchCreatedTagModelWithPredicateSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let tagModel = TagModel(name: "FetchWithPredicateTest", color: .gray)
        let savedItem = await CloudKitManager.shared.create(tagModel)
        #expect(savedItem != nil)
        
        try await Task.sleep(for: .seconds(2))
        
        let predicate = NSPredicate(format: "name == %@", "FetchWithPredicateTest")
        let item = await CloudKitManager.shared.fetchAll(TagModel.self, predicate: predicate)
        print("Error:", CloudKitManager.shared.errorMessage as Any)
        
        #expect(item.contains { $0.name == "FetchWithPredicateTest" })
        
        if let savedItem {
            await CloudKitManager.shared.delete(savedItem)
        }
    }
    
    @Test func updateTagModelSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let tagModel = TagModel(name: "updateTagModel", color: .gray)
        var savedItem = await CloudKitManager.shared.create(tagModel)
        
        #expect(savedItem != nil)
        
        try await Task.sleep(for: .seconds(2))
        
        savedItem?.name = "updatedName"
        await CloudKitManager.shared.update(savedItem!)
        try await Task.sleep(for: .seconds(2))

        let predicate = NSPredicate(format: "name == %@", "updatedName")
        let updatedCheckItem = await CloudKitManager.shared.fetchAll(TagModel.self, predicate: predicate)
        
        #expect(updatedCheckItem.contains{$0.name == "updatedName"})
        await CloudKitManager.shared.delete(updatedCheckItem.first!)
    }
    
    @Test func deleteTagModelSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let tagModel = TagModel(name: "deleteTest", color: .gray)
        var savedItem = await CloudKitManager.shared.create(tagModel)
        
        #expect(savedItem != nil)
        try await Task.sleep(for: .seconds(2))
        
        if let savedItem {
            let isDeleted = await CloudKitManager.shared.delete(savedItem)
            #expect(isDeleted)
        }
    }

}
