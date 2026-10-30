//
//  FreeTimeSyncService.swift
//  Cognitive-Work
//

import Foundation

// MARK: - Documentation
//
// # Free time: where it lives and how it is kept in sync
//
// A person has two `UserModel` records (see `CloudKitManager.houseUserRecordID(for:inHouseZone:)`):
//
// - the **private profile**: lives in the user's own private zone and survives leaving or deleting
//   a house. It is the *source of truth* for free time.
// - the **house (public) profile**: a copy inside the house's zone, visible to housemates and read
//   by the scheduler. It is deleted when the member leaves the house.
//
// Each profile points at its own `AvailableTimeModel` records through `availableTime`
// (up to 7 weekdays x 4 weeks), so free time is stored twice and has to be kept consistent.
//
// ## Write path (`save`)
// 1. Private profile first (`UserModel.setAvailableTimes`). If this fails nothing else is written,
//    so the two profiles can never diverge because of a half-applied edit: the error is thrown.
// 2. The value is remembered as *pending* (UserDefaults, `onboarding.pendingFreeTime`): "the house
//    profile does not have this yet".
// 3. House profile (`UserModel.setAvailableTimes` on the in-house copy). On success the pending
//    mark is cleared. If there is no house yet the pending mark stays and is flushed when the
//    house is created or joined (`flushPending`). If the write fails after retries the outcome is
//    `.publicSyncPending` (not an error for the user) and the sync is retried by `reconcile`.
//
// ## Read path (`restore`)
// Private profile first, then the house profile (accounts created before this change only had
// free time in the house copy). A value found only in the house profile is copied back to the
// private one, so it survives leaving the house.
//
// ## Conflict policy (`reconcile`)
// When the two profiles differ (two devices of the same iCloud account edited at the same time
// and their writes interleaved, or one write failed) the **private profile wins**, with one
// exception: accounts from before this change may hold an *old* free time on the private profile
// and a current one on the house profile. Every save creates slots for the current week and the
// next three, so the date of a profile's latest slot says how recent its value is. If the house
// profile's latest slot is strictly newer, it wins and the private profile is updated instead.
// `reconcile` runs when the app opens (ContentView) and right before leaving or deleting a house.
//
// ## CloudKit queries involved (no new record types, fields or indexes)
// - read private profile: `CloudKitManager.fetchMyUser()` (direct read by remembered recordName,
//   `ownerRecordName` query as fallback)
// - read house profile: `CloudKitManager.fetchMyHouseUser()` (direct read, derived recordID)
// - read slots: `CloudKitManager.fetchRecordsByRecordReference(for: AvailableTimeModel.self, ...)`
//   using `UserModel.availableTimeReference`
// - write: `UserModel.setAvailableTimes(_:)` = batch save of the new slots, update the user's
//   `availableTime` reference list, delete the previous slots. If updating the reference list
//   fails, the model's in-memory references are restored. Slots already saved are left in place
//   on purpose: an unreferenced slot is harmless, while deleting after an ambiguous timeout
//   could leave the profile pointing at records that no longer exist.

// MARK: - Errors & results

/// Error thrown by a ``FreeTimeProfileStore``.
enum FreeTimeStoreError: Error, Equatable {
    /// Might work if tried again (network, throttling, a concurrent write...).
    case transient(String)
    /// Retrying cannot help (e.g. the profile has no record yet).
    case permanent(String)
}

/// Error thrown by ``FreeTimeSyncService/save(minutes:)``.
enum FreeTimeSyncError: Error, Equatable, LocalizedError {
    /// The minutes are not a valid week.
    case invalidInput
    /// There is no private profile to write to (not created yet, or it could not be loaded).
    case privateProfileUnavailable
    /// The private profile could not be written. The house profile was left untouched.
    case privateWriteFailed(String)

    /// A short message describing the error (in English, for logs).
    var errorDescription: String? {
        switch self {
        case .invalidInput:
            return "Invalid free time."
        case .privateProfileUnavailable:
            return "Private profile unavailable."
        case .privateWriteFailed(let reason):
            return "Could not save free time on the private profile: \(reason)"
        }
    }
}

/// What happened when free time was saved.
enum FreeTimeSaveOutcome: Equatable {
    /// Saved on both profiles.
    case synced
    /// Saved on the private profile. There is no house yet; the house profile gets it on
    /// create/join.
    case privateOnly
    /// Saved on the private profile; writing the house profile failed after retries. It stays
    /// pending and is retried by ``FreeTimeSyncService/reconcile()``.
    case publicSyncPending
}

