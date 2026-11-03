//
//  ShopListItem.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 27/08/26.
//

import Foundation
import CloudKit

/// One item of the house's shopping list (a ``ShopListModel``).
///
/// Besides what to buy, it keeps who bought it, who it was for and who already paid their share,
/// so the app can split the cost between housemates (see ``DebtCalculator``).
@Observable
class ShopListItem: CloudKitSyncable, Identifiable {
    /// Identifier used before the item is saved (when it has no `recordID`).
    private let localID = UUID().uuidString

    /// Identifier for SwiftUI lists: the record name once saved, a local ID before that.
    var id: String {
        recordID?.recordName ?? localID
    }

    /// The CloudKit record type.
    static var recordType: String = "ShopListItem"

    /// The CloudKit record ID. `nil` until the model is saved.
    var recordID: CKRecord.ID?

    /// The item's name.
    var name: String

    /// Price of ONE unit (see ``totalValue``).
    var value: Double?

    /// How much to buy, in ``unitMeasurement``.
    var quantity: Int

    /// The unit ``quantity`` is expressed in (grams, liters, individual pieces, …).
    var unitMeasurement: UnitMeasurement

    /// Whether the item has already been purchased.
    var isBought: Bool

    /// The aisle the item belongs to; the list groups by it.
    var category: ShopItemCategory

    /// When the item was added.
    private(set) var createdAt: Date

    /// When the item was last marked bought
    var boughtAt: Date?

    /// The list this item belongs to (the record's `parent`).
    var listRecordID: CKRecord.ID?

    /// The user who actually bought the item.
    private var buyerUserReference: CKRecord.Reference?

    /// Other users who will use/share this item, e.g. to split its cost.
    var relatedUsersReference: [CKRecord.Reference]?

    /// The user who added this item to the list.
    private var addedByUserReference: CKRecord.Reference?

    /// Tags attached to the item (not used by the app yet).
    private var tagsReference: [CKRecord.Reference]?

    /// Housemates who already paid the buyer their share of this item (see ``DebtCalculator``).
    private var settledUsersReference: [CKRecord.Reference]?

    /// Whether a price was informed (an item without one can't be split between housemates).
    var hasPrice: Bool { (value ?? 0) > 0 }

    /// ``value`` is the price of one unit, so the whole purchase costs `value × quantity`.
    var totalValue: Double? {
        guard let value, value > 0 else { return nil }
        return value * Double(quantity)
    }

    /// The housemates the item is for, as record ids.
    var consumerRecordIDs: [CKRecord.ID] {
        var seen = Set<CKRecord.ID>()
        return (relatedUsersReference ?? []).map(\.recordID).filter { seen.insert($0).inserted }
    }

    /// The housemates who already paid their share of this item.
    var settledUserIDs: Set<CKRecord.ID> {
        Set((settledUsersReference ?? []).map(\.recordID))
    }

    /// Who bought the item, as a record id (for resolving against an already-fetched pool).
    var buyerRecordID: CKRecord.ID? { buyerUserReference?.recordID }

    /// Who added the item, as a record id.
    var addedByRecordID: CKRecord.ID? { addedByUserReference?.recordID }

    /// The member who bought the item, fetched from CloudKit.
    var buyerUser: UserModel? {
        get async {
            if let buyerUserReference {
                return await CloudKitManager.shared.fetchRecordsByRecordReference(for: UserModel.self, recordReferences: [buyerUserReference])?.first
            }
            return nil
        }
    }

    /// The members the item is for, fetched from CloudKit.
    var relatedUsers: [UserModel] {
        get async {
            if let relatedUsersReference {
                return await CloudKitManager.shared.fetchRecordsByRecordReference(for: UserModel.self, recordReferences: relatedUsersReference) ?? []
            }
            return []
        }
    }

    /// Resolves ``relatedUsers`` against an already-fetched pool of users (e.g.
    /// ``ShopListViewModel/houseUsers``) instead of making a network request.
    ///
    /// - Parameter pool: Users to search, typically every house member.
    /// - Returns: The subset of `pool` referenced by this item.
    func relatedUsers(in pool: [UserModel]) -> [UserModel] {
        guard let relatedUsersReference else { return [] }
        let ids = Set(relatedUsersReference.map { $0.recordID })
        return pool.filter { user in
            guard let recordID = user.recordID else { return false }
            return ids.contains(recordID)
        }
    }

