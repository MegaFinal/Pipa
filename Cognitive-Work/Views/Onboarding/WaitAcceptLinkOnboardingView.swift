//
//  WaitAcceptLinkOnboardingView.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 01/09/26.
//


import SwiftUI

/// Step shown after the user chooses to join an existing house.
///
/// The app cannot advance on its own here: the user has to open the invite link
/// they received, which triggers the system share-acceptance flow. ``Onboarding``
/// listens for `.didAcceptShare` and moves the flow forward once that happens.
struct WaitAcceptLinkOnboardingView: View {
    // MARK: - Properties
    
    /// State shared by every step of the flow.
    @Binding var viewModel: OnboardingViewModel
    
    /// The invite is being accepted or the house joined. Navigation is locked meanwhile, so the
    /// user can't leave halfway through and end up without a member record.
    private var isEnteringHouse: Bool {
        viewModel.isAcceptingInvite || viewModel.isJoiningHouse
    }
    
    /// Text of the message that asks the house admin for the invite link. Short, says who is asking
    /// and where from (the app), and what is wanted, since the admin may get it with no context.
    /// Resolved with ``L10n`` so it follows the language chosen in the app, not just the device's.
    private var inviteRequestMessage: String {
        let name = viewModel.currentUser?.name.trimmingCharacters(in: .whitespaces) ?? ""
        guard !name.isEmpty else {
            return L10n.tr("Oi! Baixei o Pipa e quero entrar na nossa casa. Pode me mandar o link de convite? 🏠")
        }
        return L10n.tr("Oi, aqui é \(name)! Baixei o Pipa e quero entrar na nossa casa. Pode me mandar o link de convite? 🏠")
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            VStack {
                // MARK: - Illustration and header
                Image("TocTocPurple")
                    .frame(width: width * 0.64, height: height * 0.19)
                    .accessibilityDecorative()
                    .padding(.bottom, height * 0.075)
                OnboardingHeader(
                    title: "Peça o convite para o administrador da casa",
                    description: "Quando receber o link, é só tocar nele para entrar na casa!"
                )
                // Not at the top of the screen (the illustration is above it), so it keeps
                // its distance from the image.
                .padding(.top, 20)
                .padding(.bottom, height * 0.052)
                
                
                
                // MARK: - "Entrando na casa..." or the button to ask for the invite
                if isEnteringHouse {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.chorePurple)
                        Text("Entrando na casa...")
                            .fontWeight(.semibold)
                            .foregroundStyle(.chorePurple)
                    }
                    .accessibilityElement(children: .combine)
                    .transition(.opacity)
                } else {
                    ShareLink(item: inviteRequestMessage) {
                        Label("Pedir o convite por mensagem", systemImage: "square.and.arrow.up")
                            .fontWeight(.semibold)
                    }
                    .voiceControlNames([L10n.tr("Pedir o convite por mensagem"), L10n.tr("Pedir convite"), L10n.tr("Compartilhar")])
                    .controlSize(.large)
                    .buttonStyle(.glassProminent)
                    .tint(.blue)
                    .transition(.opacity)
                }
                
                
            }
            .ignoresSafeArea()
            // MARK: - Background texture
            .background{
                Image("purple.worms")
                    .resizable()
                    .frame(width: height * 1.09, height: height * 1.09)
                    .opacity(0.2)
                    .accessibilityDecorative()
            }
            .padding(.horizontal, 10)
            .animation(.easeInOut(duration: 0.2), value: isEnteringHouse)
            .onChange(of: isEnteringHouse) { _, isEntering in
                if isEntering { VoiceOver.announce(L10n.tr("Entrando na casa...")) }
            }
            .navigationBarBackButtonHidden()
            // MARK: - Joins right away if the invite was accepted while the app was closed
            .task {
                // Covers the case where the invite was already accepted while the app was closed.
                // Check whether the house is already reachable (only true once the share
                // has been accepted) and advance the flow the same way the notification
                // handler in Onboarding.swift does.
                
                let houseFetched = await Task.detached(priority: .utility) {
                    return (try? await CloudKitManager.shared.fetchFirst(HouseModel.self)) != nil
                }.value
                
                guard houseFetched, viewModel.currentUser != nil else { return }
                
                viewModel.stateMachine.flow = .invitedWithProfile
                guard await viewModel.joinHouse() else { return }
                await viewModel.advanceAfterJoiningHouse()
            }
            // MARK: - Back button (locked while entering the house)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        guard !isEnteringHouse else { return }
                        viewModel.goToPreviousView()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(isEnteringHouse)
                    .accessibilityLabel(Text(L10n.tr("Voltar")))
                    .voiceControlNames([L10n.tr("Voltar")])
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var viewModel = OnboardingViewModel()
    WaitAcceptLinkOnboardingView(viewModel: $viewModel)
}
