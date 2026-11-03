//
//  GamificationViewModel.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 15/10/26.
//

import Foundation
import CloudKit

/// Feeds the rewards tab: the user's coins, the house's rooms, and the coupons each room offers.
///
/// A coupon belongs to a room through its task: ``CouponModel/task`` points at a chore, and the
/// chore points at its room. Coins come from the user's ``CoinWalletModel``; prices are
/// recomputed from each chore with ``CouponPricing``.
///
/// Loading also settles closed cycles (``CycleSettlementService/prepareClosedCycles(_:members:houseID:today:)``),
/// so the coins of a finished cycle are ready to be redeemed in the retrospective.
@MainActor
@Observable
final class GamificationViewModel {

    // MARK: - State

    /// Coins the signed-in user can spend.
    private(set) var coins: Int = 0

    /// The signed-in user's points, for the rank shown on the screen.
    private(set) var points: Int = 0

    /// The signed-in user's rank at the end of each past cycle, oldest first.
    private(set) var rankHistory: [RankHistoryModel] = []

    /// Record name of the coupon being bought, so its button shows progress.
    private(set) var buyingCouponName: String?

    /// Message of the last failed purchase, shown in an alert.
    var alertMessage: String?

    /// The house's rooms, as tabs of the coupon list.
    private(set) var rooms: [RoomModel] = []

    /// Coupons of the period with their room's color, symbol and tier, and the members of each
    /// rank. See ``GamificationCatalog``.
    private(set) var catalog: GamificationCatalog = .empty

    /// Whether the first load finished, so the screen can tell "loading" from "empty".
    private(set) var hasLoaded = false

    /// ``UserModel/ownerRecordName`` of the signed-in member, to find their vehicle in the ranking.
    private(set) var myOwnerRecordName: String?

    /// Key of the room the coupon lists are limited to (``key(for:)``); `nil` shows every room.
    var roomFilterKey: String?

    /// Key of the room chosen in the picker; `nil` until the first load picks one.
    var selectedRoomKey: String?

    /// Coupons available in each room, by ``key(for:)``.
    private var couponsByRoom: [String: [CouponModel]] = [:]

    /// Room key (``key(for:)``) of each coupon in ``couponsByRoom``, by the coupon's record name.
    @ObservationIgnored
    private var roomKeyByCoupon: [String: String] = [:]

    /// The house data this screen last showed, so it isn't rebuilt when nothing changed.
    @ObservationIgnored
    private var appliedSnapshotID: UUID?

    /// The signed-in member's record inside the house.
    @ObservationIgnored
    private var houseUser: UserModel?

    /// The house's record ID.
    @ObservationIgnored
    private var houseID: CKRecord.ID?

    /// Key of the latest cycle; purchases belong to it.
    @ObservationIgnored
    private var latestCycleKey: String?

    /// The reload scheduled after a purchase (see ``catchUpDelay``).
    @ObservationIgnored
    private var refreshTask: Task<Void, Never>?

    /// Coupons this device bought in the last ``recentPurchaseWindow``, by record name, as they
    /// are after the purchase.
    ///
    /// A CloudKit query returns a changed record only once the server has indexed the change, a
    /// few seconds after the save, so the reload right after a purchase would still list the
    /// coupon as for sale. These take the place of what the query returned until then.
    @ObservationIgnored
    private var recentPurchases: [String: (coupon: CouponModel, boughtAt: Date)] = [:]

    /// How long a purchase made here overrides what CloudKit returns.
    private static let recentPurchaseWindow: TimeInterval = 120

    /// `true` inside Xcode previews, where CloudKit can't run.
    @ObservationIgnored
    private let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

    // MARK: - Init

    /// Creates an empty view model; data comes from ``HouseDataStore``.
    init() {}

