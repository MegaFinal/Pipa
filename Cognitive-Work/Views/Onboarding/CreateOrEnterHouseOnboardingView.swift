//
//  ThirdOnboardingView.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 19/08/26.
//

import SwiftUI
import CloudKit

/// The onboarding step where the user chooses to create a new house (becoming its admin) or to
/// join one that already exists.
struct CreateOrEnterHouseOnboardingView: View {
    
    // MARK: - Properties
    
    /// The shared onboarding view model, read from the environment
    @Binding var viewModel: OnboardingViewModel
    
    /// `true` while the new house is being created.
    @State private var isCreatingHouse = false
    
    /// An invite is being accepted or the house joined (shown on the "Entrar" card).
    private var isEnteringHouse: Bool { viewModel.isAcceptingInvite || viewModel.isJoiningHouse }
    
    /// Whether any action is running (blocks the buttons and going back).
    private var isBusy: Bool { isCreatingHouse || isEnteringHouse || viewModel.isLoading }
    
    // MARK: - Body
    //
    // Two branching actions: joining an existing house switches the flow to
    // `.invitedWithProfile`, creating one saves the house before advancing.
    
    var body: some View {
        VStack(alignment: .center) {
            // MARK: - Header
            OnboardingHeader(
                title: "Bem vindo, \(viewModel.currentUser?.name ?? viewModel.userName)!",
                description: "Sua casa já está no Pipa?"
            )
            
            
            Spacer()
            
            // MARK: - "Criar uma casa" card
            Button {
                Task {
                    isCreatingHouse = true
                    defer { isCreatingHouse = false }
                    await viewModel.createHouseAndLinkUser()
                    
                    if viewModel.currentHouse != nil {
                        viewModel.stateMachine.flow = .houseCreator
                        viewModel.goToNextView()
                    }
                }
            } label: {
                VStack(alignment: .center){
                    if isCreatingHouse {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                    } else {
                        Image("HousePlus")
                            .resizable()
                            .frame(width: width * 0.297, height: height * 0.13)
                            .accessibilityDecorative()
            
                        VStack(alignment: .leading) {
                            Text("Criar uma casa")
                                .bold()
                                .font(.title2)
                            Text("Você será o administrador")
                                .font(.subheadline)
                        }
                        .padding(.horizontal, width * 0.04)
                        .frame(minWidth: width * 0.854, alignment: .leading)
                    }
                }
                .foregroundColor(.white)
                .frame(width: width * 0.854, height: height * 0.255)
                
            }
            .background {
                Color(.chorePurple)
                Image("purple.clouds")
                    .opacity(0.15)
                    .allowsHitTesting(false)
                    .accessibilityDecorative()
            }
            .clipShape(.rect(cornerRadius: 24))
            // `clipShape` only clips drawing, not hit testing: the texture (~566×753 pt, not
            // resizable) kept an invisible touch area far outside the card.
            .contentShape(.rect(cornerRadius: 24))
            .disabled(isBusy)
            .accessibilityLabel(Text(L10n.tr("Criar uma casa")))
            .voiceControlNames([L10n.tr("Criar uma casa"), L10n.tr("Criar casa"), L10n.tr("Criar")])
            .voiceOverValue(isCreatingHouse ? L10n.tr("Carregando") : "")
            .accessibilityHint(Text(L10n.tr("Você será o administrador")))
            
            // MARK: - "Entrar em uma casa" card
            Button {
                viewModel.stateMachine.flow = .invitedWithProfile
                viewModel.goToNextView()
            } label: {
                VStack{
                    // While an invite is accepted, only the icon becomes a spinner (same frame,
                    // so the card doesn't jump).
                    Group {
                        if isEnteringHouse {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.chorePurple)
                        } else {
                            Image("TocToc")
                                .resizable()
                                .accessibilityDecorative()
                        }
                    }
                    .frame(width: width * 0.414, height: height * 0.123)
                    .padding(.bottom, height * 0.018)
                    
                    VStack(alignment: .leading) {
                        Text("Entrar em uma casa")
                            .bold()
                            .font(.title2)
                        Text("A casa já foi criada por outro morador")
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                    }
                    .foregroundStyle(.chorePurple)
                    .padding(.horizontal, width * 0.04)
                    .frame(minWidth: width * 0.854, alignment: .leading)
                }
                .frame(width: width * 0.854, height: height * 0.255)
            }
            .background {
                Color(.lowOpacityPink)
                Image("purple.worms")
                    .opacity(0.15)
                    .allowsHitTesting(false)
                    .accessibilityDecorative()
            }
            .clipShape(.rect(cornerRadius: 24))
            // Same as above: this card's oversized texture was covering "Criar uma casa" and
            // swallowing its taps (it's later in the VStack, so it sits on top).
            .contentShape(.rect(cornerRadius: 24))
            .disabled(isBusy)
            .accessibilityLabel(Text(L10n.tr("Entrar em uma casa")))
            .voiceControlNames([L10n.tr("Entrar em uma casa"), L10n.tr("Entrar na casa"), L10n.tr("Entrar")])
            .voiceOverValue(isEnteringHouse ? L10n.tr("Entrando na casa") : "")
            .accessibilityHint(Text(L10n.tr("A casa já foi criada por outro morador")))
            
            Spacer()
        }
        .onboardingBackButton(viewModel: viewModel, isDisabled: isBusy)
        // MARK: - Error alert
        .alert("Não deu para criar a casa", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

#Preview {
    @Previewable @State var viewModel = OnboardingViewModel()
    CreateOrEnterHouseOnboardingView(viewModel: $viewModel)
}
