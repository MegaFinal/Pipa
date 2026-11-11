//
//  ICloudStorageMonitor.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 11/11/26.
//

import CloudKit
import Foundation

/// Notices when CloudKit refuses to save because an iCloud account is out of space, and asks
/// the app to tell the user.
///
/// CloudKit has no API to read how much iCloud storage is left: the only signal is a write that
/// fails with `CKError.Code.quotaExceeded`. Every CloudKit failure is passed to
/// ``report(_:owner:)``; the app root shows ``notice`` with
/// ``SwiftUI/View/iCloudStorageAlert()``.
@Observable
final class ICloudStorageMonitor {

    /// The shared instance used by the whole app.
    static let shared = ICloudStorageMonitor()

    /// Whose iCloud ran out of space.
    enum StorageOwner: Equatable {
        /// The current user's: writes to the private database count against their own storage.
        case currentUser
        /// The house creator's: writes to a shared house count against the owner's storage, so a
        /// member with free space still fails when the owner's iCloud is full.
        case houseOwner
    }

    /// What the alert should say.
    struct Notice: Equatable {
        /// Whose iCloud is full, or `nil` when the failing database could not be told apart.
        let owner: StorageOwner?
    }

    /// The pending notice. Set by ``report(_:owner:)``, cleared by ``dismiss()``.
    private(set) var notice: Notice?

    /// How long the notice stays quiet after being dismissed, so every failed save that follows
    /// does not bring it right back.
    private let quietPeriod: TimeInterval = 10 * 60

    /// When the user last dismissed the notice.
    @ObservationIgnored
    private var lastDismissal: Date?

    private init() {}

    // MARK: - Reporting

    /// Shows the notice when `error` says an iCloud is full.
    ///
    /// - Parameters:
    ///   - error: Any error. Nothing happens unless it is (or contains) `quotaExceeded`.
    ///   - owner: Whose iCloud is full, when the caller knows the database. When `nil`, it is
    ///     read from the record or zone IDs inside a partial failure, if any.
    /// - Returns: `true` when `error` is a full-iCloud error.
    @discardableResult
    func report(_ error: Error, owner: StorageOwner? = nil) -> Bool {
        guard error.isQuotaExceeded else { return false }

        let owner = owner ?? error.quotaExceededZoneOwnerName.map(Self.owner(ofZoneOwnedBy:))

        // Already on screen: only make it more precise, never less.
        if let notice {
            if notice.owner == nil, owner != nil {
                self.notice = Notice(owner: owner)
            }
            return true
        }

        if let lastDismissal, Date.now.timeIntervalSince(lastDismissal) < quietPeriod {
            return true
        }

        notice = Notice(owner: owner)
        return true
    }

    /// Shows the notice when `error`, returned by `database`, says an iCloud is full.
    /// - Returns: `true` when `error` is a full-iCloud error.
    @discardableResult
    func report(_ error: Error, in database: CKDatabase) -> Bool {
        report(error, owner: Self.owner(of: database))
    }

    /// Checks the per-record results of a `modifyRecords` call, which does not throw when only
    /// some records fail (for example with `atomically: false`).
    /// - Returns: `true` when one of the failures is a full-iCloud error.
    @discardableResult
    func report(
        saveResults: [CKRecord.ID: Result<CKRecord, Error>],
        in database: CKDatabase
    ) -> Bool {
        for case .failure(let error) in saveResults.values where report(error, in: database) {
            return true
        }
        return false
    }

    /// Hides the notice and keeps it quiet for a while.
    func dismiss() {
        notice = nil
        lastDismissal = .now
    }

    // MARK: - Helpers

    /// Whose storage a write to `database` uses.
    private static func owner(of database: CKDatabase) -> StorageOwner {
        database.databaseScope == .private ? .currentUser : .houseOwner
    }

    /// Whose storage a write to a zone owned by `ownerName` uses.
    private static func owner(ofZoneOwnedBy ownerName: String) -> StorageOwner {
        ownerName == CKCurrentUserDefaultName ? .currentUser : .houseOwner
    }
}
