//
//  AvailableTimeModel.swift
//  Cognitive-Work
//
//  Created by anshu Li on 18/08/26.
//

import Foundation
import CloudKit

/// How many minutes a member can spend on chores on one day.
///
/// The division of chores uses these records so nobody gets more work than their free time allows.
struct AvailableTimeModel: CloudKitSyncable {
    /// The CloudKit record type.
    static let recordType: String = "AvailableTimeModel"
    
    /// The CloudKit record ID. `nil` until the model is saved.
    var recordID: CKRecord.ID?
    /// Minutes available for chores on ``day``.
    var capacityMinutes: Int
    /// The day this free time is for (always at the start of the day).
    var day: Date
    
    /// The member this free time belongs to.
    private var userReference: CKRecord.Reference?
    
    /// The member this free time belongs to, fetched from CloudKit. `nil` if not set or not found.
    var user: UserModel? {
        get async {
            if let userReference {
                return await CloudKitManager.shared.fetchRecordsByRecordReference(for: UserModel.self, recordReferences: [userReference])?.first
            }
            return nil
        }
    }
    
    /// Creates a new record, not saved yet.
    /// - Parameters:
    ///   - capacityMinutes: Minutes available for chores.
    ///   - day: The day; it is moved to the start of the day.
    ///   - user: The member it belongs to.
    init(capacityMinutes: Int, day: Date, user: CKRecord.Reference? = nil) {
        self.capacityMinutes = capacityMinutes
        self.day = Calendar.current.startOfDay(for: day)
        self.userReference = user
    }
    
    /// Creates the model from a CloudKit record. Returns `nil` when the minutes or the day are missing.
    init?(record: CKRecord) {
        guard
            let capacityMinutes = record["capacityMinutes"] as? Int,
            let day = record["day"] as? Date
        else {
            return nil
        }

        self.recordID = record.recordID
        self.capacityMinutes = capacityMinutes
        self.day = day
        self.userReference = record["user"] as? CKRecord.Reference
    }
    
    /// Copies the model's fields into `record`, before saving it.
    func populate(record: CKRecord) {
        record["capacityMinutes"] = capacityMinutes
        record["day"] = day
        if let userReference {
            record["user"] = userReference
        }
    }
}
