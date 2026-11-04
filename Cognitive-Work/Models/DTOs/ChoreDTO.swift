//
//  ChoreDTO.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 26/08/26.
//

import SwiftUI
import CloudKit

/// A chore as presented during onboarding or editing, before it is persisted to CloudKit.
///
/// This type carries only what the selection screens need, keeping the UI free
/// from direct CloudKit mutations. Once the user confirms the selection, the picked
/// instances are mapped into ``ChoreModel`` records.
@Observable
final class ChoreDTO: Identifiable {

    // MARK: - Properties

    /// Local identifier for SwiftUI lists.
    let id = UUID()
    
    /// Identifier of the original stored record, if this DTO is editing an existing chore.
    var originalRecordID: CKRecord.ID?

    /// Name shown to the user.
    var name: String

    /// Short explanation of what the chore involves.
    var description: String

    /// How often the chore repeats.
    var frequency: Recurrence

    /// Estimated time to complete the chore, in minutes.
    var duration: Double

    /// Priority level used to sort and highlight the chore.
    var priorityTag: PriorityTag

    /// Whether the user marked this chore to be split between the residents.
    var isSelected: Bool = false
    
    /// Whether every member of the house can see and claim the chore.
    var isPublic: Bool
    
    /// The SF Symbol name used as the chore's icon.
    var symbolName: String
    
    /// Reference to the room this chore belongs to.
    var roomDTO: RoomDTO
    
    /// The saved room the chore belongs to. Setting it also updates ``roomReference``.
    var room: RoomModel? {
        didSet {
            if let roomRecordID = room?.recordID {
                roomReference = CKRecord.Reference(recordID: roomRecordID, action: .none)
            } else {
                roomReference = nil
            }
        }
    }
    /// Reference to ``room``, ready to be saved in the chore's record.
    var roomReference: CKRecord.Reference?
    
    /// Every user assigned to this chore or occurrence.
    var responsibleUsers: [UserModel] = []
    
    /// The checklist items for this chore.
    var checklist: [CheckItemDTO] = []
    
    /// Whether the chore currently has a checklist enabled in the UI.
    var hasChecklist: Bool = false
    
    /// The chore's occurrences, kept when editing so they are not lost on save.
    var dailyAssignmentsReference: [CKRecord.Reference]? = nil
    
    /// Returns CloudKit references for all selected responsible users.
    var responsibleUserReferences: [CKRecord.Reference] {
        responsibleUsers.compactMap { user in
            guard let id = user.recordID else { return nil }
            return CKRecord.Reference(recordID: id, action: .none)
        }
    }

    // MARK: - Initialization
    
    /// Creates a new, empty chore draft for the creation flow.
    init() {
        self.name = ""
        self.description = ""
        self.frequency = .weekly
        self.duration = 30
        self.priorityTag = .medium
        self.isPublic = false
        self.symbolName = "toilet"
        self.roomDTO = RoomDTO(name: "Banheiro", symbol: "toilet")
    }

    /// Creates a chore draft from an existing ``ChoreModel`` for the editing flow.
    init(
        from model: ChoreModel,
        users: [UserModel],
        checklist: [CheckItemDTO],
        room: RoomModel? = nil
    ) {
        self.originalRecordID = model.recordID
        self.name = model.name
        self.description = model.description
        self.frequency = model.frequency
        self.duration = model.duration
        self.priorityTag = model.priorityTag
        self.isPublic = model.isPublic
        self.symbolName = model.symbolName
        
        self.responsibleUsers = users
        self.checklist = checklist
        self.hasChecklist = !checklist.isEmpty
        
        self.dailyAssignmentsReference = model.dailyAssignmentsReference
        
        self.room = room
        if let roomRecordID = room?.recordID {
            self.roomReference = CKRecord.Reference(recordID: roomRecordID, action: .none)
        }
        self.roomDTO = RoomDTO(name: room?.name ?? "NoDTO", symbol: room?.symbol ?? "xmark")
    }

    /// Creates a chore for the onboarding selection screens.
    init(
        name: String,
        description: String,
        frequency: Recurrence,
        duration: Double,
        priorityTag: PriorityTag,
        room: RoomDTO
    ) {
        self.name = name
        self.description = description
        self.frequency = frequency
        self.duration = duration
        self.priorityTag = priorityTag
        self.isPublic = false
        self.symbolName = "toilet"
        self.roomDTO = room
    }
}

extension ChoreDTO {
    /// Whether every optional detail was filled in. Creating such a chore earns bonus points.
    var hasFullDetails: Bool {
        room != nil
        && priorityTag != .undefined
        && frequency != .undefined
        && duration > 0
        && !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
