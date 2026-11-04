//
//  CheckItemModel.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 12/08/26.
//

import Foundation
import CloudKit

/// A single entry in a chore's checklist.
@Observable
class CheckItemModel: CloudKitSyncable, Identifiable {
    /// Identifier for SwiftUI lists: the record name once saved, otherwise a new random ID.
    var id: String {
        recordID?.recordName ?? UUID().uuidString
    }
    
    /// CloudKit record type backing this model.
    static var recordType: String = "CheckItemModel"
    
    /// Identifier of the stored record, or `nil` before the item is saved.
    var recordID: CKRecord.ID?
    
    /// Label shown to the user.
    var name: String
    
    /// Whether the item has been checked off.
    var isDone: Bool
    
    /// Creates a model from a CloudKit record.
    ///
    /// - Parameter record: The record to decode.
    /// - Returns: `nil` when a required field is missing or has the wrong type.
    required init?(record: CKRecord) {
        guard
            let name = record["name"] as? String,
            let isDone = record["isDone"] as? Bool
        else {
            return nil
        }
        
        self.recordID = record.recordID
        self.name = name
        self.isDone = isDone
    }
    
    /// Creates a new, unsaved checklist item.
    ///
    /// - Parameters:
    ///   - name: Label shown to the user.
    ///   - isDone: Whether the item starts checked off.
    init(name: String, isDone: Bool) {
        self.name = name
        self.isDone = isDone
    }
    
    /// Writes this model's values into a CloudKit record.
    ///
    /// - Parameter record: The record to populate.
    func populate(record: CKRecord) {
        record["name"] = name
        record["isDone"] = isDone
    }
    
    /// Checks or unchecks the item and saves the change in CloudKit.
    func toggle() async {
        self.isDone.toggle()
        await CloudKitManager.shared.update(self)
    }
    
    /// Persists a checklist DTO, creating or updating each item as needed.
    ///
    /// Every new item is created inside the same record zone as `parentReference` and adopts it
    /// as its CloudKit parent, so a checklist item never outlives the chore that owns it.
    ///
    /// - Parameters:
    ///   - draftItems: The checklist as currently edited in the UI. Items with a blank name are
    ///     skipped, since they represent rows the user started but never filled in.
    ///   - parentReference: Reference to the owning chore, expected to use `action: .deleteSelf`
    ///     so deleting the chore cascades to every checklist item that references it.
    /// - Returns: A reference to every checklist item that saved successfully, suitable for
    ///   storing on `ChoreModel.checkListReference`. Items that failed to save are omitted rather
    ///   than failing the whole sync; check ``CloudKitManager/errorMessage`` for details.
    static func sync(
        from draftItems: [CheckItemDTO],
        parent parentReference: CKRecord.Reference
    ) async -> [CKRecord.Reference] {
        var savedItemReferences: [CKRecord.Reference] = []

        for draftItem in draftItems {
            let trimmedName = draftItem.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { continue }

            if let existingRecordID = draftItem.originalRecordID {
                let updatedCheckItem = CheckItemModel(name: trimmedName, isDone: draftItem.isDone)
                updatedCheckItem.recordID = existingRecordID

                await CloudKitManager.shared.update(updatedCheckItem)
                savedItemReferences.append(
                    CKRecord.Reference(recordID: existingRecordID, action: .none)
                )
            } else {
                let newCheckItem = CheckItemModel(name: trimmedName, isDone: draftItem.isDone)

                guard
                    let createdCheckItem = await CloudKitManager.shared.create(
                        newCheckItem,
                        zoneID: parentReference.recordID.zoneID,
                        parent: parentReference
                    ),
                    let createdRecordID = createdCheckItem.recordID
                else { continue }

                savedItemReferences.append(
                    CKRecord.Reference(recordID: createdRecordID, action: .none)
                )
            }
        }

        return savedItemReferences
    }
    
    /// Deletes the checklist items that were in `previous` but are no longer in `current`.
    ///
    /// Best effort: if it fails, the items stay in CloudKit but no chore references them.
    static func deleteRemoved(
        from previous: [CKRecord.Reference],
        keeping current: [CKRecord.Reference]
    ) async {
        let keptIDs = Set(current.map(\.recordID))
        let removedIDs = previous.map(\.recordID).filter { !keptIDs.contains($0) }
        guard let zoneID = removedIDs.first?.zoneID else { return }
        
        await CloudKitManager.shared.delete(recordIDs: removedIDs, zoneID: zoneID)
    }
}
