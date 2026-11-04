//
//  OnboardingStep.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 31/08/26.
//


/// The screens of the onboarding flow, in the order a user usually goes through them.
///
/// Admins (who create the house) and guests (who join with a link) take different paths;
/// some steps only exist for one of them.
enum OnboardingNavigationSteps {
    /// First screen, introducing the app.
    case welcome
    /// The user creates their profile (name and photo).
    case createProfile
    /// The user chooses between creating a new house or joining one.
    case createOrEnterHome
    /// A guest waits for the share link to be accepted.
    case waitAcceptLink
    /// The admin picks the rooms of the house.
    case chooseRooms
    /// The admin invites the other members and sees who joined.
    case inviteAndConfirmJoin
    /// Introduction to setting up the chore schedule.
    case setUpScheduleChores
    /// The admin picks the house's chores.
    case chooseChores
    /// The user tells when they have free time during the week.
    case chooseFreeTime
    /// The first division of chores is generated.
    case scheduleChores
    /// A guest waits for the admin to generate the division.
    case waitAdminScheduling
    /// The admin waits for the guests to fill in their free time.
    case waitGuestsFreeTime
}
