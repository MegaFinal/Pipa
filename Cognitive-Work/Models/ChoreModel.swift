//
//  ChoreModel.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 12/08/26.
//

import Foundation
import SwiftUI
import CloudKit

/// A household task assigned to one or more users and belonging to a room.
@Observable
class ChoreModel: CloudKitSyncable, Identifiable {
    /// Local identifier for SwiftUI lists.
    var id: UUID = UUID()
    
    /// CloudKit record type backing this model.
    static let recordType = "ChoreModel"
    
    /// Every field except ``image``.
    static let listDesiredKeys: [CKRecord.FieldKey]? = [
        "name", "description", "isDone", "dueDate", "frequency", "shouldBeIncluded",
        "duration", "isPublic", "isLate", "weight", "priorityTag",
        "checkList", "currentResponsible", "allResponsibleUsers", "room", "dailyAssignment",
        "userThatHaveDone"
    ]
    
    /// Identifier of the stored record, or `nil` before the chore is saved.
    var recordID: CKRecord.ID?
    
    /// Title shown to the user.
    var name: String
    
    /// Free-form details about how the chore should be done.
    var description: String
    
    /// Whether the chore is done. For recurring chores, each day's occurrence also has its own
    /// done flag (``RecurrentAssignmentModel/isCompleted``).
    var isDone: Bool
    
    /// When the chore is next due, or `nil` when it has no deadline.
    var dueDate: Date?
    
    /// How often the chore repeats.
    var frequency: Recurrence
    
    /// Expected time to complete the chore, in minutes.
    var duration: Double
    
    /// Whether every member of the house can see and claim the chore.
    var isPublic: Bool
    
    /// Whether the chore is past its ``dueDate``.
    var isLate: Bool = false
    
    /// Effort score used to balance workload between users.
    var weight: Int = 0
    
    /// Priority level shown in the UI.
    var priorityTag: PriorityTag
    
    /// For monthly chores: whether the chore goes into the next division. It flips at every
    /// division, so a monthly chore appears every other cycle.
    var shouldBeIncluded: Bool?
    
    /// Optional illustrative image.
    var image: Data?
    
    /// SF Symbol name of the chore's icon.
    var symbolName: String = "toilet"
    
    /// References to the chore's ``CheckItemModel`` entries.
    var checkListReference: [CKRecord.Reference]?
    
    /// The user currently responsible for the chore.
    var currentResponsibleReference: CKRecord.Reference?
    
    /// Every user in the rotation for this chore.
    var allResponsibleUsersReference: [CKRecord.Reference]?
    
    /// The room this chore belongs to.
    var roomReference: CKRecord.Reference?
    
    /// References to the chore's occurrences (one per day it happens in the current division).
    var dailyAssignmentsReference: [CKRecord.Reference]?
    
    /// The member who checked the chore off. `nil` while not done.
    var userThatHaveDoneReference: CKRecord.Reference?
    
    /// ID of the matching event in the user's Apple Calendar, when calendar sync is on.
    var calendarEventIdentifier: String?
    
    /// Blocks a second toggle while the first one is still being saved.
    @ObservationIgnored
    private var isUpdating = false
    
    /// Set when the record still stores ``duration`` in seconds; see
    /// ``migrateDurationsToMinutesIfNeeded(_:)``.
    @ObservationIgnored
    private(set) var needsDurationMigration = false
    
    /// The chore's checklist items, fetched from CloudKit.
    var checkList: [CheckItemModel] {
        get async {
            if let checkListReference {
                return await CloudKitManager.shared.fetchRecordsByRecordReference(for: CheckItemModel.self, recordReferences: checkListReference) ?? []
            }
            return []
        }
    }
    
    /// The member currently responsible for the chore, fetched from CloudKit.
    var currentResponsible: UserModel? {
        get async {
            if let currentResponsibleReference {
                return await CloudKitManager.shared.fetchRecordsByRecordReference(for: UserModel.self, recordReferences: [currentResponsibleReference])?.first
            }
            return nil
        }
    }
    
    /// Every member in the chore's rotation, fetched from CloudKit.
    var allResponsibleUsers: [UserModel] {
        get async {
            if let allResponsibleUsersReference {
                return await CloudKitManager.shared.fetchRecordsByRecordReference(for: UserModel.self, recordReferences: allResponsibleUsersReference) ?? []
            }
            return []
        }
    }
    
