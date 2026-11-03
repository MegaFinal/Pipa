//
//  SharedMembershipExtension.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 28/09/26.
//

import CloudKit
import Foundation
import SwiftUI

/// Observable flag the UI binds to while an orphaned house membership is being removed in the
/// background (see ``CloudKitManager/pruneOrphanedSharedMemberships()``), so the screen can be
/// blocked with ``BlockingOperationOverlay`` for the duration of the unlink.
@Observable
final class SharedMembershipCleanup {
    /// The single instance the UI observes.
    static let shared = SharedMembershipCleanup()
    /// `true` while a membership is being removed. Only changed by ``CloudKitManager``.
    fileprivate(set) var isUnlinking = false
    /// Use ``shared``.
    private init() {}
}

/// Everything about *leaving* houses shared with this iCloud account.
///
/// Everything here works per shared **zone** (`sharedDB.allRecordZones()`), without relying on
/// local state, CKQuery indexes, or which house the app currently considers "current".
extension CloudKitManager {
    
    // MARK: - Pending join
    
    /// Keys remembering a share that was accepted but whose member record may not exist yet.
    private enum PendingJoinKey {
        static let zoneName = "pendingJoin.zoneName"
        static let ownerName = "pendingJoin.ownerName"
        static let date = "pendingJoin.date"
    }
    
    /// Same key `OnboardingStateMachine` persists its flow under.
    private static let onboardingFlowKey = "onboarding.flow"
    
    /// How long a freshly accepted share is protected from pruning, even outside an invited flow.
    private static let pendingJoinGracePeriod: TimeInterval = 60 * 60
    
    /// Records that the share living in `zoneID` was just accepted, so
    /// ``pruneOrphanedSharedMemberships()`` doesn't remove it before ``OnboardingViewModel/joinHouse()``
    /// creates this user's member record.
    func rememberPendingJoin(zoneID: CKRecordZone.ID) {
        let defaults = UserDefaults.standard
        defaults.set(zoneID.zoneName, forKey: PendingJoinKey.zoneName)
        defaults.set(zoneID.ownerName, forKey: PendingJoinKey.ownerName)
        defaults.set(Date(), forKey: PendingJoinKey.date)
    }
    
