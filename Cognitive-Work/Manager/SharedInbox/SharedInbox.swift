//
//  SharedInbox.swift
//  Cognitive-Work
//
//  Created by anshu Li on 18/11/26.
//

import Foundation

/// Text, photos and PDFs shared to Pipa from another app (Share Extension), waiting for the app
/// to turn them into shopping items and chores (text), or to read them (photos and PDFs: a
/// receipt or a recipe, Premium).
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

    /// The most photos (or PDF pages) read from one share.
    static let maxFiles = 5

    /// One share: text, and the names of the photos or PDFs copied into ``filesDirectory``.
    struct Entry: Codable, Identifiable, Equatable {
        let id: UUID
        let text: String
        let createdAt: Date
        /// File names in ``SharedInbox/filesDirectory``; `nil` for a text-only share (and for
        /// entries saved before files were supported).
        var files: [String]?

        var hasFiles: Bool { !(files ?? []).isEmpty }

        /// Where each file is, in the order shared.
        var fileURLs: [URL] {
            (files ?? []).compactMap { SharedInbox.fileURL(named: $0) }
        }
    }

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    /// Whether `url` is the link the extension opens.
    static func isImportURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == urlScheme && url.host?.lowercased() == importHost
    }

    /// Stores `text` and the files already copied with ``copyFile(at:)`` for the app.
    ///
    /// - Returns: `false` when there's nothing to store or the App Group isn't set up (then the
    ///   defaults can't be opened).
    @discardableResult
    static func add(_ text: String, files: [String] = []) -> Bool {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxTextLength))
        guard !trimmed.isEmpty || !files.isEmpty, let defaults else { return false }
        var list = entries()
        list.append(Entry(id: UUID(), text: trimmed, createdAt: Date(), files: files.isEmpty ? nil : files))
        // Entries pushed out by the limit take their files with them.
        let kept = Array(list.suffix(maxEntries))
        list.filter { old in !kept.contains { $0.id == old.id } }.forEach(deleteFiles(of:))
        save(kept, in: defaults)
        return true
    }

    // MARK: - Files

    /// Shared photos and PDFs, in the App Group's container so the app can read them.
    static var filesDirectory: URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }
        let directory = container.appendingPathComponent("SharedInbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Copies a shared file into ``filesDirectory`` (without loading it in memory: extensions
    /// get little of it).
    ///
    /// - Returns: The copy's name, for ``add(_:files:)``; `nil` when it couldn't be copied.
    static func copyFile(at url: URL) -> String? {
        guard let directory = filesDirectory else { return nil }
        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension.lowercased()
        let name = "\(UUID().uuidString).\(ext)"
        do {
            try FileManager.default.copyItem(at: url, to: directory.appendingPathComponent(name))
            return name
        } catch {
            return nil
        }
    }

    /// Writes shared data that came without a file (some apps send an image's bytes).
    static func writeFile(_ data: Data, ext: String) -> String? {
        guard let directory = filesDirectory else { return nil }
        let name = "\(UUID().uuidString).\(ext)"
        do {
            try data.write(to: directory.appendingPathComponent(name))
            return name
        } catch {
            return nil
        }
    }

    static func fileURL(named name: String) -> URL? {
        filesDirectory?.appendingPathComponent(name)
    }

    /// Deletes copied files that were never sent (the share sheet was cancelled).
    static func deleteFiles(named names: [String]) {
        for name in names {
            if let url = fileURL(named: name) { try? FileManager.default.removeItem(at: url) }
        }
    }

    static func deleteFiles(of entry: Entry) {
        deleteFiles(named: entry.files ?? [])
    }

    /// Entries still waiting, oldest first. Expired ones are dropped with their files.
    static func entries() -> [Entry] {
        guard let defaults,
              let data = defaults.data(forKey: storageKey),
              let list = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        let oldest = Date().addingTimeInterval(-maxAge)
        let expired = list.filter { $0.createdAt < oldest }
        guard !expired.isEmpty else { return list }
        expired.forEach(deleteFiles(of:))
        let kept = list.filter { $0.createdAt >= oldest }
        save(kept, in: defaults)
        return kept
    }

    /// The oldest entry waiting, if any.
    static var next: Entry? {
        entries().first
    }

    /// Takes an entry out of the waiting list once the app shows it. Its files stay until
    /// ``deleteFiles(of:)``: the import page still reads them.
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
