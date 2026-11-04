//
//  HouseDataStore.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 08/10/26.
//

import Foundation
import CloudKit

/// Everything the main tabs show, read from CloudKit in a single pass.
struct HouseSnapshot {
    /// Identifies this snapshot, so views can tell when the data was reloaded.
    let id = UUID()

    /// Every chore of the house.
    let chores: [ChoreModel]
    /// The house members, one per person.
    let users: [UserModel]

    /// Every user record of the house, including the extra records of the same person that
    /// ``users`` merges. Used to resolve who a reference points at.
    let userRecords: [UserModel]
    /// Every room of the house.
    let rooms: [RoomModel]
    /// Every chore occurrence of the house.
    let assignments: [RecurrentAssignmentModel]

    /// The signed-in member's record inside the house.
    let houseUser: UserModel?

    /// The signed-in user's private profile (outside the house).
    let privateUser: UserModel?

    /// The house's shopping list, or `nil` if it has none.
    let shopList: ShopListModel?

    /// Every shopping item visible to the user (the list keeps those whose parent it is).
    let shopItems: [ShopListItem]
    /// Every member's rank at the end of each past cycle (``RankHistoryModel``).
    let rankHistory: [RankHistoryModel]

    /// The house's coupons (``CouponModel``), on sale or not.
    let coupons: [CouponModel]

    /// The house's division cycles (``HouseCycleModel``), in no particular order.
    let cycles: [HouseCycleModel]

    /// The house record, or `nil` while the user has no house.
    let houseID: CKRecord.ID?

    /// `user`'s past cycles, oldest first.
    ///
    /// Matches every house record of the same person (see ``userRecords``): the history is
    /// written for the record ``users`` keeps, which may not be the one in ``houseUser``.
    func pastRanks(of user: UserModel?) -> [RankHistoryModel] {
        guard let user else { return [] }
        var ids = Set(userRecords.filter { $0.ownerRecordName == user.ownerRecordName }.compactMap(\.recordID))
        if let userID = user.recordID { ids.insert(userID) }
        return rankHistory
            .filter { ids.contains($0.user.recordID) }
            .sorted { $0.cycleKey < $1.cycleKey }
    }

    /// Returned when the very first load fails. It is never stored in ``HouseDataStore``, so
    /// the next load tries again.
    static let empty = HouseSnapshot(
        chores: [], users: [], userRecords: [], rooms: [], assignments: [],
        houseUser: nil, privateUser: nil, shopList: nil, shopItems: [],
        rankHistory: [], coupons: [], cycles: [], houseID: nil
    )

    /// Whether this is ``empty``, i.e. no data could be loaded yet (not "the house is empty").
    var isPlaceholder: Bool { id == Self.empty.id }
}

/// Loads the house data once and serves it to every tab.
@MainActor
@Observable
final class HouseDataStore {

    /// The single instance shared by every tab.
    static let shared = HouseDataStore()

    // MARK: - State

    /// The latest data, or `nil` until the first load finishes (and after ``reset()``).
    private(set) var snapshot: HouseSnapshot?

    /// `true` when something changed since the data in ``snapshot`` was requested.
    @ObservationIgnored
    private var isStale = true

    /// How many times ``invalidate()`` ran.
    @ObservationIgnored
    private var invalidationCount = 0

    /// The fetch currently running, so simultaneous callers wait for it instead of starting
    /// their own.
    @ObservationIgnored
    private var inFlight: Task<HouseSnapshot?, Never>?

    /// Identifies the newest fetch. An older one that finishes late must not overwrite it.
    @ObservationIgnored
    private var latestFetchID: UUID?

    /// Creates an empty store. The app uses ``shared``; tests can create their own.
    init() {}

    // MARK: - Reading

    /// Whether ``snapshot`` can be used as is, without asking CloudKit again.
    var isUpToDate: Bool {
        snapshot != nil && !isStale
    }

    /// The house data, fetching it only when it is missing or stale.
    @discardableResult
    func load(force: Bool = false) async -> HouseSnapshot {
        if !force {
            if let snapshot, !isStale { return snapshot }
            if let inFlight { return await inFlight.value ?? snapshot ?? .empty }
        }
        return await fetch()
    }

    /// The snapshot already in memory, or a first load if there is none yet.
    func current() async -> HouseSnapshot {
        if let snapshot { return snapshot }
        return await load()
    }

    /// The freshest data available: like ``load(force:)``, but if the snapshot it got was
    /// already outdated when it arrived (a change landed while that fetch was running), asks
    /// once more. Screens that must reflect the latest change should use this.
    @discardableResult
    func loadLatest() async -> HouseSnapshot {
        let snapshot = await load()
        guard !isUpToDate, !Task.isCancelled else { return snapshot }
        return await load()
    }

