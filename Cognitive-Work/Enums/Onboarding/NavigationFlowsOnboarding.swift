//
//  StatesForOnboarding.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 31/08/26.
//

/// Which branch of onboarding the user is going through.
///
/// `String` raw values let ``OnboardingStateMachine`` persist the current flow
/// across app launches.
enum NavigationFlowsOnboarding: String {
    /// The user is creating a new house (they will be its admin).
    case houseCreator
    /// The user was invited to a house and already has a profile.
    case invitedWithProfile
    /// The user was invited to a house and still needs to create a profile.
    case invitedWithoutProfile
    /// The flow is not known yet (the user hasn't chosen).
    case notDefined
}
