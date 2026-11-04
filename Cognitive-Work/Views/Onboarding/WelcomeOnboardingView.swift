//
//  FirstOnboardingView.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 19/08/26.
//

import SwiftUI

/// The first screen of the onboarding: the app's logo with a "deslize para continuar!" hint.
///
/// Swiping up opens ``WelcomeAnimatedOnboardingView``, the animated panel with the app's pitch and
/// the "Continuar" button. When it appears, it also checks whether the iCloud account already
/// has a profile, which decides where "Continuar" leads.
struct WelcomeOnboardingView: View {
    /// Whether the description panel is expanded, replacing the initial tagline
    @State private var isExpanded = false
    /// Whether the "swipe up" hint indicator is currently visible
    @State private var isSwipeVisible = false
    /// Whether the iCloud alert is currently visible.
    @State private var showICloudAlert = false
    
    /// Not used.
    @State var bool = true
    
    /// The shared view model for navigation and state across the onboarding flow
    @Binding var viewModel: OnboardingViewModel
    
    
    var body: some View {
        ZStack {
            // MARK: - Background
            Color(.onboardingBackground)
            // MARK: - Logo (moves to the top when expanded)
            VStack(spacing: 30) {
                Image("pipaOnboarding")
                    .resizable()
                    .frame(width: width * 0.708, height: height * 0.208)
                    .accessibilityLabel(Text(verbatim: "Pipa"))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityAction(named: Text(L10n.tr("Continuar"))) { expand() }
                    // Voice Control: "Mostrar ações para Pipa" lists the swipe-up replacement.
                    .voiceControlNames(["Pipa", L10n.tr("Logo")])
                
            }
            .frame(maxHeight: .infinity, alignment: isExpanded ? .top : .center)
            .ignoresSafeArea(edges: isExpanded ? .top : [])
            .padding(.top, 5)
            
            // MARK: - "Swipe up" hint
            if isSwipeVisible {
                swipeIndicator
            }
            
            // MARK: - Animated panel after the swipe
            if isExpanded {
                WelcomeAnimatedOnboardingView(viewModel: $viewModel)
            }
        }
        .ignoresSafeArea(.all)
        // MARK: - Swipe up to expand
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.height < -50 {
                        expand()
                    }
                }
        )
        // MARK: - Account check and delayed hint
        .onAppear {
            Task {
                await viewModel.checkExistingAccount()
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if !isExpanded {
                    withAnimation(.easeIn(duration: 0.8)) {
                        isSwipeVisible = true
                    }
                }
            }
        }
        // MARK: - iCloud alert
        .alert("Continue com seu iCloud", isPresented: $showICloudAlert) {
            Button("Continuar") {}
        } message: {
            Text("O Pipa usa a conta do iCloud do seu iPhone para guardar os dados da sua casa com segurança e sincronizar tudo entre você e os demais moradores. Verifique se você está conectado a uma conta do iCloud nos Ajustes do seu iPhone para continuar.")
        }
    }
    
    
    // MARK: - Actions
    
    /// Opens the description panel (swipe up, or the VoiceOver "Continuar" action).
    private func expand() {
        guard !isExpanded else { return }
        withAnimation(.easeInOut(duration: 0.6)) {
            isExpanded = true
            isSwipeVisible = false
        }
    }
    
    // MARK: - Subviews
    
    /// A hint prompting the user to swipe up to continue.
    private var swipeIndicator: some View {
        VStack(spacing: 10) {
            Image(systemName: "chevron.up")
                .font(.system(size: 20))
            
            Text("deslize para continuar!")
            
        }
        .foregroundColor(.swipeWelcomeView)
        .transition(.opacity)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, height * 0.07)
        .fontWeight(.semibold)
        // VoiceOver can't swipe up on the screen: this hint becomes a "Continuar" button.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(L10n.tr("Continuar")))
        .accessibilityHint(Text(L10n.tr("Mostra a apresentação do Pipa")))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { expand() }
        // Voice Control: the visible hint first, then the short action name.
        .voiceControlNames([L10n.tr("deslize para continuar!"), L10n.tr("Continuar"), L10n.tr("Deslizar")])
    }
}

#Preview {
    @Previewable @State var viewModel = OnboardingViewModel()
    WelcomeOnboardingView(viewModel: $viewModel)
}
