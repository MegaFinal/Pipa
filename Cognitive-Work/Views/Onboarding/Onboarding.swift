//
//  Onboarding.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 31/08/26.
//

import SwiftUI

/// Router for the whole onboarding flow.
///
/// Renders whichever step ``OnboardingStateMachine`` currently points at, and
/// hands control over to ``ContentView`` once the flow is finished or skipped.
struct Onboarding: View {

    // MARK: - Properties

    /// Flips to `true` when onboarding ends, releasing the main app.
    @Binding var didOnboard: Bool

    /// State shared by every step of the flow.
    @State var viewModel = OnboardingViewModel()

    // MARK: - Body

    var body: some View {
        ZStack {
            Group {
                // MARK: - No connection: retry instead of leaving the user stuck on a step
                if let problem = viewModel.accountCheckError, !viewModel.isRetryingAccountCheck {
                    ConnectionErrorView(message: problem) {
                        Task { await viewModel.retryAccountCheck() }
                    }
                    .transition(.opacity)
                // MARK: - Loading while the account check runs ("Continuar" tapped or retrying)
                } else if viewModel.isWaitingAccountCheck || viewModel.isRetryingAccountCheck {
                    LoadingScreen(
                        accessibilityTitle: L10n.tr("Conectando ao iCloud..."),
                        message: "Conectando ao iCloud..."
                    )
                    .transition(.opacity)
                // MARK: - Loading animation while restoring, otherwise the current step
                } else if viewModel.isRestoringSession && viewModel.stateMachine.index > 0 {
                    LoadingScreen(
                        animation: .burst,
                        accessibilityTitle: L10n.tr("Retomando de onde você parou..."),
                        message: "Retomando de onde você parou..."
                    )
                } else {
                    NavigationStack {
                        stepView(for: viewModel.stateMachine)
                    }
                }
            }
                // MARK: - End of onboarding and VoiceOver
                .onChange(of: viewModel.isOnboardingSkipped) {
                    didOnboard = true
                }
                // "Continuar" tapped while the account check was running: move on once it ends.
                .onChange(of: viewModel.isCheckingAccount) {
                    viewModel.finishWaitingAccountCheck()
                }
                .animation(.easeInOut, value: viewModel.accountCheckError)
                // Each step replaces the whole screen: let VoiceOver start over from the top.
                .onChange(of: viewModel.stateMachine.index) {
                    VoiceOver.screenChanged()
                }
                // MARK: - Invite acceptance (moves an invited user into their flow)
                .onReceive(NotificationCenter.default.publisher(for: .willAcceptShare)) { _ in
                    guard viewModel.stateMachine.flow != .houseCreator else { return }
                    viewModel.isAcceptingInvite = true
                }
                .onReceive(NotificationCenter.default.publisher(for: .shareAcceptFailed)) { _ in
                    viewModel.isAcceptingInvite = false
                }
                .onReceive(NotificationCenter.default.publisher(for: .notAcceptShare)) { _ in
                    viewModel.isAcceptingInvite = false
                }
                .onReceive(NotificationCenter.default.publisher(for: .didAcceptShare)) { _ in
                    Task {
                        defer { viewModel.isAcceptingInvite = false }
                        
                        // A house creator mid-flow must not be switched to an invited flow:
                        // the same index means a different step there.
                        guard viewModel.stateMachine.flow != .houseCreator else { return }
                        viewModel.isAcceptingInvite = true
                        
                        // On a cold launch through the invite link this can fire before
                        // `checkExistingAccount()` loaded the profile. Treating that as "no
                        // profile" sent the user down `.invitedWithoutProfile` past the
                        // profile step, so `joinHouse()` never ran and no public user was created.
                        if viewModel.currentUser == nil {
                            await viewModel.fetchCurrentUser()
                        }
                        
                        if viewModel.currentUser != nil {
                            viewModel.stateMachine.flow = .invitedWithProfile
                            if await viewModel.joinHouse() {
                                await viewModel.advanceAfterJoiningHouse()
                            }
                        } else {
                            viewModel.stateMachine.flow = .invitedWithoutProfile
                        }
                    }
                }
        }
        .blockingWhileUnlinkingOrphanedHouse()
        // MARK: - Account check and restoring the saved step
        .task {
            await viewModel.checkExistingAccount()

            // Without a connection there is nothing to restore: ``ConnectionErrorView`` retries both.
            if !viewModel.isOnboardingSkipped, viewModel.accountCheckError == nil {
                await viewModel.restoreProgressIfNeeded()
            }
            
            viewModel.isRestoringSession = false
        }
    }
    
    // MARK: - Steps

    /// Maps the state machine's current step to its screen.
    @ViewBuilder
    private func stepView(for stateMachine: OnboardingStateMachine) -> some View {
        switch stateMachine.current {
        case .welcome:
            WelcomeOnboardingView(viewModel: $viewModel)
            
        case .createProfile:
            CreateProfileOnboardingView(viewModel: $viewModel)
            
        case .createOrEnterHome:
            CreateOrEnterHouseOnboardingView(viewModel: $viewModel)
            
        case .waitAcceptLink:
            WaitAcceptLinkOnboardingView(viewModel: $viewModel)
            
        case .chooseRooms:
            SelectRoomsOnboardingView(viewModel: $viewModel)
            
        case .inviteAndConfirmJoin:
            InviteUsersOnboardingView(viewModel: $viewModel, isFromSettings: false)
            
        case .setUpScheduleChores:
            StartChoreDivisionOnboardingView(viewModel: $viewModel)
            
        case .chooseChores:
            SelectChoresOnboardingView(viewModel: $viewModel)
            
        case .chooseFreeTime:
            SelectFreeTimeOnboardingView(viewModel: $viewModel)
            
        case .waitAdminScheduling:
            WaitHouseCreatorSheduleView(viewModel: $viewModel)
            
        case .scheduleChores:
            FortnightlyScheduleView(
                shouldGenerate: viewModel.stateMachine.isOwner ?? false,
                knownChoreIDs: viewModel.createdChoreRecordIDs
            ) {
                viewModel.finishOnboarding()
            }
        case .waitGuestsFreeTime:
            InviteAndWaitUsersFreeTimeOnboardingView(viewModel: $viewModel, isFromSettings: false)
            
        case .none:
            EmptyView()
        }
    }
}

#Preview {
    @Previewable @State var didOnboard = false
    Onboarding(didOnboard: $didOnboard)
}