    /// The chore's room, fetched from CloudKit.
    var room: RoomModel? {
        get async {
            if let roomReference {
                return await CloudKitManager.shared.fetchRecordsByRecordReference(for: RoomModel.self, recordReferences: [roomReference])?.first
            }
            return nil
        }
    }
    
    /// The chore's occurrences, fetched from CloudKit.
    var dailyAssignments: [RecurrentAssignmentModel] {
        get async {
            if let dailyAssignmentsReference {
                return await CloudKitManager.shared.fetchRecordsByRecordReference(for: RecurrentAssignmentModel.self, recordReferences: dailyAssignmentsReference) ?? []
            }
            return []
        }
    }
    
    /// The member who checked the chore off, fetched from CloudKit.
    var userThatHaveDone: UserModel? {
        get async {
            if let userThatHaveDoneReference {
                return await CloudKitManager.shared.fetchRecordsByRecordReference(for: UserModel.self, recordReferences: [userThatHaveDoneReference])?.first
            }
            return nil
        }
    }
    
    /// How hard the chore is: priority + frequency + duration points.
    ///
    /// Used to price and rank its coupon (see ``CouponModel/tier(forScore:)``).
    var score: Int {
        return priorityTag.scoreValue + frequency.scoreValue + TimeScore.getPoints(time: duration)
    }
    
    /// Creates a model from a CloudKit record.
    ///
    /// - Parameter record: The record to decode.
    /// - Returns: `nil` when a required field is missing, has the wrong type, or holds an
    ///   unknown ``Recurrence`` or ``PriorityTag`` value.
    required init?(record: CKRecord) {
        guard
            let name = record["name"] as? String,
            let description = record["description"] as? String,
            let isDone = record["isDone"] as? Bool,
            let frequencyRaw = record["frequency"] as? String,
            let frequency = Recurrence(rawValue: frequencyRaw),
            let duration = record["duration"] as? TimeInterval,
            let isPublic = record["isPublic"] as? Bool,
            let isLate = record["isLate"] as? Bool,
            let weight = record["weight"] as? Int,
            let priorityTagRaw = record["priorityTag"] as? String,
            let priorityTag = PriorityTag(rawValue: priorityTagRaw)
        else {
            return nil
        }
        
        self.recordID = record.recordID
        
        self.name = name
        self.description = description
        self.isDone = isDone
        self.dueDate = record["dueDate"] as? Date
        self.frequency = frequency
        self.shouldBeIncluded = (record["shouldBeIncluded"] as? Int).map { $0 != 0 }
        if Self.isLegacySecondsDuration(duration) {
            self.duration = duration / 60
            self.needsDurationMigration = true
        } else {
            self.duration = duration
        }
        self.isPublic = isPublic
        self.isLate = isLate
        self.weight = weight
        self.priorityTag = priorityTag
        self.image = record["image"] as? Data
        self.checkListReference = record["checkList"] as? [CKRecord.Reference]
        self.currentResponsibleReference = record["currentResponsible"] as? CKRecord.Reference
        self.allResponsibleUsersReference = record["allResponsibleUsers"] as? [CKRecord.Reference]
        self.roomReference = record["room"] as? CKRecord.Reference
        self.dailyAssignmentsReference = record["dailyAssignment"] as? [CKRecord.Reference]
        self.userThatHaveDoneReference = record["userThatHaveDone"] as? CKRecord.Reference
        self.calendarEventIdentifier = record["calendarEventIdentifier"] as? String
    }
    