    #if DEBUG
    /// Fills the store with sample data, so SwiftUI previews don't ask CloudKit.
    func seed(_ snapshot: HouseSnapshot) {
        self.snapshot = snapshot
        isStale = false
    }
    #endif
    
    // MARK: - Invalidation

    /// Marks the snapshot as outdated; the next ``load(force:)`` fetches again.
    func invalidate() {
        invalidationCount &+= 1
        isStale = true
    }

    /// A change reported by CloudKit (push from another device): invalidates and reloads.
    @discardableResult
    func refreshAfterRemoteChange() async -> HouseSnapshot {
        invalidate()
        return await loadLatest()
    }

    /// Forgets everything, e.g. when a different account or house takes over.
    func reset() {
        inFlight?.cancel()
        inFlight = nil
        latestFetchID = nil
        snapshot = nil
        isStale = true
    }

    // MARK: - Fetching

    /// Downloads everything once and keeps it as ``snapshot``.
    ///
    /// When a newer fetch started meanwhile, its result wins. When the download fails, the previous
    /// snapshot is kept and marked stale, so the next load tries again.
    private func fetch() async -> HouseSnapshot {
        let fetchID = UUID()
        latestFetchID = fetchID
        let invalidationsAtStart = invalidationCount

        let task = Task<HouseSnapshot?, Never> {
            do {
                return try await Self.download()
            } catch {
                print("HouseDataStore: refresh failed, keeping the previous data. \(error)")
                return nil
            }
        }
        inFlight = task
        let downloaded = await task.value

        guard latestFetchID == fetchID else { return snapshot ?? downloaded ?? .empty }
        inFlight = nil

        // A failed refresh must not wipe what is on screen: keep the previous snapshot and stay
        // stale, so the next load (tab opened, push, back to foreground) tries again.
        guard let downloaded else {
            isStale = true
            return snapshot ?? .empty
        }

        snapshot = downloaded
        isStale = invalidationCount != invalidationsAtStart
        return downloaded
    }

    /// Every request the tabs need, running in parallel. Throws if any of them fails, so a
    /// network error is never mistaken for an empty house.
    private nonisolated static func download() async throws -> HouseSnapshot {
        let cloud = CloudKitManager.shared

        async let chores = cloud.fetchAllOrThrow(ChoreModel.self)
        async let userRecords = cloud.fetchHouseUserRecordsOrThrow()
        async let rooms = cloud.fetchAllOrThrow(RoomModel.self)
        async let assignments = cloud.fetchAllOrThrow(RecurrentAssignmentModel.self)
        async let houseUser = cloud.currentHouseUser()
        async let privateUser = cloud.fetchMyUser()
        async let shopList = fetchShopList()
        async let shopItems = cloud.fetchAll(ShopListItem.self)
        // Points live in `UserScoreModel`; they are copied onto the users below.
        async let scores = cloud.fetchAll(UserScoreModel.self)
        async let rankHistory = cloud.fetchAll(RankHistoryModel.self)
        async let house = try? cloud.currentHouse()
        async let allCoupons = cloud.fetchAll(CouponModel.self)

        // The cycles are read per house zone, so they wait for the house; the rest keeps running.
        let houseID = await house?.recordID
        async let cycles = fetchCycles(inHouseZone: houseID?.zoneID)

        let records = try await userRecords
        let currentUser = await houseUser
        await UserScoreModel.apply(scores, to: records + [currentUser].compactMap { $0 })

        return try await HouseSnapshot(
            chores: chores,
            users: cloud.deduplicatedByOwner(records),
            userRecords: records,
            rooms: rooms,
            assignments: assignments,
            houseUser: currentUser,
            privateUser: privateUser,
            shopList: shopList,
            shopItems: shopItems,
            rankHistory: rankHistory,
            coupons: allCoupons.filter { coupon in
                houseID.map { coupon.recordID?.zoneID == $0.zoneID } ?? true
            },
            cycles: cycles,
            houseID: houseID
        )
    }

    /// Every cycle of the house in `zoneID`, or none when there is no house.
    private nonisolated static func fetchCycles(inHouseZone zoneID: CKRecordZone.ID?) async -> [HouseCycleModel] {
        guard let zoneID else { return [] }
        return await HouseCycleModel.fetchAll(inHouseZone: zoneID)
    }

    /// The house's shopping list, or `nil` when there is no house or list.
    private nonisolated static func fetchShopList() async -> ShopListModel? {
        guard let house = try? await CloudKitManager.shared.currentHouse() else { return nil }
        return await house.shopList
    }
}
