//
//  SharedInbox.swift
//  Cognitive-Work
//
//  Created by anshu Li on 18/11/26.
//

import Foundation

/// Text shared to Pipa from another app (Share Extension), waiting for the app to turn it into
/// shopping items and chores.
///
/// The extension only stores the text here, in the App Group's defaults, and asks the system to
/// open Pipa. The app reads it (``ContentView``) and shows ``SharedImportView``, where the text
/// becomes cards. Keeping the extension this small avoids running CloudKit, Premium and the
/// on-device model inside it (extensions get little memory).
///
/// Compiled in both targets: the app and the Share Extension (see the membership exception in
/// the project for `Manager/SharedInbox/SharedInbox.swift`).
nonisolated enum SharedInbox {

    /// The App Group both targets belong to (Signing & Capabilities → App Groups).
    static let appGroupID = "group.JonasMelo.Cognitive-Work"

    /// `pipa://import`: opens the app on the import page.
    static let urlScheme = "pipa"
    static let importHost = "import"
    static var importURL: URL {
        var components = URLComponents()
        components.scheme = urlScheme
        components.host = importHost
        return components.url!
    }

    /// The longest text kept (a long WhatsApp message is still far below this).
    static let maxTextLength = 4_000
    /// Older entries are dropped: something shared a week ago isn't wanted anymore.
    private static let maxAge: TimeInterval = 7 * 24 * 60 * 60
    private static let maxEntries = 10
    private static let storageKey = "sharedInbox.entries"

    /// One shared text.
    struct Entry: Codable, Identifiable, Equatable {
        let id: UUID
        let text: String
        let createdAt: Date
    }

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    /// Whether `url` is the link the extension opens.
    static func isImportURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == urlScheme && url.host?.lowercased() == importHost
    }

    /// Stores `text` for the app.
    ///
    /// - Returns: `false` when the text is empty or the App Group isn't set up (then the
    ///   defaults can't be opened).
    @discardableResult
    static func add(_ text: String) -> Bool {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxTextLength))
        guard !trimmed.isEmpty, let defaults else { return false }
        var list = entries()
        list.append(Entry(id: UUID(), text: trimmed, createdAt: Date()))
        save(Array(list.suffix(maxEntries)), in: defaults)
        return true
    }

    /// Entries still waiting, oldest first.
    static func entries() -> [Entry] {
        guard let defaults,
              let data = defaults.data(forKey: storageKey),
              let list = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        let oldest = Date().addingTimeInterval(-maxAge)
        return list.filter { $0.createdAt >= oldest }
    }

    /// The oldest entry waiting, if any.
    static var next: Entry? {
        entries().first
    }

    /// Removes an entry once the app showed it (added or discarded).
    static func remove(_ id: UUID) {
        guard let defaults else { return }
        save(entries().filter { $0.id != id }, in: defaults)
    }

    private static func save(_ list: [Entry], in defaults: UserDefaults) {
        if list.isEmpty {
            defaults.removeObject(forKey: storageKey)
        } else if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