    /// Who added this item to the list. See ``addedByUserReference``.
    var addedByUser: UserModel? {
        get async {
            if let addedByUserReference {
                return await CloudKitManager.shared.fetchRecordsByRecordReference(for: UserModel.self, recordReferences: [addedByUserReference])?.first
            }
            return nil
        }
    }

    /// The item's tags, fetched from CloudKit.
    var tags: [TagModel] {
        get async {
            if let tagsReference {
                return await CloudKitManager.shared.fetchRecordsByRecordReference(for: TagModel.self, recordReferences: tagsReference) ?? []
            }
            return []
        }
    }

    /// Creates a model from a CloudKit record.
    ///
    /// - Parameter record: The record to decode.
    /// - Returns: `nil` when a required field is missing or has the wrong type, or when the
    ///   stored unit/priority isn't a known case.
    required init?(record: CKRecord) {
        guard
            let name = record["name"] as? String,
            let quantity = record["quantity"] as? Int,
            let unitMeasurement = record["unitMeasurement"] as? String,
            let isBought = record["isBought"] as? Bool
        else {
            return nil
        }

        self.recordID = record.recordID

        self.name = name
        self.value = record["value"] as? Double
        self.quantity = quantity
        self.unitMeasurement = UnitMeasurement(rawValue: unitMeasurement) ?? .gram
        self.isBought = isBought
        self.category = ShopItemCategory(rawValue: record["category"] as? String ?? "") ?? .other
        self.createdAt = record.creationDate ?? Date()
        self.boughtAt = record["boughtAt"] as? Date
        self.listRecordID = record.parent?.recordID
        self.buyerUserReference = record["buyerUser"] as? CKRecord.Reference
        self.relatedUsersReference = record["relatedUsers"] as? [CKRecord.Reference]
        self.addedByUserReference = record["addedByUser"] as? CKRecord.Reference
        self.tagsReference = record["tags"] as? [CKRecord.Reference]
        self.settledUsersReference = record["settledUsers"] as? [CKRecord.Reference]
    }

    /// Creates a new, unsaved shopping list item.
    ///
    /// - Parameters:
    ///   - name: Label shown to the user.
    ///   - value: Estimated or actual price, when known.
    ///   - quantity: How many units to buy.
    ///   - unitMeasurement: The unit `quantity` is expressed in.
    ///   - isBought: Whether the item starts already purchased. Defaults to `false`.
    ///   - category: The aisle the item belongs to.
    ///   - relatedUsers: Other users who will use/share this item.
    ///   - addedByUser: The user adding this item, for gamification credit.
    ///   - buyerUser: The user who bought it, when it is created already bought.
    ///   - recordID: The record ID to use, when it is already known.
    init(
        name: String,
        value: Double? = nil,
        quantity: Int,
        unitMeasurement: UnitMeasurement,
        isBought: Bool = false,
        category: ShopItemCategory = .other,
        relatedUsers: [CKRecord.Reference]? = nil,
        addedByUser: CKRecord.Reference? = nil,
        buyerUser: CKRecord.Reference? = nil,
        recordID: CKRecord.ID? = nil
    ) {
        self.recordID = recordID
        self.name = name
        self.value = value
        self.quantity = quantity
        self.unitMeasurement = unitMeasurement
        self.isBought = isBought
        self.category = category
        self.createdAt = Date()
        self.relatedUsersReference = relatedUsers
        self.addedByUserReference = addedByUser
        self.buyerUserReference = buyerUser
    }

    /// Writes this model's values into a CloudKit record.
    ///
    /// - Parameter record: The record to populate.
    ///
    /// > Note: `nil` relationships are skipped rather than written, preserving whatever is
    /// > already on the server (same convention as ``ChoreModel/populate(record:)``).
    func populate(record: CKRecord) {
        record["name"] = name
        record["value"] = value
        record["quantity"] = quantity
        record["unitMeasurement"] = unitMeasurement.rawValue
        record["isBought"] = isBought
        record["category"] = category.rawValue
        record["boughtAt"] = boughtAt
        
        if let buyerUserReference {
            record["buyerUser"] = buyerUserReference
        }
        if let relatedUsersReference {
            record["relatedUsers"] = relatedUsersReference
        }
        if let addedByUserReference {
            record["addedByUser"] = addedByUserReference
        }
        if let tagsReference {
            record["tags"] = tagsReference
        }
        if let settledUsersReference {
            // CloudKit refuses an empty list for a field it doesn't know yet, so "nobody" is
            // stored as no value at all (which also clears an old list on a re-purchase).
            record["settledUsers"] = settledUsersReference.isEmpty ? nil : settledUsersReference
        }
    }