/// Result of ``FreeTimeSyncService/restore()``.
enum FreeTimeRestoreResult: Equatable {
    /// Minutes per weekday, Monday first.
    case found([Int])
    /// Both profiles were read and neither has free time.
    case none
    /// It could not be determined (network etc.). Not the same as ``none``.
    case unavailable
}

/// Result of ``FreeTimeSyncService/reconcile()``.
enum FreeTimeReconcileResult: Equatable {
    /// Both profiles already have the same free time.
    case alreadyInSync
    /// The house profile was overwritten with the private value.
    case updatedPublic
    /// The private profile was written from the house profile (it had nothing, or older data).
    case updatedPrivate
    /// Neither profile has free time.
    case nothingToSync
    /// Private profile is the only one that exists (no house yet).
    case noHouse
    /// A read or write failed; the pending mark (if any) was kept for a later retry.
    case failed
}

// MARK: - Store abstraction

/// A profile's free time as stored.
struct FreeTimeSnapshot: Equatable {
    /// Minutes per weekday, Monday first (7 entries).
    var minutes: [Int]
    /// Date of the latest stored slot. Each save creates the current week and the next three, so
    /// this orders saves made in different weeks.
    var lastSlotDay: Date
}

/// One profile's copy of the user's free time.
@MainActor
protocol FreeTimeProfileStore {
    /// The stored free time, or `nil` when the profile has none.
    func loadSnapshot() async throws -> FreeTimeSnapshot?
    /// Replaces the profile's free time.
    func saveMinutes(_ minutes: [Int]) async throws
}

// MARK: - Service

/// Keeps the user's free time on the private profile and on the house profile.
/// See the documentation at the top of this file.
@MainActor
final class FreeTimeSyncService {

    /// How many times a store operation is attempted, and how long to wait in between.
    struct RetryPolicy {
        var maxAttempts: Int = 3
        var baseDelay: Duration = .milliseconds(400)

        static let noRetry = RetryPolicy(maxAttempts: 1, baseDelay: .zero)
    }

    /// `UserDefaults` key of the free time waiting to be copied to the house profile.
    static let pendingKey = "onboarding.pendingFreeTime"

    /// Gives the store of the private profile, or `nil` when unavailable.
    private let privateProvider: () async -> FreeTimeProfileStore?
    /// Gives the store of the house profile, or `nil` when the user has no house.
    private let publicProvider: () async -> FreeTimeProfileStore?
    /// Where the pending free time is saved.
    private let defaults: UserDefaults
    /// How transient errors are retried.
    private let retryPolicy: RetryPolicy
    /// Waits between retries (replaced in tests so they don't wait).
    private let sleep: (Duration) async -> Void

    /// - Parameters:
    ///   - privateProvider: Returns the private profile's store, or `nil` when unavailable.
    ///   - publicProvider: Returns the house profile's store, or `nil` when the user has no house.
    ///   - defaults: Where the pending mark is persisted.
    ///   - retryPolicy: Retries for transient store errors.
    ///   - sleep: Injected so tests do not wait.
    init(
        privateProvider: @escaping () async -> FreeTimeProfileStore?,
        publicProvider: @escaping () async -> FreeTimeProfileStore?,
        defaults: UserDefaults = .standard,
        retryPolicy: RetryPolicy = RetryPolicy(),
        sleep: @escaping (Duration) async -> Void = { _ = try? await Task.sleep(for: $0) }
    ) {
        self.privateProvider = privateProvider
        self.publicProvider = publicProvider
        self.defaults = defaults
        self.retryPolicy = retryPolicy
        self.sleep = sleep
    }

    // MARK: Pending mark

