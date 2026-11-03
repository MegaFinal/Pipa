//
//  Cognitive_WorkApp.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 07/08/26.
//

import SwiftUI
import SwiftData

/// The app's entry point.
///
/// Shows the onboarding until the user finishes it, then the main tabs (``ContentView``).
@main
struct Cognitive_WorkApp: App {
    /// Connects ``AppDelegate`` for launch, push and invite events.
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    /// Whether the user finished the onboarding.
    @AppStorage("didOnboard") private var didOnboard: Bool = false
    
    /// Whether the app is active or in the background.
    @Environment(\.scenePhase) private var scenePhase
    /// Keeps the Harvii device in sync while the app runs.
    @State private var hardwareViewModel = HardwareViewModel()
    
    /// Language picked in "Configurações Gerais" (or the device language by default).
    @State private var languageManager = LanguageManager.shared
    
    var body: some Scene {
        WindowGroup {
            // MARK: - Root screen: onboarding or main tabs
            Group {
                if didOnboard {
                    ContentView()
                } else {
                    Onboarding(didOnboard: $didOnboard)
                }
            }
            // MARK: - App-wide settings: terms gate, text size and language
            .requiresTermsAcceptance()
            .dynamicTypeSize(.large)
            .environment(\.locale, languageManager.locale)
            // MARK: - Premium: listen to the App Store from launch (renewals, refunds, purchases)
            .task {
                await PremiumManager.shared.start()
            }
        }
        // MARK: - Harvii sync: send now when active, schedule a refresh when in background
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task {
                    await NotificationManager.shared.processIncoming()
                    await NotificationManager.shared.refreshReminders()
                    await NotificationManager.shared.refreshUnseenNotifications()
                    await StoreManager.shared.refreshEntitlements() 
                    await HardwareViewModel.deliverNow()
                }
            case .background:
                HardwareBackgroundSync.scheduleAppRefresh()
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(HardwareBackgroundSync.refreshTaskID)) {
            await HardwareBackgroundSync.scheduleAppRefresh()   // schedule the next one
            await HardwareViewModel.deliverNow()
        }
    }
}
