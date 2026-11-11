//
//  BadgeManager.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 11/11/26.
//

import SwiftUI
import CloudKit

/// Counts the chores each member checks off per kind of default room, and unlocks the room
/// badges (``RoomBadge``) as the counts reach their thresholds.
///
/// Works like ``ScoreManager``: every change is applied to the **server's**
/// ``RoomBadgeProgressModel``, saved only if nobody changed it in between (``AtomicRecordStore``),
/// and fetched again otherwise. So two devices counting at once both count, and a stale copy
/// can't undo anything.
@Observable
final class BadgeManager {

    /// The single instance used by the app.
    static let shared = BadgeManager()

    /// Where the progress is read and saved (CloudKit in the app, in memory in tests).
    @ObservationIgnored private let store: AtomicRecordStore
    /// How many times a save is retried when another device changed the progress at the same time.
    @ObservationIgnored private let maxAttempts = 5

    /// The last progress read or saved on this device, per person (``UserModel/ownerRecordName``).
    private(set) var progressByOwner: [String: RoomBadgeProgressModel] = [:]

    /// Creates the shared instance, backed by CloudKit.
    private convenience init() {
        self.init(store: CloudKitAtomicRecordStore())
    }

    /// - Parameter store: Where the progress is read and saved; tests pass an in-memory one.
    init(store: AtomicRecordStore) {
        self.store = store
    }

    // MARK: - Reading

    /// The progress of `user` on the server: an empty one when they have none yet, the last one
    /// known on this device when it can't be read.
    func progress(of user: UserModel) async -> RoomBadgeProgressModel {
        guard let userID = user.recordID else {
            return RoomBadgeProgressModel(ownerRecordName: user.ownerRecordName)
        }
        let owner = RoomBadgeProgressModel.owner(of: user, userID: userID)
        let id = RoomBadgeProgressModel.recordID(for: user, userID: userID)

        guard let fetched = try? await store.fetch([id]) else {
            return progressByOwner[owner] ?? RoomBadgeProgressModel(ownerRecordName: owner)
        }
        let progress = fetched[id].flatMap(RoomBadgeProgressModel.init(record:))
            ?? RoomBadgeProgressModel(ownerRecordName: owner)
        progressByOwner[owner] = progress
        return progress
    }

    /// How many more one-off chores of each kind of room can count for `user` on `date`
    /// (``RoomBadgeProgressModel/oneOffDailyLimit``), never below 0.
    func countableOneOffs(for user: UserModel, on date: Date = .now) async -> [DefaultRoomsOnboarding: Int] {
        let progress = await progress(of: user)
        let dayKey = RoomBadgeProgressModel.dayKey(for: date)
        var countable: [DefaultRoomsOnboarding: Int] = [:]
        for room in DefaultRoomsOnboarding.allCases {
            let used = progress.oneOffCount(for: room, on: dayKey)
            countable[room] = max(RoomBadgeProgressModel.oneOffDailyLimit - used, 0)
        }
        return countable
    }

    // MARK: - Changing

    /// Adds `changes` to the progress of `user` on the server, unlocking the badges they reach.
    ///
    /// The first change creates the progress, as a child of the user's house.
    ///
    /// - Parameters:
    ///   - changes: Check-offs to add (or take back), per kind of room.
    ///   - user: Whose progress changes.
    ///   - date: The day one-off check-offs are counted on.
    /// - Returns: The badges this change unlocked; empty when none, or when it couldn't be saved.
    @discardableResult
    func apply(_ changes: [RoomBadgeChange], to user: UserModel, on date: Date = .now) async -> [RoomBadge] {
        let changes = changes.filter { $0.delta != 0 }
        guard !changes.isEmpty, let userID = user.recordID else { return [] }

        let owner = RoomBadgeProgressModel.owner(of: user, userID: userID)
        let id = RoomBadgeProgressModel.recordID(for: user, userID: userID)
        let houseID = user.houseReference?.recordID
        let dayKey = RoomBadgeProgressModel.dayKey(for: date)

        for _ in 0..<maxAttempts {
            guard let fetched = try? await store.fetch([id]) else { return [] }

            let (record, current) = RoomBadgeProgressModel.record(
                id,
                in: fetched,
                ownerRecordName: owner,
                houseID: houseID
            )
            var updated = current
            let unlocked = updated.apply(changes, dayKey: dayKey)
            updated.populate(record: record)

            do {
                try await store.saveAtomically([record])
                progressByOwner[owner] = updated
                return unlocked
            } catch AtomicRecordStoreError.conflict {
                // Someone changed this progress meanwhile (or created it): start again from the new value.
                continue
            } catch {
                return []
            }
        }
        return []
    }
}
