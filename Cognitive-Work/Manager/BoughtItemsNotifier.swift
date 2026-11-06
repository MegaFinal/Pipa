//
//  BoughtItemsNotifier.swift
//  Cognitive-Work
//

import Foundation
import UIKit

/// Gathers the items someone checks off during one shopping trip and sends each housemate a
/// single notification about the ones they added, instead of one notification per item.
///
/// The trip counts as over after ``quietPeriod`` without checking off another item, or as soon
/// as the app goes to the background. Unchecking an item before that takes it out of the
/// notification, so a mistake never reaches anyone.
@MainActor
final class BoughtItemsNotifier {

    static let shared = BoughtItemsNotifier()

    /// How long without checking off another item before the notifications go out.
    static let quietPeriod: Duration = .seconds(90)

    /// The items waiting to be announced to one housemate.
    private struct Batch {
        let owner: UserModel
        let buyerName: String
        var items: [(id: String, name: String)]
    }

    /// Items waiting to be announced, by the `ownerRecordName` of who added them.
    private var batches: [String: Batch] = [:]

    /// Sends the batches once the trip is over. Restarted by every new item.
    private var flushTask: Task<Void, Never>?

    /// Keeps the app running for a moment in the background, so the batches still go out.
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

    /// Adds `item`, just bought, to the notification for the housemate who added it.
    func add(_ item: ShopListItem, by buyerName: String, to owner: UserModel) {
        let key = owner.ownerRecordName
        var batch = batches[key] ?? Batch(owner: owner, buyerName: buyerName, items: [])
        batch.items.removeAll { $0.id == item.id }
        batch.items.append((item.id, item.name))
        batches[key] = batch
        scheduleFlush()
    }

    /// Takes `item` out of the waiting notifications (it was unchecked).
    func remove(_ item: ShopListItem) {
        for key in Array(batches.keys) {
            batches[key]?.items.removeAll { $0.id == item.id }
            if batches[key]?.items.isEmpty == true { batches[key] = nil }
        }
        if batches.isEmpty {
            flushTask?.cancel()
            flushTask = nil
        }
    }

    /// Waits for the trip to end, then sends everything.
    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: Self.quietPeriod)
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    /// Sends one notification per housemate with everything bought for them, now.
    func flush() async {
        flushTask?.cancel()
        flushTask = nil
        let ready = Array(batches.values)
        batches = [:]

        for batch in ready where !batch.items.isEmpty {
            await NotificationManager.shared.notifyItemsBought(
                batch.items.map(\.name),
                by: batch.buyerName,
                to: batch.owner
            )
        }
    }

    /// The app went to the background (phone locked, back in the pocket): the trip is over.
    private func flushInBackground() {
        guard !batches.isEmpty, backgroundTaskID == .invalid else { return }

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