    /// Creates a view model with fixed data, for previews.
    init(
        previewCoins: Int,
        previewPoints: Int = 0,
        previewHistory: [RankHistoryModel] = [],
        rooms: [RoomModel],
        couponsByRoomName: [String: [CouponModel]],
        users: [UserModel] = [],
        myOwnerRecordName: String? = nil
    ) {
        self.coins = previewCoins
        self.points = previewPoints
        self.rankHistory = previewHistory
        self.rooms = rooms
        for room in rooms {
            couponsByRoom[Self.key(for: room)] = couponsByRoomName[room.name] ?? []
        }
        self.selectedRoomKey = rooms.first.map(Self.key(for:))
        self.myOwnerRecordName = myOwnerRecordName
        self.catalog = GamificationCatalog(
            entries: rooms.flatMap { room in
                (couponsByRoomName[room.name] ?? []).map { coupon in
                    CouponEntry(
                        coupon: coupon, roomName: room.name, roomKey: Self.key(for: room),
                        color: room.color, symbol: room.symbol, state: .available
                    )
                }
            },
            users: users
        )
        self.hasLoaded = true
    }

    // MARK: - Derived

    /// Coupons anyone can still buy in this cycle, in the room chosen in the filter.
    var availableEntries: [CouponEntry] { filtered(catalog.availableCoupons) }

    /// Coupons the member holds in this cycle, in the room chosen in the filter.
    var myEntries: [CouponEntry] { filtered(catalog.myCoupons) }

    /// The coupon `entry` stands for, now with the room-limit rule of ``state(of:)``.
    func state(of entry: CouponEntry) -> CouponCard.PurchaseState { state(of: entry.coupon) }

    private func filtered(_ entries: [CouponEntry]) -> [CouponEntry] {
        guard let roomFilterKey else { return entries }
        return entries.filter { $0.roomKey == roomFilterKey }
    }

    /// The room whose coupons are shown.
    var selectedRoom: RoomModel? {
        rooms.first { Self.key(for: $0) == selectedRoomKey }
    }

    /// Coupons of the selected room, cheapest first.
    var selectedCoupons: [CouponModel] {
        guard let selectedRoomKey else { return [] }
        return (couponsByRoom[selectedRoomKey] ?? []).sorted { $0.price < $1.price }
    }

    /// How many coupons `room` has.
    func couponCount(in room: RoomModel) -> Int {
        couponsByRoom[Self.key(for: room)]?.count ?? 0
    }

    /// Whether the member has enough coins for `coupon`.
    func canAfford(_ coupon: CouponModel) -> Bool {
        coins >= coupon.price
    }

    /// How `coupon`'s card looks: available, bought by the member, taken by someone else, and so on.
    func state(of coupon: CouponModel) -> CouponCard.PurchaseState {
        guard let latestCycleKey else { return .available }
        let myID = houseUser?.recordID
        if let myID, coupon.isHeld(by: myID, inCycle: latestCycleKey) {
            return .ownedByMe
        }
        guard coupon.isAvailable(latestCycleKey: latestCycleKey) else { return .taken }
        // One coupon per room per cycle (the purchase service checks it again on the server).
        if let myID, holdsAnotherCoupon(inRoomOf: coupon, userID: myID, cycleKey: latestCycleKey) {
            return .roomLimitReached
        }
        return .available
    }

    /// Whether `userID` holds, unused, a coupon other than `coupon` in the same room this cycle.
    private func holdsAnotherCoupon(inRoomOf coupon: CouponModel, userID: CKRecord.ID, cycleKey: String) -> Bool {
        guard let name = coupon.recordID?.recordName,
              let roomKey = roomKeyByCoupon[name]
        else { return false }
        return (couponsByRoom[roomKey] ?? []).contains { other in
            other.recordID?.recordName != name && other.isHeld(by: userID, inCycle: cycleKey)
        }
    }

    /// Stable across refreshes, unlike ``RoomModel/id``, which changes on every fetch.
    static func key(for room: RoomModel) -> String {
        room.recordID?.recordName ?? room.id.uuidString
    }

    // MARK: - Loading

