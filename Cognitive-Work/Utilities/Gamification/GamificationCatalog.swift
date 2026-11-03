//
//  GamificationCatalog.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 27/10/26.
//

import Foundation
import CloudKit

/// A coupon as the rewards tab shows it: the coupon plus the look it takes from its room.
struct CouponEntry: Identifiable {
    let coupon: CouponModel
    let roomName: String
    /// Identifies that room; the same value as ``GamificationViewModel/key(for:)``.
    let roomKey: String
    let color: RoomColor
    let symbol: String
    let state: CouponCard.PurchaseState
    var id: String { coupon.recordID?.recordName ?? coupon.name }
    var name: String { coupon.name }
    var tier: Tier { coupon.tier }
    var price: Int { coupon.price }
    var isMine: Bool { state == .ownedByMe }
    var isAvailable: Bool { state != .taken && state != .ownedByMe }
}

/// A rank and the members who are in it right now.
struct TierGroup: Identifiable {
    let tier: Tier
    let users: [UserModel]
    var id: Tier { tier }
}

/// What the rewards tab needs from the house data
struct GamificationCatalog {

    let entries: [CouponEntry]
    let tiers: [TierGroup]
    var availableCoupons: [CouponEntry] { entries.filter(\.isAvailable) }
    var myCoupons: [CouponEntry] { entries.filter(\.isMine) }
    func coupons(of tier: Tier) -> [CouponEntry] { entries.filter { $0.tier == tier } }
    func users(in tier: Tier) -> [UserModel] { tiers.first { $0.tier == tier }?.users ?? [] }

    static let empty = GamificationCatalog(entries: [], users: [])

    /// Builds the catalog.
    ///
    /// - Parameters:
    ///   - coupons: The house's coupons; only the ones on sale are listed.
    ///   - chores: The house's chores, to find each coupon's room through ``CouponModel/task``.
    ///   - rooms: The house's rooms, which give the coupon its color and symbol.
    ///   - users: The house members, one per person.
    ///   - myUserID: Record ID of the signed-in member in the house.
    ///   - latestCycleKey: Key of the latest cycle, or `nil` before the first division.
    init(
        coupons: [CouponModel],
        chores: [ChoreModel],
        rooms: [RoomModel],
        users: [UserModel],
        myUserID: CKRecord.ID?,
        latestCycleKey: String?
    ) {
        let roomsByName = Dictionary(
            rooms.compactMap { room in room.recordID.map { ($0.recordName, room) } },
            uniquingKeysWith: { first, _ in first }
        )
        var roomByChore: [String: RoomModel] = [:]
        for chore in chores {
            guard let choreName = chore.recordID?.recordName,
                  let roomName = chore.roomReference?.recordID.recordName,
                  let room = roomsByName[roomName]
            else { continue }
            roomByChore[choreName] = room
        }

        let entries: [CouponEntry] = coupons.compactMap { coupon in
            guard coupon.isOnSale,
                  let choreName = coupon.task?.recordID.recordName,
                  let room = roomByChore[choreName]
            else { return nil }
            return CouponEntry(
                coupon: coupon,
                roomName: room.name,
                roomKey: room.recordID?.recordName ?? room.id.uuidString,
                color: room.color,
                symbol: room.symbol,
                state: Self.state(of: coupon, myUserID: myUserID, latestCycleKey: latestCycleKey)
            )
        }

        self.init(entries: entries.sorted { $0.price < $1.price }, users: users)
    }

    /// Builds the catalog from entries already made (previews), grouping `users` by rank.
    init(entries: [CouponEntry], users: [UserModel]) {
        self.entries = entries
        self.tiers = Self.groups(of: users)
    }

    /// The coupon's state for the member, without the room-limit rule (that one needs the whole
    /// room; ``GamificationViewModel/state(of:)`` still applies it on top).
    private static func state(
        of coupon: CouponModel,
        myUserID: CKRecord.ID?,
        latestCycleKey: String?
    ) -> CouponCard.PurchaseState {
        guard let latestCycleKey else { return .available }
        if let myUserID, coupon.isHeld(by: myUserID, inCycle: latestCycleKey) { return .ownedByMe }
        return coupon.isAvailable(latestCycleKey: latestCycleKey) ? .available : .taken
    }

    /// Every rank of the ladder with the members whose points put them there.
    private static func groups(of users: [UserModel]) -> [TierGroup] {
        let byTier = Dictionary(grouping: users, by: \.tier)
        return Tier.allCases.map { tier in
            TierGroup(tier: tier, users: (byTier[tier] ?? []).sorted { $0.points > $1.points })
        }
    }
}
