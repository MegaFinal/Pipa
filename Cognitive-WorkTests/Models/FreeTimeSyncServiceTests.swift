//
//  FreeTimeSyncServiceTests.swift
//  Cognitive-Work
//

import Testing
import Foundation
@testable import Cognitive_Work

// MARK: - Test doubles

/// An in-memory profile (private or house) whose reads and writes can be made to fail.
@MainActor
private final class FakeFreeTimeStore: FreeTimeProfileStore {
    var snapshot: FreeTimeSnapshot?
    /// Day recorded as the latest slot by the next successful save.
    var saveDay: Date

    /// The next N loads / saves throw a transient error.
    var failingLoads = 0
    var failingSaves = 0
    /// Every save throws a permanent error.
    var permanentSaveFailure = false

    private(set) var loadCalls = 0
    private(set) var saveCalls = 0

    nonisolated init(snapshot: FreeTimeSnapshot? = nil, saveDay: Date = Date(timeIntervalSince1970: 1_000_000)) {
        self.snapshot = snapshot
        self.saveDay = saveDay
    }

    func loadSnapshot() async throws -> FreeTimeSnapshot? {
        loadCalls += 1
        if failingLoads > 0 {
            failingLoads -= 1
            throw FreeTimeStoreError.transient("offline")
        }
        return snapshot
    }

    func saveMinutes(_ minutes: [Int]) async throws {
        saveCalls += 1
        if permanentSaveFailure { throw FreeTimeStoreError.permanent("no record") }
        if failingSaves > 0 {
            failingSaves -= 1
            throw FreeTimeStoreError.transient("offline")
        }
        snapshot = FreeTimeSnapshot(minutes: FreeTimeSyncService.normalized(minutes), lastSlotDay: saveDay)
    }
}

/// The world around the service: the private profile, the current house's profile (which can
/// disappear and be replaced, like leaving a house and joining another) and an isolated
/// `UserDefaults` for the pending mark.
@MainActor
private final class Env {
    let suiteName = "FreeTimeSyncServiceTests.\(UUID().uuidString)"
    let defaults: UserDefaults

    var privateStore: FakeFreeTimeStore?
    var houseStore: FakeFreeTimeStore?
    var sleeps: [Duration] = []

    init(privateStore: FakeFreeTimeStore? = FakeFreeTimeStore(), houseStore: FakeFreeTimeStore? = FakeFreeTimeStore()) {
        defaults = UserDefaults(suiteName: suiteName)!
        self.privateStore = privateStore
        self.houseStore = houseStore
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    /// A new service over the same world, like the app being relaunched.
    func makeService(retry: FreeTimeSyncService.RetryPolicy = .init()) -> FreeTimeSyncService {
        FreeTimeSyncService(
            privateProvider: { self.privateStore },
            publicProvider: { self.houseStore },
            defaults: defaults,
            retryPolicy: retry,
            sleep: { duration in self.sleeps.append(duration) }
        )
    }
}

private let week = [60, 120, 0, 30, 0, 300, 0]

private func thrownError(from body: () async throws -> Void) async -> Error? {
    do {
        try await body()
        return nil
    } catch {
        return error
    }
}

// MARK: - Tests

@MainActor
struct FreeTimeSyncServiceTests {

    // MARK: Saving

    @Test func saveWritesBothProfiles() async throws {
        let env = Env()
        let service = env.makeService()

        let outcome = try await service.save(minutes: week)

        #expect(outcome == .synced)
        #expect(env.privateStore?.snapshot?.minutes == week)
        #expect(env.houseStore?.snapshot?.minutes == week)
        #expect(service.pendingPublicSync == nil)
    }

    @Test func saveWithoutAHouseKeepsItOnTheProfileAndPending() async throws {
        let env = Env(houseStore: nil)
        let service = env.makeService()

        let outcome = try await service.save(minutes: week)

        #expect(outcome == .privateOnly)
        #expect(env.privateStore?.snapshot?.minutes == week)
        #expect(service.pendingPublicSync == week)
    }

    @Test func pendingFreeTimeIsWrittenToTheHouseWhenItExists() async throws {
        let env = Env(houseStore: nil)
        let service = env.makeService()
        try await service.save(minutes: week)

        // The user creates or joins a house.
        env.houseStore = FakeFreeTimeStore()
        let flushed = await service.flushPending()

        #expect(flushed)
        #expect(env.houseStore?.snapshot?.minutes == week)
        #expect(service.pendingPublicSync == nil)
    }

