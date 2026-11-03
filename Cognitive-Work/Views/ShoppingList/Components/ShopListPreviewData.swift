//
//  ShopListPreviewData.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 08/10/26.
//

import Foundation
import CloudKit

/// Sample users, items and view models shared by every shopping list `#Preview`.
@MainActor
enum ShopListPreviewData {

    // MARK: - Users

    /// Sample housemate (the signed-in user in the previews).
    static let jones = makeUser("Jones")
    /// Sample housemate.
    static let isabela = makeUser("Isabela")
    /// Sample housemate.
    static let carol = makeUser("Carol")
    /// Sample housemate.
    static let anshu = makeUser("Anshu")

    /// Every sample housemate.
    static let users: [UserModel] = [jones, isabela, carol, anshu]

    /// A sample user with a fixed record ID.
    private static func makeUser(_ name: String) -> UserModel {
        let user = UserModel(name: name, tier: .tier1, ownerRecordName: "preview-\(name)")
        user.recordID = CKRecord.ID(recordName: "preview-user-\(name)")
        return user
    }

    // MARK: - Items

    /// A sample item with a fixed record ID. The parameters match ``ShopListItem``'s.
    static func makeItem(
        _ name: String,
        quantity: Int,
        unit: UnitMeasurement = .unit,
        value: Double? = nil,
        category: ShopItemCategory = .other,
        isBought: Bool = false,
        buyer: UserModel? = nil,
        users: [UserModel] = []
    ) -> ShopListItem {
        let item = ShopListItem(
            name: name,
            value: value,
            quantity: quantity,
            unitMeasurement: unit,
            isBought: isBought,
            category: category,
            relatedUsers: users.compactMap { user in
                user.recordID.map { CKRecord.Reference(recordID: $0, action: .none) }
            },
            buyerUser: buyer?.recordID.map { CKRecord.Reference(recordID: $0, action: .none) }
        )
        item.recordID = CKRecord.ID(recordName: "preview-item-\(UUID().uuidString)")
        return item
    }

    /// A pending item with price, three housemates and a short name.
    static var pendingItem: ShopListItem {
        makeItem("Amaciante", quantity: 2, value: 30.5, category: .cleaning, users: [jones, isabela, carol])
    }

    /// A checked-off item.
    static var boughtItem: ShopListItem {
        makeItem("Veja multiuso", quantity: 1, value: 12.9, category: .cleaning, isBought: true, users: [jones, isabela])
    }

    /// A long name, no price, no housemates.
    static var longNameItem: ShopListItem {
        makeItem("Molho de tomate artesanal com manjericão", quantity: 3, unit: .package, category: .food)
    }

    /// One pending item per category, to compare every tile and color.
    static var onePerCategory: [ShopListItem] {
        ShopItemCategory.allCases.map { category in
            makeItem(category.displayName, quantity: 1, value: 9.9, category: category, users: [jones, anshu])
        }
    }

    /// A realistic list: several categories, some bought.
    static var items: [ShopListItem] {
        [
            makeItem("Papel higiênico", quantity: 1, unit: .package, value: 24.9, category: .hygiene, users: [jones, isabela, carol]),
            makeItem("Detergente", quantity: 2, value: 5.8, category: .cleaning, users: [jones, isabela, carol]),
            makeItem("Amaciante", quantity: 2, value: 30.5, category: .cleaning, users: [isabela]),
            makeItem("Vassoura", quantity: 1, category: .home, users: [jones, isabela, carol]),
            makeItem("Ovos", quantity: 6, category: .food, users: [jones]),
            makeItem("Arroz", quantity: 5, unit: .kilogram, value: 28, category: .food, users: [jones, carol]),
            makeItem("Banana", quantity: 1, unit: .kilogram, category: .produce, users: [anshu]),
            makeItem("Suco de uva", quantity: 2, unit: .liter, category: .drinks, users: [carol, anshu]),
            makeItem("Ração", quantity: 1, unit: .package, value: 89.9, category: .pets, users: [jones]),
            makeItem("Veja multiuso", quantity: 1, value: 12.9, category: .cleaning, isBought: true, users: [jones, isabela, carol]),
            makeItem("Café", quantity: 500, unit: .gram, category: .food, isBought: true, users: [jones])
        ] + debtItems
    }

    /// Bought, priced items split among housemates: Jones owes Isabela and Carol, and is owed by Anshu.
    static var debtItems: [ShopListItem] {
        [
            makeItem("Pizza", quantity: 2, value: 45, category: .food, isBought: true, buyer: isabela, users: [jones, isabela, carol]),
            makeItem("Sabão em pó", quantity: 1, unit: .package, value: 42, category: .cleaning, isBought: true, buyer: isabela, users: [jones, isabela]),
            makeItem("Cerveja", quantity: 12, value: 5.5, category: .drinks, isBought: true, buyer: carol, users: [jones, carol]),
            makeItem("Pão", quantity: 6, value: 3, category: .food, isBought: true, buyer: jones, users: [jones, anshu, carol]),
            makeItem("Queijo", quantity: 1, unit: .kilogram, value: 55, category: .food, isBought: true, buyer: jones, users: [jones, anshu])
        ]
    }

    // MARK: - View models

    /// A view model already loaded with ``items``.
    static var populatedViewModel: ShopListViewModel {
        ShopListViewModel(previewItems: items, houseUsers: users, currentUser: jones)
    }

    /// A view model for the pending payments screen, with debts in both directions.
    static var debtsViewModel: PendingPaymentsViewModel {
        PendingPaymentsViewModel(shopList: populatedViewModel)
    }

    /// A pending payments screen where nobody owes anything.
    static var noDebtsViewModel: PendingPaymentsViewModel {
        PendingPaymentsViewModel(shopList: emptyViewModel)
    }

    /// A view model already loaded with no items.
    static var emptyViewModel: ShopListViewModel {
        ShopListViewModel(previewItems: [], houseUsers: users, currentUser: jones)
    }
}
