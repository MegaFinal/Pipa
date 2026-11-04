//
//  UserProfileCache.swift
//  Cognitive-Work
//

import CloudKit
import UIKit

/// Decodes, caches and lazily downloads user profile off the main thread.
actor UserProfileCache {

    /// The process-wide cache.
    static let shared = UserProfileCache()

    /// Decoded, display-ready avatars keyed by the owning user's record ID.
    private var images: [CKRecord.ID: UIImage] = [:]

    /// Record IDs already known to have no avatar, so a miss is not retried on every row.
    private var knownEmpty: Set<CKRecord.ID> = []

    /// In-flight loads, so simultaneous requests for the same avatar coalesce into one.
    private var inFlight: [CKRecord.ID: Task<UIImage?, Never>] = [:]

    /// Use ``shared``.
    private init() {}

    /// `true` inside Xcode previews, where CloudKit can't be reached.
    private static let isRunningForPreviews =
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

    // MARK: - Reading

    /// The avatar for `user`, decoded off the main thread and cached for the rest of the session.
    /// - Parameter user: The user whose ``UserModel/profilePicture`` should be rendered.
    /// - Returns: A display-ready image, or `nil` when the user has no avatar or it could not
    ///   be read. A `nil` here is an expected outcome, not an error: `CKAsset` file URLs are
    ///   only valid while the record that carried them is alive.
    func image(for user: UserModel?) async -> UIImage? {
        guard let user else { return nil }

        // Xcode previews can't reach CloudKit (no iCloud entitlement) and crash if they try.
        // A preview user with only a record ID and no local picture gets the placeholder avatar.
        if Self.isRunningForPreviews, user.profilePicture?.fileURL == nil { return nil }

        guard let recordID = user.recordID else {
            guard let fileURL = user.profilePicture?.fileURL else { return nil }
            return await Self.decode(contentsOf: fileURL)
        }

        if let cached = images[recordID] { return cached }
        if knownEmpty.contains(recordID) { return nil }
        if let running = inFlight[recordID] { return await running.value }

        let localAssetURL = user.profilePicture?.fileURL
        let task = Task<UIImage?, Never> {
            if let localAssetURL, let image = await Self.decode(contentsOf: localAssetURL) {
                return image
            }
            return await Self.download(recordID: recordID)
        }
        inFlight[recordID] = task

        let image = await task.value
        inFlight[recordID] = nil

        if let image {
            images[recordID] = image
        } else {
            knownEmpty.insert(recordID)
        }
        return image
    }

    // MARK: - Invalidation

    /// Forgets the cached avatar for one user, e.g. right after they change their picture.
    func invalidate(_ recordID: CKRecord.ID) {
        images[recordID] = nil
        knownEmpty.remove(recordID)
        inFlight[recordID]?.cancel()
        inFlight[recordID] = nil
    }

    /// Forgets every cached avatar, e.g. after leaving or switching house.
    func removeAll() {
        images.removeAll()
        knownEmpty.removeAll()
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
    }

    // MARK: - Loading primitives

    /// Reads and decodes an asset file on a background executor.
    private static func decode(contentsOf fileURL: URL) async -> UIImage? {
        await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let data = try? Data(contentsOf: fileURL) else { return nil }
            return UIImage(data: data)?.preparingForDisplay()
        }.value
    }

    /// Fetches only the `profilePicture` field of one user record and decodes it.
    private static func download(recordID: CKRecord.ID) async -> UIImage? {
        let manager = CloudKitManager.shared
        let database = recordID.zoneID.ownerName == CKCurrentUserDefaultName
            ? manager.privateDB
            : manager.sharedDB

        guard
            let results = try? await database.records(
                for: [recordID],
                desiredKeys: ["profilePicture"]
            ),
            let record = try? results[recordID]?.get(),
            let fileURL = (record["profilePicture"] as? CKAsset)?.fileURL
        else {
            return nil
        }

        return await decode(contentsOf: fileURL)
    }
}