    @Test func flushWithoutAHouseKeepsTheValuePending() async throws {
        let env = Env(houseStore: nil)
        let service = env.makeService()
        try await service.save(minutes: week)

        let flushed = await service.flushPending()

        #expect(flushed == false)
        #expect(service.pendingPublicSync == week)
    }

    @Test func invalidWeeksAreRejectedWithoutWriting() async {
        let env = Env()
        let service = env.makeService()

        for invalid in [[], [0, 0, 0, 0, 0, 0, 0], [-30, 60, 0, 0, 0, 0, 0], [30, 30, 30, 30, 30, 30, 30, 30]] {
            let thrown = await thrownError { _ = try await service.save(minutes: invalid) }
            #expect(thrown as? FreeTimeSyncError == .invalidInput)
        }
        #expect(env.privateStore?.saveCalls == 0)
        #expect(env.houseStore?.saveCalls == 0)
    }

    @Test func savingWithoutAPrivateProfileFails() async {
        let env = Env(privateStore: nil)
        let service = env.makeService()

        let thrown = await thrownError { _ = try await service.save(minutes: week) }

        #expect(thrown as? FreeTimeSyncError == .privateProfileUnavailable)
        #expect(env.houseStore?.saveCalls == 0)
    }

    // MARK: The bug: free time must survive switching houses

    @Test func freeTimeSurvivesLeavingOneHouseAndJoiningAnother() async throws {
        let env = Env()

        // In house A the user picks their free time once.
        try await env.makeService().save(minutes: week)
        #expect(env.houseStore?.snapshot?.minutes == week)

        // They leave house A: the house profile (and its free time) is gone. Then the app
        // relaunches into onboarding.
        env.houseStore = nil
        let afterLeaving = env.makeService()

        // The free time is still known, so the free-time screen is not needed...
        let known = await afterLeaving.restoreAsPending()
        #expect(known)
        #expect(afterLeaving.pendingPublicSync == week)
        #expect(OnboardingRouting.stepAfterWelcome(hasProfile: true, hasFreeTime: known) == .createOrEnterHome)

        // ...and house B receives it without any new input.
        env.houseStore = FakeFreeTimeStore()
        let flushed = await afterLeaving.flushPending()
        #expect(flushed)
        #expect(env.houseStore?.snapshot?.minutes == week)
        #expect(afterLeaving.pendingPublicSync == nil)
    }

    @Test func accountsFromBeforeTheChangeKeepTheirFreeTimeWhenLeaving() async throws {
        // Free time only existed on the house profile.
        let legacy = FreeTimeSnapshot(minutes: week, lastSlotDay: Date(timeIntervalSince1970: 2_000_000))
        let env = Env(privateStore: FakeFreeTimeStore(), houseStore: FakeFreeTimeStore(snapshot: legacy))

        // Leaving a house reconciles first: the private profile is filled from the house one.
        let result = await env.makeService().reconcile()
        #expect(result == .updatedPrivate)

        env.houseStore = nil
        let restored = await env.makeService().restore()
        #expect(restored == .found(week))
    }

    // MARK: Restore

    @Test func restoreReadsThePrivateProfileFirst() async {
        let env = Env(
            privateStore: FakeFreeTimeStore(snapshot: FreeTimeSnapshot(minutes: week, lastSlotDay: .now)),
            houseStore: FakeFreeTimeStore(snapshot: FreeTimeSnapshot(minutes: [30, 0, 0, 0, 0, 0, 0], lastSlotDay: .now))
        )

        #expect(await env.makeService().restore() == .found(week))
        #expect(env.houseStore?.loadCalls == 0)
    }

    @Test func restoreFallsBackToTheHouseProfileAndCopiesItToThePrivateOne() async {
        let env = Env(
            privateStore: FakeFreeTimeStore(),
            houseStore: FakeFreeTimeStore(snapshot: FreeTimeSnapshot(minutes: week, lastSlotDay: .now))
        )

        #expect(await env.makeService().restore() == .found(week))
        #expect(env.privateStore?.snapshot?.minutes == week)
    }

