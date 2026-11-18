//
//  MyBadgesViewModel.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 18/11/26.
//

import Foundation

/// Feeds "Minhas Badges" on the profile: the signed-in member's room badge progress (pins
/// included) and the kinds of default room the house has.
///
/// Reads straight from what is already in memory: the house data (``HouseDataStore``) and the
/// progress ``BadgeManager`` keeps, which the house's first load already fetched. So the badges
/// are there as soon as the profile opens, and a pin made on the rewards tab shows here at once.
/// ``load()`` only asks CloudKit for the latest values.
@MainActor
@Observable
final class MyBadgesViewModel {

    /// The pin being saved, shown before the save finishes (see ``togglePin(_:)``).
    private var pending: RoomBadgeProgressModel?

    /// Fixed data for previews; `nil` in the app.
    @ObservationIgnored
    private let previewProgress: RoomBadgeProgressModel?
    @ObservationIgnored
    private let previewRooms: [DefaultRoomsOnboarding]

    /// Creates the view model the app uses.
    init() {
        self.previewProgress = nil
        self.previewRooms = []
    }

    /// Creates a view model with fixed data, for previews.
    init(previewProgress: RoomBadgeProgressModel, rooms: [DefaultRoomsOnboarding]) {
        self.previewProgress = previewProgress
        self.previewRooms = rooms
    }

    // MARK: - Data

    /// The signed-in member's record inside the house, once the house data is in memory.
    private var houseUser: UserModel? {
        HouseDataStore.shared.snapshot?.houseUser
    }

    /// The member's progress as last read on this device; `nil` before the first read.
    private var cachedProgress: RoomBadgeProgressModel? {
        if let previewProgress { return previewProgress }
        guard let houseUser else { return nil }
        return BadgeManager.shared.cachedProgress(of: houseUser)
    }

    /// The signed-in member's progress towards the room badges (``RoomBadge``).
    var progress: RoomBadgeProgressModel {
        pending ?? cachedProgress ?? RoomBadgeProgressModel(ownerRecordName: "")
    }

    /// The kinds of default room the house has: the badge ladders shown.
    var rooms: [DefaultRoomsOnboarding] {
        guard previewProgress == nil else { return previewRooms }
        return DefaultRoomsOnboarding.withBadges(in: HouseDataStore.shared.snapshot?.rooms ?? [])
    }

    /// Whether the progress was read at least once, so the views can tell "loading" from "empty".
    var hasLoaded: Bool { cachedProgress != nil }

    /// The badges the member pinned to the profile, in the order they were pinned.
    var pinnedBadges: [RoomBadge] { progress.pinnedBadges }

    // MARK: - Loading

    /// Asks CloudKit for the member's latest progress (the house data only if it's outdated).
    /// What is in memory keeps showing meanwhile.
    func load() async {
        guard previewProgress == nil else { return }
        let snapshot = await HouseDataStore.shared.load()
        guard !Task.isCancelled, !snapshot.isPlaceholder, let houseUser = snapshot.houseUser else { return }
        _ = await BadgeManager.shared.progress(of: houseUser)
    }

    // MARK: - Pinned badges

    /// Pins `badge` to the profile, or unpins it if it already is.
    ///
    /// Shows the change at once and saves it after; goes back to what it was if the save fails.
    func togglePin(_ badge: RoomBadge) async {
        guard let houseUser else { return }
        var optimistic = progress
        let pin = !optimistic.isPinned(badge)
        guard optimistic.setPinned(badge, pin) else { return }
        pending = optimistic

        // On success `BadgeManager` keeps the saved progress, which ``progress`` reads.
        await BadgeManager.shared.setPinned(badge, pin, for: houseUser)
        pending = nil
    }
}
