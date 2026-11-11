//
//  CKErrorExtension.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 11/11/26.
//

import CloudKit

extension Error {

    /// Whether this is a CloudKit "iCloud storage is full" error.
    ///
    /// Batch saves (`modifyRecords`) report it inside a `partialFailure`, one error per record,
    /// so checking only the outer code misses it.
    var isQuotaExceeded: Bool {
        guard let ckError = self as? CKError else { return false }
        if ckError.code == .quotaExceeded { return true }
        return ckError.partialErrorsByItemID?.values.contains { $0.isQuotaExceeded } ?? false
    }

    /// The owner of the zone whose save failed for lack of iCloud space, read from the record or
    /// zone IDs of a `partialFailure`. `nil` when the error does not carry them.
    ///
    /// Equal to `CKCurrentUserDefaultName` when the zone belongs to the current user.
    var quotaExceededZoneOwnerName: String? {
        guard let partialErrors = (self as? CKError)?.partialErrorsByItemID else { return nil }

        for (item, error) in partialErrors where error.isQuotaExceeded {
            if let recordID = item.base as? CKRecord.ID {
                return recordID.zoneID.ownerName
            }
            if let zoneID = item.base as? CKRecordZone.ID {
                return zoneID.ownerName
            }
        }
        return nil
    }

    /// Whether this is the error CloudKit gives the *other* records of an atomic batch when one
    /// of them fails. It says nothing about why: the real cause is on another record.
    var isBatchRequestFailed: Bool {
        (self as? CKError)?.code == .batchRequestFailed
    }
}
