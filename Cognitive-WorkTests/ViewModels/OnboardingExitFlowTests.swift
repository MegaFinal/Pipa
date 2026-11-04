//
//  OnboardingExitFlowTests.swift
//  Cognitive-Work
//

import Testing
import Foundation
@testable import Cognitive_Work

/// After leaving (or losing) a house the user sees the welcome screen and then "create or enter a
/// house" - never the free-time screen again.
///
/// Serialized because the state machine persists its progress in `UserDefaults.standard`.
@MainActor
@Suite(.serialized)
struct OnboardingExitFlowTests {

    init() {
        OnboardingStateMachine.clearPersistedProgress()
    }

    @Test func leavingAHouseGoesFromWelcomeToCreateOrEnterWithoutAskingForFreeTime() throws {
        // Progress left behind by the onboarding the user went through before.
        UserDefaults.standard.set(8, forKey: "onboarding.index")
        UserDefaults.standard.set(NavigationFlowsOnboarding.houseCreator.rawValue, forKey: "onboarding.flow")

        // Leaving or deleting the house clears it...
        OnboardingStateMachine.clearPersistedProgress()
        let machine = OnboardingStateMachine()
        #expect(machine.flow == .notDefined)
        #expect(machine.current == .welcome)

        // ...the welcome screen leads to create/enter because profile and free time are known.
        var visited: [OnboardingNavigationSteps] = []
        visited.append(try #require(machine.current))

        let target = OnboardingRouting.stepAfterWelcome(hasProfile: true, hasFreeTime: true)
        let index = try #require(machine.steps.firstIndex(of: target))
        machine.jumpToStep(index: index)
        visited.append(try #require(machine.current))

        #expect(visited == [.welcome, .createOrEnterHome])
        #expect(visited.contains(.chooseFreeTime) == false)

        OnboardingStateMachine.clearPersistedProgress()
    }

    @Test func theWelcomeScreenLeadsWhereTheAccountStateSays() {
        // Brand new user.
        #expect(OnboardingRouting.stepAfterWelcome(hasProfile: false, hasFreeTime: false) == .createProfile)
        #expect(OnboardingRouting.stepAfterWelcome(hasProfile: false, hasFreeTime: true) == .createProfile)
        // Has a profile but never saved free time (or it could not be read): still asked once,
        // so a house is never created without it.
        #expect(OnboardingRouting.stepAfterWelcome(hasProfile: true, hasFreeTime: false) == .chooseFreeTime)
        // Returning user.
        #expect(OnboardingRouting.stepAfterWelcome(hasProfile: true, hasFreeTime: true) == .createOrEnterHome)
    }

    @Test func everyFlowStillReachesCreateOrEnterAtTheSameIndex() throws {
        // `advanceFromWelcome()` jumps by step, and choosing "Criar"/"Entrar" switches flow while
        // keeping the index, so the position of this step must not depend on the flow.
        let index = try #require(OnboardingStateMachine.steps(for: .notDefined).firstIndex(of: .createOrEnterHome))
        for flow in [NavigationFlowsOnboarding.houseCreator, .invitedWithProfile] {
            #expect(OnboardingStateMachine.steps(for: flow).firstIndex(of: .createOrEnterHome) == index)
        }
    }

    @Test func backFromCreateOrEnterReturnsToWelcomeForAReturningUser() throws {
        let machine = OnboardingStateMachine()
        machine.skippedToCreateOrEnter = true
        machine.jumpToStep(index: try #require(machine.steps.firstIndex(of: .createOrEnterHome)))
        #expect(machine.previousStep == .welcome)

        machine.back(to: .welcome)
        #expect(machine.current == .welcome)
        #expect(machine.skippedToCreateOrEnter == false)

        OnboardingStateMachine.clearPersistedProgress()
    }

    @Test func backFromCreateOrEnterStillGoesToFreeTimeForANewUser() throws {
        let machine = OnboardingStateMachine()
        machine.jumpToStep(index: try #require(machine.steps.firstIndex(of: .createOrEnterHome)))
        #expect(machine.previousStep == .chooseFreeTime)

        OnboardingStateMachine.clearPersistedProgress()
    }

    @Test func afterCreateOrEnterTheFlowContinuesAsBefore() throws {
        let creator = OnboardingStateMachine()
        creator.jumpToStep(index: try #require(creator.steps.firstIndex(of: .createOrEnterHome)))
        creator.flow = .houseCreator
        creator.next()
        #expect(creator.current == .waitGuestsFreeTime)

        OnboardingStateMachine.clearPersistedProgress()

        let guest = OnboardingStateMachine()
        guest.jumpToStep(index: try #require(guest.steps.firstIndex(of: .createOrEnterHome)))
        guest.flow = .invitedWithProfile
        guest.next()
        #expect(guest.current == .waitAcceptLink)

        OnboardingStateMachine.clearPersistedProgress()
    }
}