    /// Free time already on the private profile but not (known to be) on the house profile yet
    /// (minutes per weekday, Monday first).
    var pendingPublicSync: [Int]? {
        get { defaults.array(forKey: Self.pendingKey) as? [Int] }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Self.pendingKey)
            } else {
                defaults.removeObject(forKey: Self.pendingKey)
            }
        }
    }

    // MARK: Save

    /// Saves the week on the private profile and then on the house profile.
    ///
    /// - Throws: ``FreeTimeSyncError`` when the private profile cannot be written. A failure on
    ///   the house profile is *not* thrown: see ``FreeTimeSaveOutcome/publicSyncPending``.
    @discardableResult
    func save(minutes rawMinutes: [Int]) async throws -> FreeTimeSaveOutcome {
        guard Self.isValid(rawMinutes) else { throw FreeTimeSyncError.invalidInput }
        let minutes = Self.normalized(rawMinutes)

        guard let privateStore = await privateProvider() else {
            throw FreeTimeSyncError.privateProfileUnavailable
        }
        do {
            try await withRetry { try await privateStore.saveMinutes(minutes) }
        } catch {
            throw FreeTimeSyncError.privateWriteFailed(Self.describe(error))
        }

        // The private profile has the new value; the house profile does not, until proven.
        pendingPublicSync = minutes

        guard let publicStore = await publicProvider() else { return .privateOnly }
        do {
            try await withRetry { try await publicStore.saveMinutes(minutes) }
            pendingPublicSync = nil
            return .synced
        } catch {
            return .publicSyncPending
        }
    }

    // MARK: Flush

    /// Pushes the pending value to the house profile (used right after creating/joining a house).
    ///
    /// - Returns: `true` when nothing is pending or the write succeeded.
    @discardableResult
    func flushPending() async -> Bool {
        guard let minutes = pendingPublicSync else { return true }
        guard let publicStore = await publicProvider() else { return false }
        do {
            try await withRetry { try await publicStore.saveMinutes(minutes) }
            pendingPublicSync = nil
            return true
        } catch {
            return false
        }
    }

    // MARK: Restore

    /// The user's free time: private profile first, then the house profile.
    func restore() async -> FreeTimeRestoreResult {
        var privateWasRead = false

        if let privateStore = await privateProvider() {
            do {
                if let snapshot = try await withRetry({ try await privateStore.loadSnapshot() }) {
                    return .found(Self.normalized(snapshot.minutes))
                }
                privateWasRead = true
            } catch {
                // Fall through to the house profile.
            }
        }

        guard let publicStore = await publicProvider() else {
            // No house profile: the private profile is the whole picture.
            return privateWasRead ? FreeTimeRestoreResult.none : .unavailable
        }

        do {
            guard let snapshot = try await withRetry({ try await publicStore.loadSnapshot() }) else {
                return privateWasRead ? FreeTimeRestoreResult.none : .unavailable
            }
            let minutes = Self.normalized(snapshot.minutes)
            // Older accounts only had it here: keep a copy that survives leaving the house.
            if privateWasRead, let privateStore = await privateProvider() {
                _ = try? await withRetry { try await privateStore.saveMinutes(minutes) }
            }
            return .found(minutes)
        } catch {
            return .unavailable
        }
    }

    /// Brings the saved free time back as *pending*, so the next house the user creates or joins
    /// receives it (via ``flushPending()``) without asking again.
    ///
    /// - Returns: `true` when free time is known (already pending, or found on a profile).
    ///   `false` when there is none or it could not be read.
    func restoreAsPending() async -> Bool {
        if pendingPublicSync != nil { return true }
        guard case .found(let minutes) = await restore() else { return false }
        pendingPublicSync = minutes
        return true
    }

    // MARK: Reconcile

    /// Makes the two profiles agree. The private profile wins unless the house profile is
    /// strictly more recent; see the file documentation.
    @discardableResult
    func reconcile() async -> FreeTimeReconcileResult {
        guard let privateStore = await privateProvider() else { return .failed }

        var privateSnapshot: FreeTimeSnapshot?
        do {
            privateSnapshot = try await withRetry { try await privateStore.loadSnapshot() }
        } catch {
            return .failed
        }

        // A pending value means the private write succeeded but the profile reads back empty
        // (e.g. its slots were lost): heal it before comparing.
        if privateSnapshot == nil, let pending = pendingPublicSync {
            do {
                try await withRetry { try await privateStore.saveMinutes(pending) }
                privateSnapshot = try await withRetry { try await privateStore.loadSnapshot() }
            } catch {
                return .failed
            }
        }

        guard let publicStore = await publicProvider() else {
            return privateSnapshot == nil ? .nothingToSync : .noHouse
        }

        let publicSnapshot: FreeTimeSnapshot?
        do {
            publicSnapshot = try await withRetry { try await publicStore.loadSnapshot() }
        } catch {
            return .failed
        }

        switch (privateSnapshot, publicSnapshot) {
        case (nil, nil):
            return .nothingToSync

        case (nil, let house?):
            return await copy(house.minutes, to: privateStore, success: .updatedPrivate)

        case (let owner?, nil):
            return await pushToPublic(owner.minutes, store: publicStore)

        case (let owner?, let house?):
            let ownerMinutes = Self.normalized(owner.minutes)
            let houseMinutes = Self.normalized(house.minutes)
            if ownerMinutes == houseMinutes {
                pendingPublicSync = nil
                return .alreadyInSync
            }
            if house.lastSlotDay > owner.lastSlotDay {
                return await copy(houseMinutes, to: privateStore, success: .updatedPrivate)
            }
            return await pushToPublic(ownerMinutes, store: publicStore)
        }
    }

    /// Saves `minutes` to `store`, with retries.
    /// - Returns: `success` when it worked, or a failure result.
    private func copy(
        _ minutes: [Int],
        to store: FreeTimeProfileStore,
        success: FreeTimeReconcileResult
    ) async -> FreeTimeReconcileResult {
        do {
            try await withRetry { try await store.saveMinutes(Self.normalized(minutes)) }
            pendingPublicSync = nil
            return success
        } catch {
            return .failed
        }
    }

    /// Saves `minutes` to the house profile. If it fails, keeps them as pending so a later
    /// ``reconcile()`` tries again.
    private func pushToPublic(_ minutes: [Int], store: FreeTimeProfileStore) async -> FreeTimeReconcileResult {
        do {
            try await withRetry { try await store.saveMinutes(Self.normalized(minutes)) }
            pendingPublicSync = nil
            return .updatedPublic
        } catch {
            pendingPublicSync = Self.normalized(minutes)
            return .failed
        }
    }

    // MARK: Helpers

    /// Runs `operation`, retrying transient errors with a growing delay.
    private func withRetry<T>(_ operation: () async throws -> T) async throws -> T {
        var attempt = 1
        while true {
            do {
                return try await operation()
            } catch FreeTimeStoreError.permanent(let reason) {
                throw FreeTimeStoreError.permanent(reason)
            } catch {
                guard attempt < retryPolicy.maxAttempts else { throw error }
                await sleep(retryPolicy.baseDelay * attempt)
                attempt += 1
            }
        }
    }

    /// A readable reason for `error`.
    private static func describe(_ error: Error) -> String {
        switch error {
        case FreeTimeStoreError.transient(let reason), FreeTimeStoreError.permanent(let reason):
            return reason
        default:
            return UserFacingError.message(for: error)
        }
    }

    /// A week has at most 7 entries, none negative, and at least one day with free time.
    static func isValid(_ minutes: [Int]) -> Bool {
        !minutes.isEmpty
            && minutes.count <= 7
            && minutes.allSatisfy { $0 >= 0 }
            && minutes.contains { $0 > 0 }
    }

    /// Always 7 entries (missing days are 0), so two weeks can be compared with `==`.
    static func normalized(_ minutes: [Int]) -> [Int] {
        let week = Array(minutes.prefix(7))
        return week + Array(repeating: 0, count: 7 - week.count)
    }

    /// The snapshot of a list of stored slots (`nil` when there are none). When several slots
    /// fall on the same weekday (one per week) the latest one gives the minutes.
    static func snapshot(
        from slots: [(day: Date, minutes: Int)],
        calendar: Calendar = .current
    ) -> FreeTimeSnapshot? {
        guard let lastSlotDay = slots.map { $0.day }.max() else { return nil }

        var latest: [Int: (day: Date, minutes: Int)] = [:]
        for slot in slots {
            // Calendar weekday: 1 = Sunday ... 7 = Saturday  ->  0 = Monday ... 6 = Sunday.
            let index = (calendar.component(.weekday, from: slot.day) + 5) % 7
            if let current = latest[index], current.day >= slot.day { continue }
            latest[index] = slot
        }
        return FreeTimeSnapshot(
            minutes: (0..<7).map { latest[$0]?.minutes ?? 0 },
            lastSlotDay: lastSlotDay
        )
    }
}

// MARK: - Where to go after the welcome screen

/// Decides where the welcome screen leads. A returning user (profile and free time already
/// known, e.g. after leaving a house) goes straight to "create or enter a house".
enum OnboardingRouting {
    /// The step after the welcome screen.
    /// - Parameters:
    ///   - hasProfile: Whether the user already has a profile.
    ///   - hasFreeTime: Whether the user already told their free time.
    /// - Returns: Create the profile, choose free time, or go straight to create/enter a house.
    static func stepAfterWelcome(hasProfile: Bool, hasFreeTime: Bool) -> OnboardingNavigationSteps {
        guard hasProfile else { return .createProfile }
        return hasFreeTime ? .createOrEnterHome : .chooseFreeTime
    }
}
