//
//  BoughtItemsNotifier.swift
//  Cognitive-Work
//

import Foundation
import UIKit

/// Gathers the items someone checks off during one shopping trip, so the housemates get one
/// notification for the whole trip instead of one per item. Who gets what is decided when the
/// trip is over, by the shopping list (``ShopListViewModel``): the people the items are for,
/// with their part, and who added an item without sharing it.
///
/// The trip counts as over after ``quietPeriod`` without checking off another item, or as soon
/// as the app goes to the background. Unchecking an item before that takes it out of the
/// notification, so a mistake never reaches anyone.
@MainActor
final class BoughtItemsNotifier {

    static let shared = BoughtItemsNotifier()

    /// How long without checking off another item before the notifications go out.
    static let quietPeriod: Duration = .seconds(90)

    /// Sends one trip's notifications: the items bought, and who bought them.
    typealias Sender = @MainActor ([ShopListItem], UserModel) async -> Void

    /// The items checked off in this trip, in order.
    private var items: [ShopListItem] = []
    /// Who checked them off.
    private var buyer: UserModel?
    /// What sends the trip's notifications.
    private var sender: Sender?

    /// Sends the trip once it is over. Restarted by every new item.
    private var flushTask: Task<Void, Never>?

    /// Keeps the app running for a moment in the background, so the trip still goes out.
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    private init() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushInBackground() }
        }
    }

    /// Adds `item`, just bought by `buyer`, to this trip.
    /// - Parameter send: Sends the trip's notifications once it is over.
    func add(_ item: ShopListItem, by buyer: UserModel, send: @escaping Sender) {
        items.removeAll { $0.id == item.id }
        items.append(item)
        self.buyer = buyer
        sender = send
        #if DEBUG
        print("[BoughtItems] \(item.name) waits for the trip to end (\(items.count) items)")
        #endif
        scheduleFlush()
    }

    /// Takes `item` out of this trip (it was unchecked).
    func remove(_ item: ShopListItem) {
        items.removeAll { $0.id == item.id }
        if items.isEmpty {
            flushTask?.cancel()
            flushTask = nil
        }
    }

    /// Waits for the trip to end, then sends everything.
    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: Self.quietPeriod)
            guard !Task.isCancelled, let self else { return }
            // Let go of this task first: `flush()` cancels `flushTask`, and cancelling the task
            // that is running it made CloudKit give up the save, so nothing was ever sent.
            flushTask = nil
            await flush()
        }
    }

    /// Sends the trip's notifications now. Stops the wait for the trip to end, if any (never
    /// the task running this: see ``scheduleFlush()``).
    func flush() async {
        flushTask?.cancel()
        flushTask = nil
        let trip = items.filter(\.isBought)
        items = []
        guard !trip.isEmpty, let buyer, let sender else { return }
        #if DEBUG
        print("[BoughtItems] sending the trip: \(trip.map(\.name))")
        #endif
        await sender(trip, buyer)
    }

    /// The app went to the background (phone locked, back in the pocket): the trip is over.
    private func flushInBackground() {
        guard !items.isEmpty, backgroundTaskID == .invalid else { return }

        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            MainActor.assumeIsolated { self?.endBackgroundTask() }
        }
        Task {
            await flush()
            endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
}