    /// Creates a new, unsaved chore.
    ///
    /// Relationship parameters are usually filled in after the related records exist.
    init(
        name: String,
        description: String,
        isDone: Bool = false,
        dueDate: Date? = nil,
        frequency: Recurrence,
        duration: Double,
        isPublic: Bool,
        isLate: Bool = false,
        weight: Int = 0,
        priorityTag: PriorityTag,
        image: Data? = nil,
        checkList: [CKRecord.Reference]? = nil,
        currentResponsible: CKRecord.Reference? = nil,
        allResponsibleUsers: [CKRecord.Reference]? = nil,
        roomReference: CKRecord.Reference? = nil,
        dailyAssignment: [CKRecord.Reference]? = nil,
        userThatHaveDone: CKRecord.Reference? = nil,
        calendarEventIdentifier: String? = nil
    ) {
        self.recordID = nil
        self.name = name
        self.description = description
        self.isDone = isDone
        self.dueDate = dueDate
        self.frequency = frequency
        self.shouldBeIncluded = frequency == .monthly ? Bool.random() : nil
        self.duration = duration
        self.isPublic = isPublic
        self.isLate = isLate
        self.weight = weight
        self.priorityTag = priorityTag
        self.image = image
        self.checkListReference = checkList
        self.currentResponsibleReference = currentResponsible
        self.allResponsibleUsersReference = allResponsibleUsers
        self.roomReference = roomReference
        self.dailyAssignmentsReference = dailyAssignment
        self.userThatHaveDoneReference = userThatHaveDone
        self.calendarEventIdentifier = calendarEventIdentifier
    }
    
    /// Saves a change to one of the chore's checklist items.
    func updateCheckItem(_ item: CheckItemModel) async {
        await CloudKitManager.shared.update(item)
    }
    
    /// Writes this model's values into a CloudKit record.
    ///
    /// - Parameter record: The record to populate.
    ///
    /// > Note: `nil` collections are skipped rather than written, so an existing list on the
    /// > server is preserved instead of being cleared.
    func populate(record: CKRecord) {
        record["name"] = name
        record["description"] = description
        record["isDone"] = isDone
        record["dueDate"] = dueDate
        record["frequency"] = frequency.rawValue
        record["shouldBeIncluded"] = shouldBeIncluded.map { $0 ? 1 : 0 }
        record["duration"] = duration
        record["isPublic"] = isPublic
        record["isLate"] = isLate
        record["weight"] = weight
        record["priorityTag"] = priorityTag.rawValue
        if let image {
            record["image"] = image
        }
        
        record["checkList"] = checkListReference ?? []
        record["currentResponsible"] = currentResponsibleReference
        record["allResponsibleUsers"] = allResponsibleUsersReference ?? []
        record["room"] = roomReference
        record["dailyAssignment"] = dailyAssignmentsReference ?? []
        record["userThatHaveDone"] = userThatHaveDoneReference
        record["calendarEventIdentifier"] = calendarEventIdentifier
    }
    
    /// Moves a one-off chore's ``dueDate`` by `days`.
    ///
    /// - Returns: `true` when CloudKit saved it. On failure the date is put back.
    @discardableResult
    func postpone(byDays days: Int) async -> Bool {
        let calendar = Calendar.current
        let previousDueDate = dueDate
        let currentDate = calendar.startOfDay(for: dueDate ?? Date())
        
        guard let newDate = calendar.date(byAdding: .day, value: days, to: currentDate) else { return false }
        dueDate = newDate
        
        guard await CloudKitManager.shared.update(self) else {
            dueDate = previousDueDate
            return false
        }
        return true
    }
    
    /// Flips ``isDone``, records who did it and persists the change.
    ///
    /// - Returns: `true` when CloudKit saved it. On failure the chore is left as it was.
    @discardableResult
    func toggle() async -> Bool {
        guard !isUpdating else { return false }
        isUpdating = true
        defer { isUpdating = false }
        
        guard let myUserRecordID = await CloudKitManager.shared.currentHouseUser()?.recordID
        else { return false }
        
        let previousIsDone = isDone
        let previousDoer = userThatHaveDoneReference
        
        isDone.toggle()
        userThatHaveDoneReference = isDone
        ? CKRecord.Reference(recordID: myUserRecordID, action: .none)
        : nil
        
        guard await CloudKitManager.shared.update(self) else {
            isDone = previousIsDone
            userThatHaveDoneReference = previousDoer
            return false
        }
        return true
    }
    