    @Test func restoreTellsNoFreeTimeApartFromAFailedRead() async {
        // Nothing saved anywhere.
        let empty = Env(houseStore: nil)
        #expect(await empty.makeService().restore() == FreeTimeRestoreResult.none)

        // The read failed: that is not "nothing saved".
        let offline = Env(houseStore: nil)
        offline.privateStore?.failingLoads = 10
        #expect(await offline.makeService(retry: .noRetry).restore() == .unavailable)
    }

    @Test func aFailedReadNeverCountsAsHavingFreeTime() async {
        let offline = Env(houseStore: nil)
        offline.privateStore?.failingLoads = 10
        let service = offline.makeService(retry: .noRetry)

        let known = await service.restoreAsPending()

        #expect(known == false)
        #expect(service.pendingPublicSync == nil)
        #expect(OnboardingRouting.stepAfterWelcome(hasProfile: true, hasFreeTime: known) == .chooseFreeTime)
    }

    // MARK: Failed sync between the two profiles

    @Test func aFailedPrivateWriteLeavesTheHouseProfileUntouched() async {
        let env = Env()
        env.privateStore?.failingSaves = 10
        let service = env.makeService(retry: .noRetry)

        let thrown = await thrownError { _ = try await service.save(minutes: week) }

        #expect(thrown as? FreeTimeSyncError == .privateWriteFailed("offline"))
        #expect(env.houseStore?.saveCalls == 0)
        #expect(env.houseStore?.snapshot == nil)
        #expect(service.pendingPublicSync == nil)
    }

    @Test func aFailedHouseWriteKeepsThePrivateValueAndRetriesLater() async throws {
        let env = Env()
        env.houseStore?.failingSaves = 10
        let service = env.makeService(retry: .noRetry)

        let outcome = try await service.save(minutes: week)

        #expect(outcome == .publicSyncPending)
        #expect(env.privateStore?.snapshot?.minutes == week)
        #expect(env.houseStore?.snapshot == nil)
        #expect(service.pendingPublicSync == week)

        // Back online: the next sync (e.g. when the app opens) catches the house profile up.
        env.houseStore?.failingSaves = 0
        let result = await service.reconcile()

        #expect(result == .updatedPublic)
        #expect(env.houseStore?.snapshot?.minutes == week)
        #expect(service.pendingPublicSync == nil)
    }

    @Test func aFailedReconcileKeepsThePendingValue() async throws {
        let env = Env()
        env.houseStore?.failingSaves = 10
        let service = env.makeService(retry: .noRetry)
        try await service.save(minutes: week)

        #expect(await service.reconcile() == .failed)
        #expect(service.pendingPublicSync == week)
    }

    @Test func reconcileFailsWithoutChangingAnythingWhenAProfileCannotBeRead() async {
        let env = Env()
        env.privateStore?.failingLoads = 10
        env.houseStore?.snapshot = FreeTimeSnapshot(minutes: week, lastSlotDay: .now)

        #expect(await env.makeService(retry: .noRetry).reconcile() == .failed)
        #expect(env.privateStore?.saveCalls == 0)
        #expect(env.houseStore?.saveCalls == 0)
    }

    // MARK: Retries

    @Test func transientFailuresAreRetriedWithAGrowingDelay() async throws {
        let env = Env()
        env.privateStore?.failingSaves = 2
        let service = env.makeService(retry: .init(maxAttempts: 3, baseDelay: .milliseconds(100)))

        let outcome = try await service.save(minutes: week)

        #expect(outcome == .synced)
        #expect(env.privateStore?.saveCalls == 3)
        #expect(env.sleeps == [.milliseconds(100), .milliseconds(200)])
    }

    @Test func permanentFailuresAreNotRetried() async {
        let env = Env()
        env.privateStore?.permanentSaveFailure = true
        let service = env.makeService(retry: .init(maxAttempts: 3, baseDelay: .milliseconds(100)))

        let thrown = await thrownError { _ = try await service.save(minutes: week) }

        #expect(thrown as? FreeTimeSyncError == .privateWriteFailed("no record"))
        #expect(env.privateStore?.saveCalls == 1)
        #expect(env.sleeps.isEmpty)
    }

    // MARK: Conflicts

