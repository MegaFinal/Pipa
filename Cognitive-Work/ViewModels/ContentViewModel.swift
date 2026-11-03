//
//  ContentViewModel.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 17/08/26.
//

import Foundation
import CloudKit
import SwiftUI

/// Runs the main tabs' app-level work: opening the app, checking the house still exists,
/// switching houses from an invite and deciding when the retrospective shows.
@MainActor
@Observable
class ContentViewModel {
    /// An error to show in an alert, or `nil` when there is none.
    var errorMessage: String? = nil
    
    /// Whether the "already in a house" warning is being presented.
    var showInviteAcceptAlert: Bool = false
    
    /// Metadata of the invitation that triggered the warning.
    var shareMetadata: CKShare.Metadata? = nil
    /// `true` while the app leaves the current house and joins the new one.
    var isSwitchingHouse = false
    
    /// Whether the user finished the onboarding. Set to `false` to send them back to it.
    @ObservationIgnored
    @AppStorage("didOnboard") private var didOnboard: Bool = true
    
    // MARK: - House verification
    
    /// `true` when the user's house was deleted, so the app can send them back to the onboarding.
    var userHasNoHouse: Bool = false
    
    /// `true` while the app opens and ``bootstrap()`` loads everything the tabs show. The root
    /// view keeps ``LoadingScreen`` up for as long as this is set, and only builds the tabs
    /// afterwards, so each of them finds its data ready.
    var isLoading = true
    
    /// The shared data every tab reads.
    private let store = HouseDataStore.shared
    
    /// Opens the app: settles which house the user belongs to, then loads all of its data in
    /// one go.
    func bootstrap() async {
        isLoading = true
        defer { isLoading = false }
        
        store.reset()
        
        await leaveOrphanedHouses()
        guard !Task.isCancelled, didOnboard else { return }
        
        await fetchHouse()
        guard !Task.isCancelled, !userHasNoHouse else { return }
        
        await store.load(force: true)
        
        Task { await syncFreeTime() }
    }
    
    /// Fetches the user house and verify if its exist
    func fetchHouse() async {
        print("fetchHouse")
        
        do {
            let house = try await CloudKitManager.shared.currentHouse(forceRefresh: true)
            guard !Task.isCancelled else { return }
            userHasNoHouse = (house == nil)
            // Reads the house's Premium status and, if this device pays, renews it in the record.
            await PremiumManager.shared.refresh(house: house)
        } catch let error as CKError where [.zoneNotFound, .userDeletedZone, .unknownItem].contains(error.code) {
            userHasNoHouse = true   // the house is really gone
        } catch {
            print("currentHouse falhou:", type(of: error), error)
            if let ck = error as? CKError {
                print("   CKError code:", ck.code.rawValue, ck.code)
                print("   partial errors:", ck.partialErrorsByItemID ?? [:])
            }
            guard !Task.isCancelled else { return }
            errorMessage = L10n.tr("Não foi possível carregar a casa. Verifique sua conexão.")
            return
        }
    }
    
    /// Sends a user whose house was deleted back to the start of the onboarding.
    func accountWithoutHouseReturnToOnboarding() {
        Self.resetOnboardingProgress()
        self.didOnboard = false
    }
    
    /// The onboarding that opens next must start at the welcome screen, not resume a stale step.
    static func resetOnboardingProgress() {
        OnboardingStateMachine.clearPersistedProgress()
        OnboardingRollbackJournal.clear()
    }
    
    /// Leaves the current house, joins the one in `metadata` and reloads everything.
    func switchHouse(to metadata: CKShare.Metadata) async {
        await CloudKitManager.shared.switchHouse(to: metadata)
        self.errorMessage = CloudKitManager.shared.errorMessage
        
        await bootstrap()
    }
    
    // MARK: - Retrospective

    /// Whether the retrospective is on screen.
    var showRetro = false

    /// Day the retrospective was last offered (kept so it shows at most once a day).
    @ObservationIgnored
    private var lastRetroPresentedDay: Date? {
        get { UserDefaults.standard.object(forKey: "retro.lastPresentedDay") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "retro.lastPresentedDay") }
    }

    /// Shows the retrospective when the period of the last division is over.
    /// Best effort: if the schedule can't be read there is nothing to compare, so nothing is shown.
    func checkRetro() async {
        guard !userHasNoHouse, !showRetro else { return }

        let assignments = await CloudKitManager.shared.fetchAll(RecurrentAssignmentModel.self)
        guard !Task.isCancelled, !showRetro else { return }

        guard RetroTriggerPolicy.shouldPresent(
            lastScheduledDay: assignments.map(\.day).max(),
            lastPresentedDay: lastRetroPresentedDay,
            now: .now
        ) else { return }

        lastRetroPresentedDay = .now
        withAnimation(.easeInOut) { showRetro = true }
    }

    // MARK: - Free time

    /// Makes the free time on the private profile and on the house profile agree, and retries a
    /// write to the house profile that failed earlier (see `FreeTimeSyncService`). Best effort:
    /// a failure is simply tried again the next time the app opens.
    func syncFreeTime() async {
        guard !userHasNoHouse else { return }
        await FreeTimeSyncService.live().reconcile()
    }

    // MARK: - Orphaned houses

    /// Leaves any house this iCloud account is still attached to without a member record
    func leaveOrphanedHouses() async {
        let removed = await CloudKitManager.shared.pruneOrphanedSharedMemberships()
        guard removed > 0 else { return }
        do {
            if try await CloudKitManager.shared.currentHouse(forceRefresh: true) == nil {
                Self.resetOnboardingProgress()
                didOnboard = false
            } else {
                NotificationCenter.default.post(name: .cloudKitDidChange, object: nil)
            }
        } catch {
            // Could not confirm whether a house is left (network, etc.).
            // Do nothing now; the next fetchHouse() will settle it.
        }
    }
}