    /// Loads the screen the first time.
    func setup() async {
        guard !isPreview else { hasLoaded = true; return }
        await load()
    }

    /// Reloads the screen (pull to refresh).
    func refresh() async {
        guard !isPreview else { return }
        await load()
    }

    /// Coalesces refresh requests and cancels the previous one.
    ///
    /// With `catchUp`, reloads once more after ``catchUpDelay``: a change made on another device
    /// (a division, a purchase) can be announced here before CloudKit's queries return it.
    func requestRefresh(debounce: Duration = .milliseconds(250), catchUp: Bool = false) {
        guard !isPreview else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled, let self else { return }
            await self.refresh()

            guard catchUp else { return }
            try? await Task.sleep(for: Self.catchUpDelay)
            guard !Task.isCancelled else { return }
            // The first reload refilled the shared cache; this one has to ask CloudKit again.
            HouseDataStore.shared.invalidate()
            await self.refresh()
        }
    }

    /// Wait before the second reload of ``requestRefresh(debounce:catchUp:)``.
    static let catchUpDelay: Duration = .seconds(3)

    /// Reads the house data and settles closed cycles, then fills the screen.
    private func load() async {
        var snapshot = await HouseDataStore.shared.load()
        // Nothing could be loaded yet (not an empty house): keep the screen as is until the next try.
        guard !Task.isCancelled, !snapshot.isPlaceholder else { return }

        // Rooms, coupons and rank come from the shared cache (`HouseDataStore`), so they show at
        // once; only the payouts and the balance are read here, after.
        apply(snapshot)

        guard let houseID = snapshot.houseID else {
            coins = snapshot.houseUser?.coins ?? 0
            return
        }

        // Automatic part of the payout: pending payouts for every cycle that ended.
        let settled = await CycleSettlementService().prepareClosedCycles(snapshot.cycles, members: snapshot.users, houseID: houseID)
        if settled > 0 {
            // A cycle was just settled: the points were reset, so the snapshot is outdated.
            snapshot = await HouseDataStore.shared.load(force: true)
        }

        var balance = snapshot.houseUser?.coins ?? 0
        if let userID = snapshot.houseUser?.recordID {
            balance = await CoinWalletModel.balance(for: userID, legacyCoins: snapshot.houseUser?.coins ?? 0)
        }
        guard !Task.isCancelled else { return }

        coins = balance
        if settled > 0 { apply(snapshot) }
    }

    /// Fills the screen from `snapshot`.
    private func apply(_ snapshot: HouseSnapshot) {
        defer { hasLoaded = true }

        houseID = snapshot.houseID
        latestCycleKey = HouseCycleModel.latest(snapshot.cycles)?.key
        let coupons = withRecentPurchases(snapshot.coupons)
        houseUser = snapshot.houseUser
        myOwnerRecordName = snapshot.houseUser?.ownerRecordName
        points = snapshot.houseUser?.points ?? 0
        // Loaded with the rest of the house data (`HouseDataStore`).
        rankHistory = snapshot.pastRanks(of: snapshot.houseUser)
        rooms = snapshot.rooms

        // coupon -> chore -> room. Only coupons on sale are offered.
        var roomKeyByChore: [String: String] = [:]
        var choreByName: [String: ChoreModel] = [:]
        let roomsByRecordName = Dictionary(
            snapshot.rooms.compactMap { room in room.recordID.map { ($0.recordName, room) } },
            uniquingKeysWith: { first, _ in first }
        )
        for chore in snapshot.chores {
            guard let choreName = chore.recordID?.recordName,
                  let roomName = chore.roomReference?.recordID.recordName,
                  let room = roomsByRecordName[roomName]
            else { continue }
            roomKeyByChore[choreName] = Self.key(for: room)
            choreByName[choreName] = chore
        }

        var grouped: [String: [CouponModel]] = [:]
        var roomByCoupon: [String: String] = [:]
        let pricing = CouponPricing.current
        for var coupon in coupons where coupon.isOnSale {
            guard let choreName = coupon.task?.recordID.recordName,
                  let roomKey = roomKeyByChore[choreName]
            else { continue }
            // The price follows the chore's current frequency and duration, until it's bought.
            if let chore = choreByName[choreName],
               latestCycleKey.map({ coupon.isAvailable(latestCycleKey: $0) }) ?? true {
                coupon.price = pricing.price(for: chore)
            }
            grouped[roomKey, default: []].append(coupon)
            if let name = coupon.recordID?.recordName { roomByCoupon[name] = roomKey }
        }
        roomKeyByCoupon = roomByCoupon
        couponsByRoom = grouped
        catalog = GamificationCatalog(
            coupons: grouped.values.flatMap { $0 },
            chores: snapshot.chores,
            rooms: snapshot.rooms,
            users: snapshot.users,
            myUserID: snapshot.houseUser?.recordID,
            latestCycleKey: latestCycleKey
        )

        if selectedRoom == nil {
            selectedRoomKey = rooms.first.map(Self.key(for:))
        }
    }

    // MARK: - Buying

    /// Buys `coupon` for the signed-in user, then reloads.
    ///
    /// - Returns: Whether the purchase went through. On failure ``alertMessage`` says why.
    @discardableResult
    func buy(_ coupon: CouponModel) async -> Bool {
        guard buyingCouponName == nil else { return false }
        guard let couponID = coupon.recordID,
              let buyerID = houseUser?.recordID,
              let houseID
        else {
            alertMessage = L10n.tr("Não foi possível concluir a compra. Tente de novo.")
            return false
        }

        buyingCouponName = coupon.recordID?.recordName ?? coupon.name
        defer { buyingCouponName = nil }

        var didBuy = false
        do {
            let receipt = try await CouponPurchaseService().purchase(
                couponID: couponID,
                buyerID: buyerID,
                houseID: houseID,
                cycleKey: latestCycleKey,
                legacyCoins: houseUser?.coins ?? 0
            )
            coins = receipt.newBalance
            rememberPurchase(of: coupon, by: buyerID, price: receipt.price)
            didBuy = true
        } catch let error as CouponPurchaseService.PurchaseError {
            alertMessage = error.userMessage
        } catch {
            alertMessage = UserFacingError.message(for: error, doing: .save)
        }

        HouseDataStore.shared.invalidate()
        await load()
        return didBuy
    }

    /// Keeps `coupon` as the purchase just saved it (see ``recentPurchases``).
    private func rememberPurchase(of coupon: CouponModel, by buyerID: CKRecord.ID, price: Int) {
        guard let name = coupon.recordID?.recordName else { return }
        var bought = coupon
        bought.lastUser = coupon.currentUser
        bought.currentUser = CKRecord.Reference(recordID: buyerID, action: .none)
        bought.purchasedCycleKey = latestCycleKey
        bought.consumedCycleKey = nil
        bought.price = price
        recentPurchases[name] = (bought, .now)
    }

    /// `coupons` with this device's recent purchases in place of the versions the query returned,
    /// until the query catches up (or ``recentPurchaseWindow`` passes).
    private func withRecentPurchases(_ coupons: [CouponModel], now: Date = .now) -> [CouponModel] {
        recentPurchases = recentPurchases.filter { now.timeIntervalSince($0.value.boughtAt) < Self.recentPurchaseWindow }
        guard !recentPurchases.isEmpty else { return coupons }

        return coupons.map { fetched in
            guard let name = fetched.recordID?.recordName,
                  let bought = recentPurchases[name]?.coupon
            else { return fetched }
            // The query already has the purchase: no need to keep it any longer.
            if fetched.currentUser?.recordID == bought.currentUser?.recordID,
               fetched.purchasedCycleKey == bought.purchasedCycleKey,
               fetched.consumedCycleKey == nil {
                recentPurchases[name] = nil
                return fetched
            }
            return bought
        }
    }
}
