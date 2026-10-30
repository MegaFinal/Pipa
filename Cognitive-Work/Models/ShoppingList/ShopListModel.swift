//
//  ShopListModel.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 18/09/26.
//

import Foundation
import CloudKit

/// A named shopping list belonging to a house, holding a collection of ``ShopListItem`` entries.
@Observable
class ShopListModel: CloudKitSyncable, Identifiable {
    /// Identifier used before the list is saved (when it has no `recordID`).
    private let localID = UUID().uuidString

    /// Identifier for SwiftUI lists: the record name once saved, a local ID before that.
    var id: String {
        recordID?.recordName ?? localID
    }

    /// The CloudKit record type.
    static var recordType: String = "ShopListModel"

    /// The CloudKit record ID. `nil` until the model is saved.
    var recordID: CKRecord.ID?

    /// The list's name.
    var name: String

    /// Legacy: the list used to keep an array of references to its items.
    private var itemsReference: [CKRecord.Reference]?

    /// The house this list belongs to.
    var houseReference: CKRecord.Reference?

    /// This list's items, queried from CloudKit by parent and sorted by creation date.
    var items: [ShopListItem] {
        get async {
            let all = await CloudKitManager.shared.fetchAll(ShopListItem.self)
            return belonging(to: all)
        }
    }

    /// Keeps the items whose parent is this list, without duplicates, oldest first.
    func belonging(to candidates: [ShopListItem]) -> [ShopListItem] {
        var seen = Set<String>()
        return candidates
            .filter { $0.listRecordID == nil || $0.listRecordID == recordID }
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// The house this list belongs to, fetched from CloudKit. `nil` if not set or not found.
    var house: HouseModel? {
        get async {
            if let houseReference {
                return await CloudKitManager.shared.fetchRecordsByRecordReference(for: HouseModel.self, recordReferences: [houseReference])?.first
            }
            return nil
        }
    }

    /// Creates a model from a CloudKit record.
    ///
    /// - Parameter record: The record to decode.
    /// - Returns: `nil` when `name` is missing.
    required init?(record: CKRecord) {
        guard let name = record["name"] as? String else {
            return nil
        }

        self.recordID = record.recordID
        self.name = name
        self.itemsReference = record["items"] as? [CKRecord.Reference]
        self.houseReference = record["house"] as? CKRecord.Reference
    }

    /// Creates a new, unsaved shopping list.
    ///
    /// - Parameters:
    ///   - name: Name shown to the user.
    ///   - items: Legacy references to the list's items (new items are linked by parent instead).
    ///   - house: The owning house.
    ///   - recordID: The record ID to use, when it is already known.
    ///   - house: The owning house.
    init(
        name: String,
        items: [CKRecord.Reference]? = nil,
        house: CKRecord.Reference? = nil,
        recordID: CKRecord.ID? = nil
    ) {
        self.recordID = recordID
        self.name = name
        self.itemsReference = items
        self.houseReference = house
    }

    /// Writes this model's values into a CloudKit record.
    ///
    /// - Parameter record: The record to populate.
    func populate(record: CKRecord) {
        record["name"] = name
        if let itemsReference {
            record["items"] = itemsReference
        }
        if let houseReference {
            record["house"] = houseReference
        }
    }

    // MARK: - Items

    /// Saves `item` as a child of this list.
    ///
    /// - Parameter item: The item to save (not yet saved — no `recordID` of its own).
    /// - Returns: The saved item, with its `recordID` set, or `nil` on failure.
    @discardableResult
    func addItem(_ item: ShopListItem) async -> ShopListItem? {
        guard let recordID else {
            CloudKitManager.shared.errorMessage = "Failed to add item: list missing recordID"
            return nil
        }

        let parentReference = CKRecord.Reference(recordID: recordID, action: .none)

        guard let created = await CloudKitManager.shared.create(item, zoneID: recordID.zoneID, parent: parentReference) else {
            return nil
        }
        created.listRecordID = recordID
        return created
    }

    /// Deletes `item`.
    @discardableResult
    func removeItem(_ item: ShopListItem) async -> Bool {
        guard item.recordID != nil else { return false }
        return await CloudKitManager.shared.delete(item)
    }
}
