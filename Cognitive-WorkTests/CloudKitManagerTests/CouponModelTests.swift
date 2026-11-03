//
//  BadgeModelTests 2.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 27/08/26.
//

import Testing
import Foundation
import CloudKit
@testable import Cognitive_Work

@MainActor
struct CouponModelTests {

    @Test func createCouponSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let placeholderReference = CKRecord.Reference(recordID: CKRecord.ID(recordName: "UserModel"), action: .none)
        let coupon = CouponModel(name: "CreatTestCoupon",
                                 isOnSale: false, price: 0,
                                 tier: .tier1,
                                 currentUser: placeholderReference,
                                 lastUser: placeholderReference,
                                 task: placeholderReference)
        let savedItem = await CloudKitManager.shared.create(coupon)
        
        print("ERRO:", CloudKitManager.shared.errorMessage as Any)
        
        #expect(savedItem != nil)
        await CloudKitManager.shared.delete(savedItem!)
    }
    
    @Test func fetchAllCouponsSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let coupon = CouponModel(name: "CreatTestCoupon", isOnSale: false, price: 0, tier: .tier1)
        let savedItem = await CloudKitManager.shared.create(coupon)
        #expect(savedItem != nil)
        
        let items = await CloudKitManager.shared.fetchAll(CouponModel.self)
        print("ERRO:", CloudKitManager.shared.errorMessage as Any)
        
        #expect(!items.isEmpty)
        await CloudKitManager.shared.delete(savedItem!)
    }
    
    @Test func fetchCreatedCouponsWithPredicateSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let coupon = CouponModel(name: "fetchWithPredicateTestCoupon", isOnSale: false, price: 0, tier: .tier1)
        let itemSaved = await CloudKitManager.shared.create(coupon)
        #expect(itemSaved != nil)
        
        try await Task.sleep(for: .seconds(2))
        
        let predicate = NSPredicate(format: "name == %@", "fetchWithPredicateTestCoupon")
        let item = await CloudKitManager.shared.fetchAll(CouponModel.self, predicate: predicate)
        print("Error:", CloudKitManager.shared.errorMessage as Any)
        
        #expect(item.contains { $0.name == "fetchWithPredicateTestCoupon" })
        
        if let savedItem = itemSaved {
            await CloudKitManager.shared.delete(savedItem)
        }
    }
    
    @Test func updateCouponsSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let coupon = CouponModel(name: "updateCouponTest", isOnSale: false, price: 0, tier: .tier1)
        var savedItem = await CloudKitManager.shared.create(coupon)
        #expect(savedItem != nil)
        
        try await Task.sleep(for: .seconds(2))
        
        savedItem?.name = "updatedName"
        await CloudKitManager.shared.update(savedItem!)
        try await Task.sleep(for: .seconds(2))

        let predicate = NSPredicate(format: "name == %@", "updatedName")
        let updatedCheckItem = await CloudKitManager.shared.fetchAll(CouponModel.self, predicate: predicate)
        
        #expect(updatedCheckItem.contains{$0.name == "updatedName"})
        await CloudKitManager.shared.delete(updatedCheckItem.first!)
    }
    
    @Test func deleteBCouponSuccessfullyTest() async throws {
        await CloudKitManager.shared.createZoneIfNeeded()
        
        let coupon = CouponModel(name: "deleteCouponTest", isOnSale: false, price: 0, tier: .tier1)
        let itemSaved = await CloudKitManager.shared.create(coupon)
        
        #expect(itemSaved != nil)
        try await Task.sleep(for: .seconds(2))
        
        let isDeleted = await CloudKitManager.shared.delete(itemSaved!)
        #expect(isDeleted)
    }

}