    /// Forgets the pending join. Pass `zoneID` to clear it only when it refers to that zone.
    func clearPendingJoin(ifMatching zoneID: CKRecordZone.ID? = nil) {
        if let zoneID, !isPendingJoinZone(zoneID) { return }
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: PendingJoinKey.zoneName)
        defaults.removeObject(forKey: PendingJoinKey.ownerName)
        defaults.removeObject(forKey: PendingJoinKey.date)
    }
    
    /// Whether `zoneID` is the house the user saved as "joining" in `UserDefaults`.
    private func isPendingJoinZone(_ zoneID: CKRecordZone.ID) -> Bool {
        let defaults = UserDefaults.standard
        return defaults.string(forKey: PendingJoinKey.zoneName) == zoneID.zoneName
        && defaults.string(forKey: PendingJoinKey.ownerName) == zoneID.ownerName
    }
    
    /// Whether `zoneID` is a share the user is still in the middle of joining.
    private func isJoinPending(for zoneID: CKRecordZone.ID) -> Bool {
        guard isPendingJoinZone(zoneID) else { return false }
        
        let flow = UserDefaults.standard.string(forKey: Self.onboardingFlowKey)
        if flow == NavigationFlowsOnboarding.invitedWithProfile.rawValue
            || flow == NavigationFlowsOnboarding.invitedWithoutProfile.rawValue {
            return true
        }
        
        if let date = UserDefaults.standard.object(forKey: PendingJoinKey.date) as? Date,
           Date().timeIntervalSince(date) < Self.pendingJoinGracePeriod {
            return true
        }
        return false
    }
    
    // MARK: - Orphaned memberships
    
    /// In-flight prune, so concurrent callers (launch, onboarding, invite link) share one run.
    private static var membershipPruneTask: Task<Int, Never>?
    
    /// Leaves every shared house in which this account no longer has a member record.
    ///
    /// - Returns: How many houses were left.
    @discardableResult
    func pruneOrphanedSharedMemberships() async -> Int {
        if let running = Self.membershipPruneTask {
            return await running.value
        }
        
        let task = Task<Int, Never> { await self.performMembershipPrune() }
        Self.membershipPruneTask = task
        let removed = await task.value
        Self.membershipPruneTask = nil
        return removed
    }
    
    /// Leaves every shared house zone where the user has no member record (and isn't still joining).
    /// - Returns: How many houses were left.
    private func performMembershipPrune() async -> Int {
        let zones: [CKRecordZone]
        do {
            zones = try await sharedDB.allRecordZones()
        } catch {
            return 0
        }
        
        guard !zones.isEmpty,
              let ownerRecordName = await fetchCurrentUserRecordID()?.recordName
        else {
            return 0
        }
        
        let profileIDs: [CKRecord.ID]
        do {
            profileIDs = try await privateProfileRecordIDs(ownerRecordName: ownerRecordName)
        } catch {
            return 0
        }
        
        var removed = 0
        
        for zone in zones {
            let zoneID = zone.zoneID
            
            guard zoneID.ownerName != CKCurrentUserDefaultName,
                  let isMember = await hasMemberRecord(in: zoneID, profileIDs: profileIDs),
                  !isMember,
                  !isJoinPending(for: zoneID)
            else {
                continue
            }
            
            SharedMembershipCleanup.shared.isUnlinking = true
            let left = await unlinkFromSharedZone(
                zoneID,
                ownerRecordName: ownerRecordName,
                profileIDs: profileIDs,
                requireFootprintRemoval: false
            )
            if left { removed += 1 }
        }
        
        SharedMembershipCleanup.shared.isUnlinking = false
        
        if removed > 0 {
            invalidateSessionCache()
            await UserProfileCache.shared.removeAll()
        }
        return removed
    }
    
    /// `true` when the zone holds this account's member record, `false` when it definitely
    /// doesn't, `nil` when that couldn't be determined.
    private func hasMemberRecord(
        in zoneID: CKRecordZone.ID,
        profileIDs: [CKRecord.ID]
    ) async -> Bool? {
        for profileID in profileIDs {
            let memberID = houseUserRecordID(for: profileID, inHouseZone: zoneID)
            do {
                _ = try await sharedDB.record(for: memberID)
                return true
            } catch let error as CKError where error.code == .unknownItem {
                continue
            } catch {
                return nil
            }
        }
        return false
    }
    
    /// Every private profile (not in-house copy) owned by this iCloud account.
    ///
    /// - Throws: Any CloudKit error other than the zone not existing.
    private func privateProfileRecordIDs(ownerRecordName: String) async throws -> [CKRecord.ID] {
        let records: [CKRecord]
        do {
            records = try await scanZone(houseZoneID, in: privateDB)
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            return []
        }
        
        return records
            .filter { $0.recordType == UserModel.recordType }
            .compactMap { UserModel(record: $0) }
            .filter { $0.ownerRecordName == ownerRecordName && !isHouseUser($0) }
            .compactMap { $0.recordID }
    }
    
    // MARK: - Leaving
    
    /// Fully detaches this account from the shared house in `zoneID`.
    ///
    /// - Parameter requireFootprintRemoval: When `true`, a failure in step 2 aborts before
    ///   leaving, so the call can be retried without leaving a ghost member behind.
    /// - Returns: `true` once the account is no longer attached to the zone.
    @discardableResult
    func unlinkFromSharedZone(
        _ zoneID: CKRecordZone.ID,
        ownerRecordName: String?,
        profileIDs: [CKRecord.ID],
        requireFootprintRemoval: Bool
    ) async -> Bool {
        guard zoneID.ownerName != CKCurrentUserDefaultName else {
            errorMessage = UserFacingError.friendly(technical: "Failed to leave house: current user is the owner")
            return false
        }
        
        let records: [CKRecord]
        do {
            records = try await scanZone(zoneID, in: sharedDB)
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            clearPendingJoin(ifMatching: zoneID)
            invalidateSessionCache()
            return true
        } catch {
            errorMessage = UserFacingError.message(for: error, doing: .share)
            return false
        }
        
        let derivedNames = Set(profileIDs.map {
            houseUserRecordID(for: $0, inHouseZone: zoneID).recordName
        })
        
        let myUserIDs = Set(
            records
                .filter { record in
                    guard record.recordType == UserModel.recordType else { return false }
                    if derivedNames.contains(record.recordID.recordName) { return true }
                    if let ownerRecordName,
                       record["ownerRecordName"] as? String == ownerRecordName {
                        return true
                    }
                    return false
                }
                .map { $0.recordID }
        )
        
        let houses = records.filter { $0.recordType == HouseModel.recordType }
        
        // Gives the leaving member's pending chores back to the house before the member record
        // disappears, so the other residents can pick them up from the unassigned list.
        await releaseAssignments(of: myUserIDs, in: records)
        
        if !myUserIDs.isEmpty {
            var housesToSave: [CKRecord] = []
            for house in houses {
                guard let references = house["users"] as? [CKRecord.Reference] else { continue }
                let kept = references.filter { !myUserIDs.contains($0.recordID) }
                guard kept.count != references.count else { continue }
                house["users"] = kept
                housesToSave.append(house)
            }
            if !housesToSave.isEmpty {
                _ = try? await sharedDB.modifyRecords(
                    saving: housesToSave,
                    deleting: [],
                    savePolicy: .changedKeys,
                    atomically: false
                )
            }
        }
        
        do {
            try await deleteRecordsIgnoringMissing(Array(myUserIDs), in: sharedDB)
        } catch {
            errorMessage = UserFacingError.message(for: error, doing: .delete)
            if requireFootprintRemoval { return false }
        }
        
        var shareIDs = Set(
            records
                .filter { $0 is CKShare || $0.recordType == CKRecord.SystemType.share }
                .map { $0.recordID }
        )
        for house in houses {
            if let shareReference = house.share {
                shareIDs.insert(shareReference.recordID)
            }
        }
        
        var left = false
        
        if !shareIDs.isEmpty {
            do {
                try await deleteRecordsIgnoringMissing(Array(shareIDs), in: sharedDB)
                left = true
            } catch {
                errorMessage = UserFacingError.message(for: error, doing: .leave)
            }
        }
        
        if !left {
            do {
                _ = try await sharedDB.deleteRecordZone(withID: zoneID)
                left = true
            } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
                left = true
            } catch {
                errorMessage = UserFacingError.message(for: error, doing: .leave)
            }
        }
        
        guard left else { return false }
        
        clearPendingJoin(ifMatching: zoneID)
        invalidateSessionCache()
        return true
    }
    
    /// Leaves the shared house in `zoneID` on behalf of this account (e.g. switching houses).
    func leaveSharedHouse(in zoneID: CKRecordZone.ID) async -> Bool {
        let ownerRecordName = await fetchCurrentUserRecordID()?.recordName
        var profileIDs: [CKRecord.ID] = []
        if let ownerRecordName {
            profileIDs = (try? await privateProfileRecordIDs(ownerRecordName: ownerRecordName)) ?? []
        }
        
        let left = await unlinkFromSharedZone(
            zoneID,
            ownerRecordName: ownerRecordName,
            profileIDs: profileIDs,
            requireFootprintRemoval: false
        )
        if left { await UserProfileCache.shared.removeAll() }
        return left
    }
    
    /// Leaves every house shared with this account, removing its member records first.
    ///
    /// - Returns: `true` when the account is no longer attached to any shared house.
    func unlinkFromAllSharedZones() async -> Bool {
        let zones: [CKRecordZone]
        do {
            zones = try await sharedDB.allRecordZones()
        } catch {
            errorMessage = UserFacingError.message(for: error, doing: .share)
            return false
        }
        
        guard !zones.isEmpty else { return true }
        
        let ownerRecordName = await fetchCurrentUserRecordID()?.recordName
        var profileIDs: [CKRecord.ID] = []
        if let ownerRecordName {
            profileIDs = (try? await privateProfileRecordIDs(ownerRecordName: ownerRecordName)) ?? []
        }
        
        var allLeft = true
        for zone in zones where zone.zoneID.ownerName != CKCurrentUserDefaultName {
            let left = await unlinkFromSharedZone(
                zone.zoneID,
                ownerRecordName: ownerRecordName,
                profileIDs: profileIDs,
                requireFootprintRemoval: true
            )
            if !left { allLeft = false }
        }
        
        invalidateSessionCache()
        return allLeft
    }
    
    // MARK: - Account deletion
    
    /// Deletes everything this account has in the app
    ///
    /// - Returns: `true` on success; otherwise ``errorMessage`` says why.
    func deleteCurrentAccount() async -> Bool {
        invalidateSessionCache()
        
        guard await unlinkFromAllSharedZones() else { return false }
        
        do {
            _ = try await privateDB.deleteRecordZone(withID: houseZoneID)
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            // Nothing private left to delete.
        } catch {
            errorMessage = UserFacingError.message(for: error, doing: .delete)
            return false
        }
        
        clearCurrentUser()
        clearPendingJoin()
        await UserProfileCache.shared.removeAll()
        
        _ = await createZoneIfNeeded(force: true)
        return true
    }
    
    // MARK: - Helpers
    
    /// Reads every record in a zone, throwing instead of swallowing errors (unlike
    /// ``fetchZoneRecords(_:inZone:)``), so callers can tell "empty" from "failed".
    private func scanZone(_ zoneID: CKRecordZone.ID, in database: CKDatabase) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        var token: CKServerChangeToken?
        
        repeat {
            let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
            for (_, result) in changes.modificationResultsByID {
                if let record = try? result.get().record {
                    records.append(record)
                }
            }
            token = changes.moreComing ? changes.changeToken : nil
        } while token != nil
        
        return records
    }
    
    /// Deletes records, treating ones that are already gone as success.
    /// Unassigns every pending chore of the given members, so they show up as "tarefas para
    /// pegar" for the people who stay.
    ///
    /// Without this the leaving member's records kept pointing at a user that no longer exists:
    /// the occurrences and one-off chores stayed assigned to nobody-in-particular, never showed
    /// in the unassigned list, and nobody could take them over.
    ///
    /// - Recurring occurrences not yet completed drop the member from `users` (and lose the
    ///   calendar event id, which belonged to the leaving member's device). Once nobody is left
    ///   they count as unassigned. Completed ones keep their users, as history.
    /// - One-off chores not yet done drop the member from `currentResponsible` and
    ///   `allResponsibleUsers`; once nobody is left they count as unassigned.
    private func releaseAssignments(of userIDs: Set<CKRecord.ID>, in records: [CKRecord]) async {
        guard !userIDs.isEmpty else { return }
        
        var toSave: [CKRecord] = []
        
        for record in records {
            switch record.recordType {
            case RecurrentAssignmentModel.recordType:
                guard record["isCompleted"] as? Bool == false,
                      let users = record["users"] as? [CKRecord.Reference]
                else { continue }
                
                let kept = users.filter { !userIDs.contains($0.recordID) }
                guard kept.count != users.count else { continue }
                
                record["users"] = kept
                record["calendarEventIdentifier"] = nil
                toSave.append(record)
                
            case ChoreModel.recordType:
                guard record["isDone"] as? Bool == false else { continue }
                
                var changed = false
                if let current = record["currentResponsible"] as? CKRecord.Reference,
                   userIDs.contains(current.recordID) {
                    record["currentResponsible"] = nil
                    changed = true
                }
                if let all = record["allResponsibleUsers"] as? [CKRecord.Reference] {
                    let kept = all.filter { !userIDs.contains($0.recordID) }
                    if kept.count != all.count {
                        record["allResponsibleUsers"] = kept
                        changed = true
                    }
                }
                if changed {
                    record["calendarEventIdentifier"] = nil
                    toSave.append(record)
                }
                
            default:
                continue
            }
        }
        
        guard !toSave.isEmpty else { return }
        
        // Best effort: failing here must not stop the member from leaving.
        _ = try? await sharedDB.modifyRecords(
            saving: toSave,
            deleting: [],
            savePolicy: .changedKeys,
            atomically: false
        )
    }
    
    /// Deletes `recordIDs`, treating records that are already gone as deleted.
    private func deleteRecordsIgnoringMissing(_ recordIDs: [CKRecord.ID], in database: CKDatabase) async throws {
        guard !recordIDs.isEmpty else { return }
        
        let (_, deleteResults) = try await database.modifyRecords(
            saving: [],
            deleting: recordIDs,
            savePolicy: .ifServerRecordUnchanged,
            atomically: false
        )
        
        for (_, result) in deleteResults {
            if case .failure(let error) = result {
                if let ckError = error as? CKError, ckError.code == .unknownItem { continue }
                throw error
            }
        }
    }
}

extension View {
    /// Blocks the screen (see ``BlockingOperationOverlay``) while
    /// ``CloudKitManager/pruneOrphanedSharedMemberships()`` is unlinking an orphaned house, so
    /// the user can't navigate mid-unlink.
    func blockingWhileUnlinkingOrphanedHouse() -> some View {
        blockingOperation(
            isPresented: Binding(
                get: { SharedMembershipCleanup.shared.isUnlinking },
                set: { _ in }
            ),
            message: "Desvinculando de uma casa antiga..."
        )
    }
}