    /// Applies the edits made in `choreDTO` to this chore and persists everything to CloudKit.
        ///
        /// - Parameters:
        ///   - choreDTO: The edited values collected by the create/edit screen.
        ///   - pickedDate: The date picked in the form. Required to create a chore (except a daily one,
        ///     which starts today), and stored as `dueDate` when the chore is a one-off.
        ///   - targetAssignments: Optional recurrent assignment instances to update if this is an
        ///     occurrence of a recurring chore.
        /// - Throws: ``ChoreSaveError`` describing why nothing (or not everything) was saved.
    func save(
        from choreDTO: ChoreDTO,
        pickedDate: Date? = nil,
        targetAssignments: [RecurrentAssignmentModel] = []
    ) async throws {
        guard let roomReference = choreDTO.roomReference else {
            throw ChoreSaveError.missingRoom
        }
        
        if recordID == nil && choreDTO.frequency != .daily && pickedDate == nil {
            throw ChoreSaveError.missingDate
        }
        
        guard let room = await CloudKitManager.shared.fetchRecordsByRecordReference(
            for: RoomModel.self,
            recordReferences: [roomReference]
        )?.first else {
            throw ChoreSaveError.missingRoom
        }
        
        guard let houseReference = room.houseReference else {
            throw ChoreSaveError.missingHouse
        }
        
        let zoneID = houseReference.recordID.zoneID
        let parentReference = CKRecord.Reference(recordID: houseReference.recordID, action: .none)
        
        var newCurrentResponsibleReference: CKRecord.Reference?
        
        let responsibleUsers = choreDTO.responsibleUsers

        if let firstUser = responsibleUsers.first, let firstID = firstUser.recordID {
            newCurrentResponsibleReference = CKRecord.Reference(recordID: firstID, action: .none)
        } else {
            newCurrentResponsibleReference = nil
        }
                
        let snapshot = EditableSnapshot(of: self)
        
        let isSingleOccurrence = !targetAssignments.isEmpty
        applyEditableFields(from: choreDTO, responsibleUsers: responsibleUsers, isSingleOccurrence: isSingleOccurrence)
        
        currentResponsibleReference = newCurrentResponsibleReference
        if choreDTO.frequency == .none {
            dueDate = pickedDate
        }
        
        let isNewChore = recordID == nil
        if recordID == nil {
            guard let createdChore = await CloudKitManager.shared.create(self, zoneID: zoneID, parent: parentReference),
                  let createdRecordID = createdChore.recordID
            else {
                snapshot.restore(on: self)
                throw ChoreSaveError.cloudKit(CloudKitManager.shared.errorMessage)
            }
            recordID = createdRecordID
        }
        
        guard let choreRecordID = recordID else {
            snapshot.restore(on: self)
            throw ChoreSaveError.cloudKit(nil)
        }
        let choreReference = CKRecord.Reference(recordID: choreRecordID, action: .none)
        
        // Every new chore comes with its coupon. The chore is already saved, so a coupon that
        // fails to save doesn't undo it; the error is left in `CloudKitManager.errorMessage`.
        if isNewChore {
            let coupon = CouponModel(for: self, choreRecordID: choreRecordID)
            await CloudKitManager.shared.create(coupon, zoneID: zoneID, parent: choreReference)
        }
        
        let checklistDrafts = choreDTO.hasChecklist
            ? choreDTO.checklist.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            : []
        self.checkListReference = await CheckItemModel.sync(from: checklistDrafts, parent: choreReference)
        
        if !targetAssignments.isEmpty {
            await updateRecurrentAssignments(
                for: responsibleUsers,
                targetAssignments: targetAssignments
            )
        }
        
        guard await CloudKitManager.shared.update(self) else {
            snapshot.restore(on: self)
            throw ChoreSaveError.cloudKit(CloudKitManager.shared.errorMessage)
        }
    }

        /// Copies every user-editable field from `choreDTO` onto this chore.
        private func applyEditableFields(
            from choreDTO: ChoreDTO,
            responsibleUsers: [UserModel],
            isSingleOccurrence: Bool = false
        ) {
            name = choreDTO.name
            description = choreDTO.description
            frequency = choreDTO.frequency
            duration = choreDTO.duration
            priorityTag = choreDTO.priorityTag
            isPublic = choreDTO.isPublic
            symbolName = choreDTO.symbolName
            roomReference = choreDTO.roomReference
            
            if !isSingleOccurrence {
                if responsibleUsers.isEmpty {
                    allResponsibleUsersReference = nil
                } else {
                    allResponsibleUsersReference = responsibleUsers.compactMap { responsibleUser in
                        responsibleUser.recordID.map { CKRecord.Reference(recordID: $0, action: .none) }
                    }
                }
            }
        }

