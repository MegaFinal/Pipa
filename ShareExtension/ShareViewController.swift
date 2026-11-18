//
//  ShareViewController.swift
//  ShareExtension
//
//  Created by anshu Li on 18/11/26.
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// "Pipa" in the share sheet: shows the shared text (or photos, PDF) in ``ShareComposeView`` to
/// check it, stores it in ``SharedInbox`` and opens the app, where text becomes shopping and
/// chore cards and photos are read as a receipt or a recipe (Premium).
///
/// Nothing else runs here (no CloudKit, no AI): extensions get little memory, and the app
/// already has every rule for saving items and chores.
final class ShareViewController: UIViewController {

    /// Photos and PDFs already copied into the App Group (names in ``SharedInbox``).
    private var files: [String] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        Task { @MainActor in
            let content = await Self.sharedContent(from: extensionContext)
            files = content.files
            embed(ShareComposeView(
                initialText: content.text,
                files: content.files.compactMap(ShareComposeView.SharedFile.init(name:)),
                onCancel: { [weak self] in
                    // Copies made for nothing: remove them.
                    SharedInbox.deleteFiles(named: self?.files ?? [])
                    self?.finish()
                },
                onSend: { [weak self] text in self?.send(text) ?? .failed }
            ))
        }
    }

    private func embed(_ rootView: ShareComposeView) {
        let host = UIHostingController(rootView: rootView)
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
    }

    // MARK: - Sending

    /// Stores the text and asks the system to open Pipa on it.
    private func send(_ text: String) -> ShareComposeView.SendResult {
        guard SharedInbox.add(text, files: files) else { return .failed }
        let opened = openApp(SharedInbox.importURL)
        // A moment for the check mark, then the sheet closes (Pipa is opening behind it).
        DispatchQueue.main.asyncAfter(deadline: .now() + (opened ? 0.6 : 1.8)) { [weak self] in
            self?.finish()
        }
        return opened ? .openingApp : .savedForLater
    }

    /// Opens the containing app. Extensions have no official way to do it from the share sheet,
    /// so this walks the responder chain to the application object. If a future iOS stops
    /// allowing it, the text is already in the inbox and Pipa shows it the next time it opens.
    ///
    /// - Returns: Whether the request reached the application.
    private func openApp(_ url: URL) -> Bool {
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                // `open(_:options:completionHandler:)` is marked unavailable in extensions, so
                // it's called through the Objective-C runtime.
                let selector = NSSelectorFromString("openURL:options:completionHandler:")
                guard application.responds(to: selector) else { return false }
                typealias OpenURL = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
                let open = unsafeBitCast(application.method(for: selector), to: OpenURL.self)
                open(application, selector, url as NSURL, NSDictionary(), nil)
                return true
            }
            responder = current.next
        }
        return false
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    // MARK: - Reading the shared items

    /// The shared text (plain text attachments first, then the item's own text, where some
    /// apps put the selection) and the photos or PDFs, copied straight into the App Group.
    private static func sharedContent(from context: NSExtensionContext?) async -> (text: String, files: [String]) {
        let items = context?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        var texts: [String] = []
        var files: [String] = []

        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                    guard files.count < SharedInbox.maxFiles else { continue }
                    if let name = await copyFile(from: provider, type: .pdf) { files.append(name) }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    guard files.count < SharedInbox.maxFiles else { continue }
                    if let name = await copyFile(from: provider, type: .image) { files.append(name) }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = await loadText(from: provider), !text.isEmpty { texts.append(text) }
                }
            }
        }
        if texts.isEmpty && files.isEmpty {
            texts = items.compactMap { $0.attributedContentText?.string }.filter { !$0.isEmpty }
        }
        let text = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (text, files)
    }

    /// Copies a photo or PDF without loading it in memory (the temporary file only lives inside
    /// the callback). Some apps only give the bytes: those are written instead.
    private static func copyFile(from provider: NSItemProvider, type: UTType) async -> String? {
        let copied: String? = await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                continuation.resume(returning: url.flatMap(SharedInbox.copyFile(at:)))
            }
        }
        if let copied { return copied }

        return await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                let ext = type == .pdf ? "pdf" : "jpg"
                continuation.resume(returning: data.flatMap { SharedInbox.writeFile($0, ext: ext) })
            }
        }
    }

    private static func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                switch item {
                case let text as String:
                    continuation.resume(returning: text)
                case let data as Data:
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                case let url as URL:
                    continuation.resume(returning: (try? String(contentsOf: url, encoding: .utf8)))
                default:
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
