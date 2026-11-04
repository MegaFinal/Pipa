//
//  OnboardingRollbackJournal.swift
//  Cognitive-Work
//

import CloudKit
import Foundation

/// Records which CloudKit records each onboarding step created, so going back can undo
/// exactly that step and nothing else.
///
/// Persisted in `UserDefaults`, like ``OnboardingStateMachine``'s progress: a user who closes
/// the app mid-onboarding and taps "voltar" after relaunching still has the right records
/// deleted.
///
/// Which step owns which field:
/// - ``OnboardingNavigationSteps/createProfile``: ``createdProfile`` (and ``joinedMembership``
///   when the invited user joins right after creating the profile)
/// - ``OnboardingNavigationSteps/chooseFreeTime``: ``freeTimeRecords`` (only when the user
///   already belongs to a house; otherwise free time is kept locally as pending)
/// - ``OnboardingNavigationSteps/createOrEnterHome``: ``createdHouse`` (its whole hierarchy)
/// - ``OnboardingNavigationSteps/chooseRooms``: ``createdRooms``
struct OnboardingRollbackJournal: Codable {

    /// A `CKRecord.ID` in a form that can be encoded.
    struct StoredRecordID: Codable, Hashable {
        /// The record's name.
        var recordName: String
        /// The name of the record's zone.
        var zoneName: String
        /// The owner of the record's zone.
        var zoneOwnerName: String

        /// Stores `recordID` in an encodable form.
        init(_ recordID: CKRecord.ID) {
            recordName = recordID.recordName
            zoneName = recordID.zoneID.zoneName
            zoneOwnerName = recordID.zoneID.ownerName
        }

        /// The stored ID turned back into a `CKRecord.ID`.
        var recordID: CKRecord.ID {
            CKRecord.ID(
                recordName: recordName,
                zoneID: CKRecordZone.ID(zoneName: zoneName, ownerName: zoneOwnerName)
            )
        }
    }

    /// Private profile created by `OnboardingViewModel.createUser()`.
    var createdProfile: StoredRecordID?

    /// In-house member record created by `OnboardingViewModel.joinHouse()`.
    var joinedMembership: StoredRecordID?

    /// House created by `OnboardingViewModel.createHouseAndLinkUser()`.
    var createdHouse: StoredRecordID?

    /// Availability slots saved straight on the in-house user by the free-time step.
    var freeTimeRecords: [StoredRecordID] = []

    /// Rooms created by `OnboardingViewModel.saveSelectedRooms()`.
    var createdRooms: [StoredRecordID] = []
    
    /// Chores created by `OnboardingViewModel.createDefaultChores()`. Read by the division
    /// step, which fetches them by ID: a query right after the save may not return them yet.
    var createdChores: [StoredRecordID] = []

    /// Last free time the user picked (minutes per day, Monday first). Lets the choice be
    /// restored as pending when the house it was written to is deleted.
    var lastFreeTimeMinutes: [Int]?

    // MARK: - Persistence

    /// The `UserDefaults` key the journal is saved under.
    private static let storageKey = "onboarding.rollbackJournal"

    /// The saved journal, or an empty one when there is none.
    static func load() -> OnboardingRollbackJournal {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let journal = try? JSONDecoder().decode(OnboardingRollbackJournal.self, from: data)
        else { return OnboardingRollbackJournal() }
        return journal
    }

    /// Saves the journal in `UserDefaults`.
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    /// Deletes the saved journal (when the onboarding ends or starts over).
    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