        /// Updates the user references for specific occurrences of a recurring chore based on selected users.
    func updateRecurrentAssignments(
        for responsibleUsers: [UserModel],
        targetAssignments: [RecurrentAssignmentModel]
    ) async {
        let userRefs = responsibleUsers.compactMap { user -> CKRecord.Reference? in
            guard let id = user.recordID else { return nil }
            return CKRecord.Reference(recordID: id, action: .none)
        }
        
        let assignmentsToUpdate: [RecurrentAssignmentModel]
        if targetAssignments.isEmpty {
            let allAssignments = await self.dailyAssignments
            assignmentsToUpdate = allAssignments.filter { !$0.isCompleted }
        } else {
            assignmentsToUpdate = targetAssignments
        }
        
        for assignment in assignmentsToUpdate {
            assignment.userReferences = userRefs.isEmpty ? nil : userRefs
        }
        
        if !assignmentsToUpdate.isEmpty {
            _ = await CloudKitManager.shared.batchUpdate(assignmentsToUpdate)
        }
    }
    
    /// Whether the viewer should see this chore.
    ///
    /// A private chore is hidden only when it clearly belongs to other residents, so a chore is
    /// never lost because the viewer's records couldn't be matched.
    ///
    /// - Parameters:
    ///   - viewerIDs: Every `UserModel` record ID of the viewer.
    ///   - otherResidentIDs: The record IDs of every other resident.
    func isVisible(viewerIDs: Set<CKRecord.ID>, otherResidentIDs: Set<CKRecord.ID>) -> Bool {
        guard !isPublic else { return true }
        
        var ownerIDs = Set((allResponsibleUsersReference ?? []).map(\.recordID))
        if let currentResponsibleReference {
            ownerIDs.insert(currentResponsibleReference.recordID)
        }
        
        guard ownerIDs.isDisjoint(with: viewerIDs) else { return true }
        return ownerIDs.isDisjoint(with: otherResidentIDs)
    }
    
    
    /// The fields ``save(from:pickedDate:targetAssignments:)`` may change, captured so a
    /// failed save can put the chore back exactly as it was.
    private struct EditableSnapshot {
        let name: String
        let description: String
        let frequency: Recurrence
        let duration: Double
        let priorityTag: PriorityTag
        let isPublic: Bool
        let symbolName: String
        let roomReference: CKRecord.Reference?
        let allResponsibleUsersReference: [CKRecord.Reference]?
        let currentResponsibleReference: CKRecord.Reference?
        let dueDate: Date?
        let checkListReference: [CKRecord.Reference]?
        
        /// Copies the editable fields of `chore`.
        init(of chore: ChoreModel) {
            name = chore.name
            description = chore.description
            frequency = chore.frequency
            duration = chore.duration
            priorityTag = chore.priorityTag
            isPublic = chore.isPublic
            symbolName = chore.symbolName
            roomReference = chore.roomReference
            allResponsibleUsersReference = chore.allResponsibleUsersReference
            currentResponsibleReference = chore.currentResponsibleReference
            dueDate = chore.dueDate
            checkListReference = chore.checkListReference
        }
        
        /// Puts the copied fields back on `chore` (used when saving fails).
        func restore(on chore: ChoreModel) {
            chore.name = name
            chore.description = description
            chore.frequency = frequency
            chore.duration = duration
            chore.priorityTag = priorityTag
            chore.isPublic = isPublic
            chore.symbolName = symbolName
            chore.roomReference = roomReference
            chore.allResponsibleUsersReference = allResponsibleUsersReference
            chore.currentResponsibleReference = currentResponsibleReference
            chore.dueDate = dueDate
            chore.checkListReference = checkListReference
        }
    }
    
    
  
    // MARK: - Delete
    
    /// Deletes this chore, or — for a recurring chore — just the given occurrence(s).
    ///
    /// - Parameter targetOccurrences: The specific occurrence(s) to delete instead of the
    ///   whole chore. Every entry must belong to this chore's ``dailyAssignmentsReference``.
    /// - Returns: `true` on success, otherwise `false` with ``CloudKitManager/errorMessage``
    ///   set.
    @discardableResult
    func delete(targetOccurrences: [RecurrentAssignmentModel] = []) async -> Bool {
        guard frequency != .none, !targetOccurrences.isEmpty else {
            return await deleteWhole()
        }
        return await deleteOccurrences(targetOccurrences)
    }
    