    /// Flips ``isBought`` and persists the change
    @discardableResult
    func toggle() async -> Bool {
        let previousBoughtAt = boughtAt
        isBought.toggle()
        // Keep the purchase date in step with the flag.
        boughtAt = isBought ? Date() : nil
        // Optimistic update, rolled back if CloudKit rejects it (it used to stay flipped on
        // screen even though the change was never saved).
        guard await CloudKitManager.shared.update(self) else {
            isBought.toggle()
            boughtAt = previousBoughtAt
            return false
        }
        return true
    }

    /// Marks the item bought by `user`, recording ``isBought``, ``buyerUserReference`` and, when
    /// given, the price paid, in a single update instead of separate writes.
    ///
    /// - Parameters:
    ///   - user: The user who bought the item.
    ///   - value: The price paid, when it wasn't known before.
    @discardableResult
    func markBought(by user: UserModel, value paid: Double? = nil) async -> Bool {
        guard let buyerID = user.recordID else { return false }
        let previousBuyer = buyerUserReference
        let previousValue = value
        let previousSettled = settledUsersReference
        let previousBoughtAt = boughtAt

        isBought = true
        boughtAt = Date()
        buyerUserReference = CKRecord.Reference(recordID: buyerID, action: .none)
        // A new purchase starts with nobody having paid their share yet.
        settledUsersReference = []
        if let paid { value = paid }

        guard await CloudKitManager.shared.update(self) else {
            isBought = false
            buyerUserReference = previousBuyer
            value = previousValue
            settledUsersReference = previousSettled
            boughtAt = previousBoughtAt
            return false
        }
        return true
    }

    /// Records, in memory only, that `debtorID` paid their share (used by previews and as the
    /// first step of ``markSettled(for:)``).
    func settleLocally(for debtorID: CKRecord.ID) {
        guard !settledUserIDs.contains(debtorID) else { return }
        settledUsersReference = (settledUsersReference ?? []) + [CKRecord.Reference(recordID: debtorID, action: .none)]
    }

    /// Records that `debtorID` paid their share of this item, and persists it. Rolled back if
    /// CloudKit rejects the update.
    @discardableResult
    func markSettled(for debtorID: CKRecord.ID) async -> Bool {
        guard !settledUserIDs.contains(debtorID) else { return true }
        let previous = settledUsersReference

        settleLocally(for: debtorID)

        guard let record = await CloudKitManager.shared.fetchRecord(for: self) else {
            settledUsersReference = previous
            return false
        }

        var merged = record["settledUsers"] as? [CKRecord.Reference] ?? []
        if !merged.contains(where: { $0.recordID == debtorID }) {
            merged.append(CKRecord.Reference(recordID: debtorID, action: .none))
        }
        record["settledUsers"] = merged

        guard await CloudKitManager.shared.update(record: record) else {
            settledUsersReference = previous
            return false
        }
        settledUsersReference = merged
        return true
    }

    /// Applies edited field values and persists them in one update. Mirrors
    /// ``ChoreModel/save(from:targetAssignments:)``: the editable fields live on this method
    /// rather than being set directly by callers, since ``relatedUsersReference`` is private.
    ///
    /// - Parameters:
    ///   - name: Label shown to the user.
    ///   - value: Estimated or actual price, when known.
    ///   - quantity: How many units to buy.
    ///   - unitMeasurement: The unit `quantity` is expressed in.
    ///   - relatedUsers: Other users who will use/share this item.
    /// - Returns: `true` when the update reached CloudKit.
    @discardableResult
    func update(
        name: String,
        value: Double?,
        quantity: Int,
        unitMeasurement: UnitMeasurement,
        category: ShopItemCategory,
        relatedUsers: [UserModel]
    ) async -> Bool {
        self.category = category
        self.name = name
        self.value = value
        self.quantity = quantity
        self.unitMeasurement = unitMeasurement
        self.relatedUsersReference = relatedUsers.compactMap { user -> CKRecord.Reference? in
            guard let recordID = user.recordID else { return nil }
            return CKRecord.Reference(recordID: recordID, action: .none)
        }
        return await CloudKitManager.shared.update(self)
    }
}
