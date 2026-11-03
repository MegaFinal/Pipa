//
//  CloudKitFreeTimeStore.swift
//  Cognitive-Work
//

import Foundation
import CloudKit

/// A `UserModel` (private profile or in-house copy) seen as a ``FreeTimeProfileStore``.
///
/// Reads the profile's `availableTime` references; writes through
/// `UserModel.setAvailableTimes(_:)`. `CloudKitManager` reports failures as `false`/`nil` plus
/// ``CloudKitManager/errorMessage``, so they are mapped to ``FreeTimeStoreError`` here.
@MainActor
struct UserModelFreeTimeStore: FreeTimeProfileStore {

    /// The profile whose free time is read and written. `setAvailableTimes` updates its
    /// `availableTimeReference` in place.
    let user: UserModel

    /// Reads the profile's free time.
    /// - Returns: The minutes per weekday, or `nil` when the profile has no free time saved.
    /// - Throws: ``FreeTimeStoreError`` when CloudKit fails.
    func loadSnapshot() async throws -> FreeTimeSnapshot? {
        guard let references = user.availableTimeReference, !references.isEmpty else { return nil }

        guard let slots = await CloudKitManager.shared.fetchRecordsByRecordReference(
            for: AvailableTimeModel.self,
            recordReferences: references
        ) else {
            throw FreeTimeStoreError.transient(
                CloudKitManager.shared.errorMessage ?? UserFacingError.Action.load.message
            )
        }

        return FreeTimeSyncService.snapshot(
            from: slots.map { (day: $0.day, minutes: $0.capacityMinutes) }
        )
    }

    /// Saves `minutes` (one value per weekday, Monday first) as the profile's free time.
    /// - Throws: ``FreeTimeStoreError`` when the profile is not saved yet or CloudKit fails.
    func saveMinutes(_ minutes: [Int]) async throws {
        guard user.recordID != nil else {
            throw FreeTimeStoreError.permanent("The profile has no record yet")
        }

        CloudKitManager.shared.errorMessage = nil
        let times = minutes.map { AvailableTimeModel(capacityMinutes: $0, day: Date()) }

        guard await user.setAvailableTimes(times) else {
            throw FreeTimeStoreError.transient(
                CloudKitManager.shared.errorMessage ?? UserFacingError.Action.save.message
            )
        }
    }
}

extension FreeTimeSyncService {

    /// A service wired to CloudKit.
    ///
    /// - Parameter publicStoreProvider: Overrides how the house profile is resolved. Onboarding
    ///   passes its own, which prefers the in-house record it just created (a read by ID right
    ///   after creating the house may still go through a stale session cache).
    static func live(
        publicStoreProvider: (() async -> FreeTimeProfileStore?)? = nil
    ) -> FreeTimeSyncService {
        let manager = CloudKitManager.shared

        let privateProvider: () async -> FreeTimeProfileStore? = {
            // Never the in-house copy: that one disappears when the user leaves the house.
            guard let profile = await manager.fetchMyUser(), !manager.isHouseUser(profile) else {
                return nil
            }
            return UserModelFreeTimeStore(user: profile)
        }

        let defaultPublicProvider: () async -> FreeTimeProfileStore? = {
            guard let houseUser = await manager.fetchMyHouseUser() else { return nil }
            return UserModelFreeTimeStore(user: houseUser)
        }

        return FreeTimeSyncService(
            privateProvider: privateProvider,
            publicProvider: publicStoreProvider ?? defaultPublicProvider
        )
    }
}
