//
//  AppDelegate.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 14/08/26.
//

import UIKit
import CloudKit

/// Handles app-level events: launch, CloudKit invites and silent pushes.
@MainActor
class AppDelegate: NSObject, UIApplicationDelegate {
    /// Uses ``SceneDelegate`` for every window, so invites opened from a link reach it.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default Configuration",
                                          sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
    
    /// Accepts a house invite opened while the app had no window yet.
    ///
    /// Posts `.willAcceptShare` before and `.didAcceptShare` or `.shareAcceptFailed` after.
    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Task {
            NotificationCenter.default.post(name: .willAcceptShare, object: nil)
            let success = await CloudKitManager.shared.acceptShare(metadata: cloudKitShareMetadata)
            if success {
                NotificationCenter.default.post(name: .didAcceptShare, object: nil)
            } else {
                NotificationCenter.default.post(name: .shareAcceptFailed, object: nil)
            }
        }
    }
    
    /// Receives CloudKit's silent pushes. When something changed in the house, posts
    /// `.cloudKitDidChange` (screens reload) and updates the Harvii device if the phone is at home.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable : Any]
    ) async -> UIBackgroundFetchResult {
        let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)
        
        if notification?.subscriptionID == "shared-changes" || notification?.subscriptionID == "private-changes" {
            NotificationCenter.default.post(name: .cloudKitDidChange, object: nil)
            
            // Something changed in the house: bring the device up to date if this phone is at home
            print("Silent push received")
            HardwareViewModel.notifyDataChanged()
            await HardwareViewModel.waitForPendingDelivery()
        }
        return .newData
    }
    
    /// Registers for pushes and makes sure the CloudKit zone and subscriptions exist.
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {

        application.registerForRemoteNotifications()
        
        // Sync fix: subscriptions used to be created only at house creation / join time, and a
        // failure there was swallowed by `try?`. Re-ensuring them on every launch (the call is
        // idempotent) repairs a device that would otherwise never receive `.cloudKitDidChange`.
        Task {
            // Warm the memoised zone check once, at launch, so the first record the user
            // creates doesn't pay for it. `createZoneIfNeeded()` is a no-op afterwards — it
            // used to issue a full `CKRecordZone` save before *every single* `create()`.
            await CloudKitManager.shared.createZoneIfNeeded()
            try? await CloudKitManager.shared.createSharedSubscription()
        }
        
        return true
    }
}
