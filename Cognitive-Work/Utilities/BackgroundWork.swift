//
//  BackgroundWork.swift
//  Cognitive-Work
//

import UIKit

/// Work the screen doesn't need to wait for (points, notifications), started right away and left
/// running while the user carries on.
enum BackgroundWork {

    /// Starts `work` without waiting for it. Asks iOS for extra time first, so it still finishes
    /// if the app goes to the background right after (home, app switcher, lock: about 30 seconds).
    /// Force-quitting the app still stops it, as it stopped work the screen was waiting for.
    ///
    /// - Parameters:
    ///   - name: Shown in the debugger for the background time.
    ///   - work: What to run.
    static func run(named name: String, _ work: @escaping @MainActor () async -> Void) {
        let time = BackgroundTime(name: name)
        Task { @MainActor in
            await work()
            time.end()
        }
    }
}

/// Extra time from iOS while some work finishes; ended by the work or when iOS runs out of time.
private final class BackgroundTime {
    private var id: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            // Out of time: ending it is required, or iOS terminates the app.
            MainActor.assumeIsolated { self?.end() }
        }
    }

    /// Gives the time back. Safe to call twice.
    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