    @Test func whenTheProfilesDifferThePrivateOneWins() async {
        let day = Date(timeIntervalSince1970: 3_000_000)
        let env = Env(
            privateStore: FakeFreeTimeStore(snapshot: FreeTimeSnapshot(minutes: week, lastSlotDay: day)),
            houseStore: FakeFreeTimeStore(snapshot: FreeTimeSnapshot(minutes: [30, 0, 0, 0, 0, 0, 0], lastSlotDay: day))
        )

        #expect(await env.makeService().reconcile() == .updatedPublic)
        #expect(env.houseStore?.snapshot?.minutes == week)
        #expect(env.privateStore?.snapshot?.minutes == week)
    }

    @Test func aMoreRecentHouseProfileBeatsAnOldPrivateOne() async {
        // An old free time left on the private profile by an earlier version of the app.
        let old = Date(timeIntervalSince1970: 1_000_000)
        let recent = old.addingTimeInterval(14 * 86_400)
        let env = Env(
            privateStore: FakeFreeTimeStore(snapshot: FreeTimeSnapshot(minutes: [30, 0, 0, 0, 0, 0, 0], lastSlotDay: old)),
            houseStore: FakeFreeTimeStore(snapshot: FreeTimeSnapshot(minutes: week, lastSlotDay: recent))
        )

        #expect(await env.makeService().reconcile() == .updatedPrivate)
        #expect(env.privateStore?.snapshot?.minutes == week)
        #expect(env.houseStore?.snapshot?.minutes == week)
    }

    @Test func reconcileWhenAlreadyInSyncWritesNothing() async {
        let snapshot = FreeTimeSnapshot(minutes: week, lastSlotDay: .now)
        let env = Env(privateStore: FakeFreeTimeStore(snapshot: snapshot), houseStore: FakeFreeTimeStore(snapshot: snapshot))
        env.defaults.set(week, forKey: FreeTimeSyncService.pendingKey)
        let service = env.makeService()

        #expect(await service.reconcile() == .alreadyInSync)
        #expect(env.privateStore?.saveCalls == 0)
        #expect(env.houseStore?.saveCalls == 0)
        #expect(service.pendingPublicSync == nil)
    }

    @Test func reconcileEdgeCases() async {
        // Neither profile has free time.
        let none = Env()
        #expect(await none.makeService().reconcile() == .nothingToSync)

        // No house: nothing to compare with.
        let noHouse = Env(
            privateStore: FakeFreeTimeStore(snapshot: FreeTimeSnapshot(minutes: week, lastSlotDay: .now)),
            houseStore: nil
        )
        #expect(await noHouse.makeService().reconcile() == .noHouse)

        // The house profile has nothing yet.
        let emptyHouse = Env(
            privateStore: FakeFreeTimeStore(snapshot: FreeTimeSnapshot(minutes: week, lastSlotDay: .now)),
            houseStore: FakeFreeTimeStore()
        )
        #expect(await emptyHouse.makeService().reconcile() == .updatedPublic)
        #expect(emptyHouse.houseStore?.snapshot?.minutes == week)
    }

    @Test func aPendingValueHealsAnEmptyPrivateProfile() async {
        let env = Env(houseStore: nil)
        env.defaults.set(week, forKey: FreeTimeSyncService.pendingKey)

        _ = await env.makeService().reconcile()

        #expect(env.privateStore?.snapshot?.minutes == week)
    }

    // MARK: Reading stored slots

    @Test func snapshotMapsSlotsToWeekdaysMondayFirst() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        func day(_ dayOfMonth: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: dayOfMonth, hour: 12))!
        }

        // 5 Oct 2026 is a Monday, 11 Oct a Sunday, 12 Oct the next Monday.
        let slots: [(day: Date, minutes: Int)] = [
            (day(5), 60),    // Monday
            (day(12), 120),  // Monday a week later: the latest slot gives the value
            (day(11), 300),  // Sunday
            (day(7), 30)     // Wednesday
        ]

        let snapshot = try #require(FreeTimeSyncService.snapshot(from: slots, calendar: calendar))

        #expect(snapshot.minutes == [120, 0, 30, 0, 0, 0, 300])
        #expect(snapshot.lastSlotDay == day(12))
        #expect(FreeTimeSyncService.snapshot(from: [], calendar: calendar) == nil)
    }
}
