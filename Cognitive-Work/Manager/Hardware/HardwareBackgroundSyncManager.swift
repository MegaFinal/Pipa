//
//  HardwareBackgroundSync.swift
//  Cognitive-Work
//
//  Created by Isabela Hissa Pinto on 28/09/26.
//

import BackgroundTasks

/// Wakes the app in the background every so often, so pending changes reach the device.
///
/// Silent pushes are handled by the subscriptions `CloudKitManager.createSharedSubscription()`
/// already creates; this only covers the periodic background refresh.
enum HardwareBackgroundSync {

    /// Must match BGTaskSchedulerPermittedIdentifiers in Info.plist.
    static let refreshTaskID = "hardwareRefresh"

    /// Asks iOS to wake the app in about 15 minutes (iOS decides the actual time).
    static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Could not schedule app refresh: \(error)")
        }
    }
}
