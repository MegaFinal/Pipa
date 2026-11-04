//
//  AtomicRecordStore.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 16/10/26.
//

import Foundation
import CloudKit

/// The two operations the coin and coupon flows need from CloudKit, so their concurrency rules
/// can be tested without a server.
///
/// CloudKit has no transactions, so every flow follows the same optimistic pattern:
/// 1. ``fetch(_:)`` the records involved. Each fetched `CKRecord` carries the server's change tag.
/// 2. Check the business rules on those values and change the records.
/// 3. ``saveAtomically(_:)`` all of them in one request.
///
/// The save succeeds only if **no** record changed on the server since it was fetched, and a
/// record created locally (no change tag) does not exist yet. Otherwise nothing is written and
/// ``AtomicRecordStoreError/conflict`` is thrown: the caller fetches again and re-checks the
/// rules. Deterministic record names turn "does not exist yet" into a uniqueness constraint.
///
/// Deletes are deliberately not offered: CloudKit does not check change tags on deletes, so they
/// can't take part in this pattern. Records expire by being overwritten instead.
@MainActor
protocol AtomicRecordStore: AnyObject {

    /// The records that exist among `ids`. Missing records are simply absent from the result.
    func fetch(_ ids: [CKRecord.ID]) async throws -> [CKRecord.ID: CKRecord]

    /// Saves every record or none. All records must be in the same zone.
    ///
    /// - Throws: ``AtomicRecordStoreError/conflict`` when any record changed (or appeared)
    ///   since it was fetched; any other error for failures unrelated to concurrency.
    func saveAtomically(_ records: [CKRecord]) async throws
}

/// Errors thrown by an ``AtomicRecordStore``.
enum AtomicRecordStoreError: Error, Equatable {
    /// Someone else wrote one of the records first. Fetch again and retry.
    case conflict
}

// MARK: - CloudKit

/// ``AtomicRecordStore`` backed by the house's zone.
///
/// Uses `modifyRecords(saving:deleting:savePolicy: .ifServerRecordUnchanged, atomically: true)`.
/// Atomic batches are only honored in custom zones, which is where every house lives
/// (`HomeEnvironment`, shared to members through the house's `CKShare`).
@MainActor
final class CloudKitAtomicRecordStore: AtomicRecordStore {

    /// Gives access to the private and shared CloudKit databases.
    private let manager: CloudKitManager

    /// - Parameter manager: Defaults to ``CloudKitManager/shared`` (resolved in the body, since
    ///   default argument expressions are evaluated outside the main actor).
    init(manager: CloudKitManager? = nil) {
        self.manager = manager ?? .shared
    }

    /// The database that holds `zoneID`: the private one when the user owns the zone, the shared one otherwise.
    private func database(for zoneID: CKRecordZone.ID) -> CKDatabase {
        zoneID.ownerName == CKCurrentUserDefaultName ? manager.privateDB : manager.sharedDB
    }

    /// The records that exist among `ids`, read from the server. All IDs must be in the same zone.
    func fetch(_ ids: [CKRecord.ID]) async throws -> [CKRecord.ID: CKRecord] {
        guard let zoneID = ids.first?.zoneID else { return [:] }

        let results = try await database(for: zoneID).records(for: ids)
        var found: [CKRecord.ID: CKRecord] = [:]
        for (id, result) in results {
            switch result {
            case .success(let record):
                found[id] = record
            case .failure(let error as CKError) where error.code == .unknownItem:
                continue
            case .failure(let error):
                throw error
            }
        }
        return found
    }

    /// Saves every record or none, failing if any of them changed on the server since it was fetched.
    /// - Throws: ``AtomicRecordStoreError/conflict`` on a concurrent change; other errors as they come.
    func saveAtomically(_ records: [CKRecord]) async throws {
        guard let zoneID = records.first?.recordID.zoneID else { return }

        do {
            let (saveResults, _) = try await database(for: zoneID).modifyRecords(
                saving: records,
                deleting: [],
                savePolicy: .ifServerRecordUnchanged,
                atomically: true
            )
            // Per-record failures come back in the results, not as a thrown error.
            let failures = saveResults.values.compactMap { result -> Error? in
                if case .failure(let error) = result { return error }
                return nil
            }
            if !failures.isEmpty { throw Self.mapped(failures) }
        } catch let error as AtomicRecordStoreError {
            throw error
        } catch {
            throw Self.mapped([error])
        }

        manager.markDataChanged()
    }

    /// `.conflict` when any failure is `serverRecordChanged` (directly or inside a
    /// `partialFailure`). In an atomic batch the other records fail with `batchRequestFailed`,
    /// so the conflicting one has to be looked for.
    private static func mapped(_ errors: [Error]) -> Error {
        for error in errors {
            guard let ckError = error as? CKError else { continue }
            if ckError.code == .serverRecordChanged { return AtomicRecordStoreError.conflict }
            if ckError.code == .partialFailure,
               let partial = ckError.partialErrorsByItemID?.values,
               partial.contains(where: { ($0 as? CKError)?.code == .serverRecordChanged }) {
                return AtomicRecordStoreError.conflict
            }
        }
        return errors.first(where: { ($0 as? CKError)?.code != .batchRequestFailed }) ?? errors[0]
    }
}
