//
//  NotificationModel.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 26/10/26.
//

import CloudKit
import Foundation
import UserNotifications

struct NotificationCloudDTO: CloudKitSyncable {
    static var recordType: String = "NotificationModel"
    
    var recordID: CKRecord.ID?
    
    let soundName: String
    
    let id = UUID()
    let title: String
    let body: String
    var sound: UNNotificationSound {
        switch soundName {
        case "defaultCritical": return .defaultCritical
        case "defaultRingtone": return .defaultRingtone
        default:                return .default
        }
    }
    let threadIdentifier: String
    let userInfo: [AnyHashable: Any]
    
    /// Who should receive the notification: the `ownerRecordName` of each person.
    /// Each device only schedules the records that list its own user.
    let recipientIDs: [String]
    
    /// When the notification should appear. `nil` means as soon as it is received.
    let fireDate: Date?
    
    var dateComponent: DateComponents? {
        guard let fireDate else { return nil }
        return Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
    }
    
    /// Creates a notification to be sent. ``recordID`` is set when it is saved.
    init(title: String,
         body: String,
         soundName: String = "default",
         threadIdentifier: String = "",
         recipientIDs: [String],
         userInfo: [AnyHashable: Any] = [:],
         fireDate: Date? = nil) {
        self.recordID = nil
        self.title = title
        self.body = body
        self.soundName = soundName
        self.threadIdentifier = threadIdentifier
        self.recipientIDs = recipientIDs
        self.userInfo = userInfo
        self.fireDate = fireDate
    }
    
    init?(record: CKRecord) {
        guard
            let title = record["title"] as? String,
            let body = record["body"] as? String,
            let soundName = record["soundName"] as? String,
            let threadIdentifier = record["threadIdentifier"] as? String,
            let recipientIDs = record["recipientIDs"] as? [String]
        else {
            return nil
        }
        
        // Without it the record can't be told apart, scheduled or deleted.
        self.recordID = record.recordID
        self.title = title
        self.body = body
        self.soundName = soundName
        self.threadIdentifier = threadIdentifier
        self.recipientIDs = recipientIDs
        self.fireDate = record["fireDate"] as? Date
        
        if let data = record["userInfo"] as? Data,
           let info = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            as? [AnyHashable: Any] {
            self.userInfo = info
        } else {
            self.userInfo = [:]
        }
    }
    
    func populate(record: CKRecord) {
        record["title"] = title
        record["body"] = body
        record["soundName"] = soundName
        record["threadIdentifier"] = threadIdentifier
        record["recipientIDs"] = recipientIDs
        if let fireDate {
            record["fireDate"] = fireDate
        }

        if let data = try? PropertyListSerialization.data(
            fromPropertyList: userInfo, format: .binary, options: 0
        ) {
            record["userInfo"] = data
        }
    }
}
