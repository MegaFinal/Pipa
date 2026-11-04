//
//  CouponHoldModel.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 16/10/26.
//

import Foundation
import CloudKit

/// Marks that a user bought a coupon in a room during a cycle, enforcing "at most one coupon per
/// room per user per cycle".
///
/// The coupon record alone can't enforce that rule: two purchases of *different* coupons in the
/// same room write different records, so CloudKit sees no conflict. Every purchase in a room also
/// writes this record, named `hold-<user recordName>-<room recordName>`, which turns two such
/// purchases into a conflict on the same record: only one succeeds.
///
/// A hold only counts while ``cycleKey`` is the latest cycle; in a later cycle it is simply
/// overwritten by the next purchase, never deleted.
struct CouponHoldModel: CloudKitSyncable, Equatable {

    /// The CloudKit record type.
    static var recordType: String = "CouponHoldModel"

    /// The CloudKit record ID (`hold-<user>-<room>`). `nil` until the model is saved.
    var recordID: CKRecord.ID?

    /// The member who bought the coupon.
    var user: CKRecord.Reference
    /// The room of the coupon's chore.
    var room: CKRecord.Reference
    /// The coupon that was bought.
    var coupon: CKRecord.Reference
    /// Key of the cycle the coupon was bought in (see ``HouseCycleModel/key(for:calendar:)``).
    var cycleKey: String

    /// Creates a new hold, not saved yet.
    init(user: CKRecord.Reference, room: CKRecord.Reference, coupon: CKRecord.Reference, cycleKey: String) {
        self.user = user
        self.room = room
        self.coupon = coupon
        self.cycleKey = cycleKey
    }

    /// Creates the model from a CloudKit record. Returns `nil` when a field is missing.
    init?(record: CKRecord) {
        guard
            let user = record["user"] as? CKRecord.Reference,
            let room = record["room"] as? CKRecord.Reference,
            let coupon = record["coupon"] as? CKRecord.Reference,
            let cycleKey = record["cycleKey"] as? String
        else { return nil }

        self.recordID = record.recordID
        self.user = user
        self.room = room
        self.coupon = coupon
        self.cycleKey = cycleKey
    }

    /// Copies the model's fields into `record`, before saving it.
    func populate(record: CKRecord) {
        record["user"] = user
        record["room"] = room
        record["coupon"] = coupon
        record["cycleKey"] = cycleKey
    }

    /// The fixed record ID of the hold of `userID` in `roomID`. There is only one per user and room.
    static func recordID(userID: CKRecord.ID, roomID: CKRecord.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: "hold-\(userID.recordName)-\(roomID.recordName)", zoneID: userID.zoneID)
    }
}
