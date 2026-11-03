//
//  OnboardingStateMachine.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 31/08/26.
//

import SwiftUI
import CloudKit

/// A state machine responsible for managing the user's progression through the onboarding process.
///
/// It persists the current state (both the active flow and the step index) across app launches
/// to ensure users can resume exactly where they left off if the app is closed.
@Observable
class OnboardingStateMachine {

    // MARK: - Persistence

    /// UserDefaults keys used to persist onboarding progress across app launches.
    private enum StorageKey {
        /// Key of the saved ``index``.
        static let index = "onboarding.index"
        /// Key of the saved ``flow``.
        static let flow = "onboarding.flow"
        /// Key of the saved ``skippedToCreateOrEnter``.
        static let skippedToCreateOrEnter = "onboarding.skippedToCreateOrEnter"
    }

    // MARK: - Properties

    /// The user profile being created or utilized during the onboarding process.
    var user: UserModel? = nil
    
    /// The house record being created or joined during the onboarding process.
    var house: HouseModel? = nil

    /// The current position index within the active ``steps`` array.
    ///
    /// > Note: Whenever this property is updated, its new value is automatically
    /// > persisted to `UserDefaults` to prevent progress loss.
    private(set) var index: Int {
        didSet { UserDefaults.standard.set(index, forKey: StorageKey.index) }
    }

    /// The specific branching path the user is currently following.
    ///
    /// Since the meaning of a given index changes depending on the active flow, this
    /// is persisted alongside the ``index``.
    var flow: NavigationFlowsOnboarding {
        didSet { UserDefaults.standard.set(flow.rawValue, forKey: StorageKey.flow) }
    }

    /// True when the user reached "create or enter a house" straight from the welcome screen
    /// (profile and free time already known, e.g. after leaving a house). "Voltar" from that
    /// step then returns to the welcome screen instead of the steps that were skipped.
    var skippedToCreateOrEnter: Bool {
        didSet { UserDefaults.standard.set(skippedToCreateOrEnter, forKey: StorageKey.skippedToCreateOrEnter) }
    }

    // MARK: - Initialization

    /// Initializes the state machine, restoring the previous session's index and flow from `UserDefaults`.
    init() {
        self.index = UserDefaults.standard.integer(forKey: StorageKey.index)

        let savedFlow = UserDefaults.standard.string(forKey: StorageKey.flow)
        self.flow = savedFlow.flatMap(NavigationFlowsOnboarding.init(rawValue:)) ?? .notDefined
        self.skippedToCreateOrEnter = UserDefaults.standard.bool(forKey: StorageKey.skippedToCreateOrEnter)
    }

    // MARK: - Computed Properties

    /// Evaluates if the current user is the administrator/creator of the linked house.
    ///
    /// - Returns: `true` if the user owns the house zone, `false` otherwise, or `nil` if no house exists yet.
    var isOwner: Bool? {
        if let recordID = house?.recordID {
            return CloudKitManager.shared.isOwner(HouseModel.self, recordID: recordID)
        }
        return nil
    }
    
    /// The dynamic array of sequential steps dictated by the currently active ``flow``.
    var steps: [OnboardingNavigationSteps] {
        Self.steps(for: flow)
    }
    
    /// The sequential steps of a given flow.
    static func steps(for flow: NavigationFlowsOnboarding) -> [OnboardingNavigationSteps] {
        switch flow {
        case .houseCreator:
            return [
                .welcome,
                .createProfile,
                .chooseFreeTime,
                .createOrEnterHome,
                .waitGuestsFreeTime,
                .setUpScheduleChores,
                .chooseRooms,
                .chooseChores,
                .scheduleChores
            ]
        case .invitedWithProfile:
            return [
                .welcome,
                .createProfile,
                .chooseFreeTime,
                .createOrEnterHome,
                .waitAcceptLink,
                .waitAdminScheduling,
                .scheduleChores
            ]
        case .invitedWithoutProfile:
            return [
                .welcome,
                .createProfile,
                .chooseFreeTime,
                .inviteAndConfirmJoin,
                .waitAdminScheduling,
                .scheduleChores
            ]
        case .notDefined:
            return [.welcome, .createProfile, .chooseFreeTime, .createOrEnterHome]
        }
    }
    
    /// Returns the specific navigation step corresponding to the current ``index``.
    ///
    /// - Returns: The active `OnboardingNavigationSteps`, or `nil` if the index is out of bounds.
    var current: OnboardingNavigationSteps? {
        steps.indices.contains(index) ? steps[index] : nil
    }
    
    /// The step a "voltar" from ``current`` leads to, or `nil` on the first step.
    var previousStep: OnboardingNavigationSteps? {
        if skippedToCreateOrEnter, current == .createOrEnterHome { return .welcome }
        let previous = index - 1
        return steps.indices.contains(previous) ? steps[previous] : nil
    }
    
    // MARK: - Navigation & Mutators

    /// Assigns a newly created or fetched user to the state machine's memory.
    ///
    /// - Parameter user: The `UserModel` instance to store.
    func setUser(user: UserModel) {
        self.user = user
    }
    
    /// Advances the state machine to the next step, safely bounded by the array limits.
    func next() {
        index = min(index + 1, steps.count - 1)
    }
    
    /// Retreats the state machine to the previous step, safely bounded to zero.
    func back() {
        index = max(index - 1, 0)
    }

    /// Goes back to `step`, optionally switching to another flow at the same time.
    ///
    /// The index is set *before* the flow so ``current`` never points past the end of the new
    /// (possibly shorter) ``steps`` array in between.
    ///
    /// - Parameters:
    ///   - step: The step to show.
    ///   - newFlow: The flow to switch to, or `nil` to keep the current one.
    func back(to step: OnboardingNavigationSteps, switchingTo newFlow: NavigationFlowsOnboarding? = nil) {
        let targetSteps = newFlow.map(Self.steps(for:)) ?? steps
        guard let targetIndex = targetSteps.firstIndex(of: step) else {
            back()
            return
        }
        index = targetIndex
        if targetIndex == 0 { skippedToCreateOrEnter = false }
        if let newFlow { flow = newFlow }
    }

    /// Clears the persisted progress completely.
    ///
    /// > Important: Call this once onboarding finishes (or is skipped) so a future run
    /// > doesn't attempt to resume in the middle of a flow that is no longer applicable.
    func resetProgress() {
        index = 0
        flow = .notDefined
        skippedToCreateOrEnter = false
    }

    /// Forgets the persisted progress without needing an instance.
    ///
    /// Used when the user leaves or deletes their house, so the onboarding that opens next starts
    /// from the welcome screen instead of resuming a stale step.
    static func clearPersistedProgress() {
        UserDefaults.standard.removeObject(forKey: StorageKey.index)
        UserDefaults.standard.removeObject(forKey: StorageKey.flow)
        UserDefaults.standard.removeObject(forKey: StorageKey.skippedToCreateOrEnter)
    }

    /// Moves straight to the step at `index` of the current flow, kept inside the valid range.
    func jumpToStep(index: Int) {
        self.index = min(max(index, 0), steps.count - 1)
    }
}
