//
//  CheckItemDTO.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 28/08/26.
//

import Foundation
import CloudKit

/// A checklist item being edited in the chore form, before it is saved.
struct CheckItemDTO: Identifiable {
    /// Local identifier for SwiftUI lists.
    let id = UUID()
    /// The item's text.
    var name: String
    /// Whether the item is checked.
    var isDone: Bool

    /// Identifier of the original stored record, if this DTO is editing an existing checklist
    /// item. `nil` means the item hasn't been persisted yet.
    var originalRecordID: CKRecord.ID?

    /// Creates a draft item.
    /// - Parameters:
    ///   - name: The item's text.
    ///   - isDone: Whether it is checked.
    ///   - originalRecordID: The saved item it edits, or `nil` for a new item.
    init(name: String, isDone: Bool, originalRecordID: CKRecord.ID? = nil) {
        self.name = name
        self.isDone = isDone
        self.originalRecordID = originalRecordID
    }

    /// Creates a draft from an already-persisted checklist item, for the editing flow.
    init(from model: CheckItemModel) {
        self.name = model.name
        self.isDone = model.isDone
        self.originalRecordID = model.recordID
    }
}
