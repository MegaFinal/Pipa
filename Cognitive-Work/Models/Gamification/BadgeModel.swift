//
//  Badge.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 27/08/26.
//

import SwiftUI
import CloudKit

/// An achievement badge a member can unlock.
///
/// > Note: Badges are not shown anywhere in the app yet.
struct BadgeModel: CloudKitSyncable {
    /// The CloudKit record type.
    static var recordType: String = "BadgeModel"
    
    /// The CloudKit record ID. `nil` until the model is saved.
    var recordID: CKRecord.ID?
    
    /// The badge's name.
    var name: String
    /// The badge's image (PNG or JPEG data).
    var image: Data
    /// What the member has to do to unlock it.
    var description: String
    /// Whether the badge is still locked.
    var isLocked: Bool
    /// The rank needed for the badge.
    var tier: Tier
    /// How many times the badge was earned.
    var quantity: Int
    /// The room the badge is about, if any.
    var room: CKRecord.Reference?
    /// The members who have the badge. Not saved by ``populate(record:)``.
    var users: [CKRecord.Reference]?
    
    /// Creates the model from a CloudKit record. Returns `nil` when a required field is missing.
    init?(record: CKRecord) {
        guard
            let name = record["name"] as? String,
            let image = record["image"] as? Data,
            let description = record["description"] as? String,
            let isLocked = record["isLocked"] as? Bool,
            let tier = record["tier"] as? String,
            let quantity = record["quantity"] as? Int
        else {
            return nil
        }
        
        self.recordID = record.recordID
        
        self.name = name
        self.image = image
        self.description = description
        self.isLocked = isLocked
        self.tier = Tier(stored: tier)
        self.quantity = quantity
        self.room = record["room"] as? CKRecord.Reference
        self.users = record["users"] as? [CKRecord.Reference]
    }
    
    /// Creates a new badge, locked and never earned by default.
    init(name: String,
         image: Data,
         description: String,
         isLocked: Bool = true,
         tier: Tier,
         quantity: Int = 0,
         room: CKRecord.Reference? = nil,
         users: [CKRecord.Reference]? = nil)
    {
        self.name = name
        self.image = image
        self.description = description
        self.isLocked = isLocked
        self.tier = tier
        self.quantity = quantity
        self.room = room
        self.users = users
    }
    
    /// Copies the model's fields into `record`, before saving it.
    func populate(record: CKRecord) {
        record["name"] = name
        record["image"] = image
        record["description"] = description
        record["isLocked"] = isLocked
        record["tier"] = tier.rawValue
        record["quantity"] = quantity
        if let room {
            record["room"] = room
        }
    }
}
