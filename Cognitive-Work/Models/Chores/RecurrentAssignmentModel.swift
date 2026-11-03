//
//  RecurrentAssignmentModel.swift
//  Cognitive-Work
//
//  Created by anshu Li on 18/08/26.
//

import Foundation
import CloudKit

/// One occurrence of a chore on one day, given to one or more members.
///
/// A daily chore has one of these per day of the cycle; a weekly one, one per week, and so on.
/// The division of chores creates them, and members check them off as they do the chore.
///
/// The CloudKit record type is still called `DailyAssignmentModel` for older data.
@Observable
class RecurrentAssignmentModel: CloudKitSyncable {
    /// The CloudKit record type.
    static let recordType: String = "DailyAssignmentModel"
    
    /// The CloudKit record ID. `nil` until the model is saved.
    var recordID: CKRecord.ID?
    /// The day the chore should be done (always at the start of the day).
    var day: Date
    /// Whether the chore was done on this day.
    var isCompleted: Bool
    
    /// The members responsible for this occurrence. `nil` or empty when nobody took it.
    var userReferences: [CKRecord.Reference]?
    /// The member who checked it off. `nil` while not done.
    var userThatHaveDoneReference: CKRecord.Reference?
    /// The chore this occurrence belongs to.
    var choreReference: CKRecord.Reference?
    
    /// `true` while ``toggle()`` is saving, so a second tap is ignored.
    @ObservationIgnored
    private var isUpdating = false

    /// ID of the matching event in the user's Apple Calendar, when calendar sync is on.
    var calendarEventIdentifier: String?
    
    /// The responsible members, fetched from CloudKit.
    var users: [UserModel] {
        get async {
            if let userReferences, !userReferences.isEmpty {
                return await CloudKitManager.shared.fetchRecordsByRecordReference(
                    for: UserModel.self,
                    recordReferences: userReferences
                ) ?? []
            }
            return []
        }
    }
    
    /// The member who checked it off, fetched from CloudKit.
    var userThatHaveDone: UserModel? {
        get async {
            if let userThatHaveDoneReference {
                return await CloudKitManager.shared.fetchRecordsByRecordReference(
                    for: UserModel.self,
                    recordReferences: [userThatHaveDoneReference]
                )?.first
            }
            return nil
        }
    }

    /// The chore, fetched from CloudKit.
    var chore: ChoreModel? {
        get async {
            if let choreReference {
                return await CloudKitManager.shared.fetchRecordsByRecordReference(
                    for: ChoreModel.self,
                    recordReferences: [choreReference]
                )?.first
            }
            return nil
        }
    }

    /// Creates a new occurrence, not saved yet. `day` is moved to the start of the day.
    init(
        day: Date,
        isCompleted: Bool = false,
        users: [CKRecord.Reference]? = nil,
        chore: CKRecord.Reference? = nil,
        calendarEventIdentifier: String? = nil
    ) {
        self.day = Calendar.current.startOfDay(for: day)
        self.isCompleted = isCompleted
        self.userReferences = users
        self.choreReference = chore
        self.calendarEventIdentifier = calendarEventIdentifier
    }
    
    /// Creates the model from a CloudKit record. Returns `nil` when the day or the done flag is missing.
    required init?(record: CKRecord) {
        guard
            let isCompleted = record["isCompleted"] as? Bool,
            let day = record["day"] as? Date
        else {
            return nil
        }

        self.recordID = record.recordID
        self.isCompleted = isCompleted
        self.day = day
        self.userReferences = record["users"] as? [CKRecord.Reference]
        self.choreReference = record["chore"] as? CKRecord.Reference
        self.userThatHaveDoneReference = record["userThatHaveDone"] as? CKRecord.Reference
        self.calendarEventIdentifier = record["calendarEventIdentifier"] as? String
    }
    
    /// Copies the model's fields into `record`, before saving it.
    func populate(record: CKRecord) {
        record["isCompleted"] = isCompleted
        record["day"] = day
        record["users"] = userReferences ?? []
        record["chore"] = choreReference
        record["userThatHaveDone"] = userThatHaveDoneReference
        record["calendarEventIdentifier"] = calendarEventIdentifier
    }
    
    /// Moves the occurrence `days` days later and saves it.
    /// - Parameter days: How many days to move (negative moves it earlier).
    /// - Returns: `true` if it was saved; on failure the day goes back to what it was.
    @MainActor
    @discardableResult
    func postpone(byDays days: Int) async -> Bool {
        let calendar = Calendar.current
        let previousDay = day
        
        guard let newDay = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: day)) else { return false }
        day = newDay
        
        guard await CloudKitManager.shared.update(self) else {
            day = previousDay
            return false
        }
        return true
    }
    
    /// Checks or unchecks the occurrence as done by the signed-in member, and saves it.
    ///
    /// Ignored while a previous toggle is still saving.
    /// - Returns: `true` if it was saved; on failure the change is undone.
    @MainActor
    @discardableResult
    func toggle() async -> Bool {
        guard !isUpdating else { return false }
        isUpdating = true
        defer { isUpdating = false }
        
        guard let myUserRecordID = await CloudKitManager.shared.currentHouseUser()?.recordID
        else { return false }
        
        let previousIsCompleted = isCompleted
        let previousDoer = userThatHaveDoneReference
        
        isCompleted.toggle()
        userThatHaveDoneReference = isCompleted
        ? CKRecord.Reference(recordID: myUserRecordID, action: .none)
        : nil
        
        guard await CloudKitManager.shared.update(self) else {
            isCompleted = previousIsCompleted
            userThatHaveDoneReference = previousDoer
            return false
        }
        return true
    }
}