    /// Removes just the given occurrences: deletes their records, then detaches them from
    /// ``dailyAssignmentsReference`` so the chore stops pointing at records that no longer
    /// exist. The chore itself and every other occurrence are untouched.
    private func deleteOccurrences(_ occurrences: [RecurrentAssignmentModel]) async -> Bool {
        let occurrenceIDs = Set(occurrences.compactMap { $0.recordID })
        
        guard !occurrenceIDs.isEmpty, let zoneID = recordID?.zoneID else {
            CloudKitManager.shared.errorMessage = "Failed to delete occurrence: missing recordID"
            return false
        }
        
        guard await CloudKitManager.shared.delete(recordIDs: Array(occurrenceIDs), zoneID: zoneID) else {
            return false
        }
        
        for occurrence in occurrences {
            CalendarManager.shared.removeEvent(identifier: occurrence.calendarEventIdentifier, title: name, date: occurrence.day)
        }
        
        dailyAssignmentsReference = dailyAssignmentsReference?.filter { !occurrenceIDs.contains($0.recordID) }
        return await CloudKitManager.shared.update(self)
    }
    
    /// Removes the whole chore: every checklist item, every occurrence (if it's recurring),
    /// and the chore record itself
    private func deleteWhole() async -> Bool {
        guard let recordID else {
            CloudKitManager.shared.errorMessage = "Failed to delete chore: missing recordID"
            return false
        }
        
        let occurrences = frequency == .none ? [] : await dailyAssignments
        
        guard await CloudKitManager.shared.deleteChildren(of: recordID, includingSelf: true) else {
            return false
        }
        
        for occurrence in occurrences {
            CalendarManager.shared.removeEvent(identifier: occurrence.calendarEventIdentifier, title: name, date: occurrence.day)
        }
        CalendarManager.shared.removeEvent(identifier: calendarEventIdentifier, title: name, date: dueDate)
        
        return true
    }
    
    // MARK: - Duration migration
    
    /// Whether `duration` is a value the edit screen used to save in seconds (15 * 60, 30 * 60…)
    /// instead of minutes.
    static func isLegacySecondsDuration(_ duration: Double) -> Bool {
        duration >= 300 && duration.truncatingRemainder(dividingBy: 60) == 0
    }
    
    /// Rewrites, in minutes, the `duration` of chores whose record still stores seconds.
    static func migrateDurationsToMinutesIfNeeded(_ chores: [ChoreModel]) async {
        for chore in chores where chore.needsDurationMigration {
            guard let record = await CloudKitManager.shared.fetchRecord(for: chore) else { continue }
            record["duration"] = chore.duration
            if await CloudKitManager.shared.update(record: record) {
                chore.needsDurationMigration = false
            }
        }
    }
}

// MARK: - Save errors

/// Why ``ChoreModel/save(from:pickedDate:targetAssignments:)`` did not save the chore.
enum ChoreSaveError: LocalizedError {
    /// The chore has no room.
    case missingRoom
    /// A one-off chore needs a date and none was picked.
    case missingDate
    /// The house of the chore's room could not be found.
    case missingHouse
    /// The signed-in member's profile could not be found (needed for a private chore).
    case missingCurrentUser
    /// CloudKit rejected the save. Carries CloudKit's message, if any.
    case cloudKit(String?)
    
    /// A short, user-facing message for the error, already translated.
    var errorDescription: String? {
        switch self {
        case .missingRoom:
            return L10n.tr("Escolha um cômodo para a tarefa.")
        case .missingDate:
            return L10n.tr("Escolha uma data para a tarefa.")
        case .missingHouse:
            return L10n.tr("Não foi possível identificar a casa deste cômodo.")
        case .missingCurrentUser:
            return L10n.tr("Não foi possível identificar seu perfil para salvar a tarefa privada.")
        case .cloudKit(let message):
            return message ?? L10n.tr("Não foi possível salvar a tarefa. Tente novamente.")
        }
    }
}
