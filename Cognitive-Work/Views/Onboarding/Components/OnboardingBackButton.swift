//
//  OnboardingBackButton.swift
//  Cognitive-Work
//

import SwiftUI

/// Adds the onboarding "voltar" button to the toolbar, as a cancellation item.
///
/// Tapping it calls ``OnboardingViewModel/goBack()``, which deletes from CloudKit whatever
/// the previous step saved before showing it again. While that runs the chevron becomes a
/// spinner; if it fails, an alert explains why and the user stays where they are.
private struct OnboardingBackButtonModifier: ViewModifier {
    
    /// The onboarding state shared by every step.
    let viewModel: OnboardingViewModel
    
    /// Extra condition from the screen (e.g. an invite being accepted) that blocks going back.
    let isDisabled: Bool
    
    /// When set, asks for confirmation with this message before going back.
    let confirmationMessage: LocalizedStringKey?
    
    /// `true` outside onboarding (screens reused by settings keep the system back button).
    let isHidden: Bool
    
    /// `true` while the "go back?" confirmation is open.
    @State private var isConfirming = false
    
    /// Adds the back button, unless ``isHidden`` is `true`.
    @ViewBuilder
    func body(content: Content) -> some View {
        if isHidden {
            content
        } else {
            backButton(on: content)
        }
    }
    
    /// Hides the system back button and adds the onboarding's own, with its confirmation and error alert.
    private func backButton(on content: Content) -> some View {
        content
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        if confirmationMessage != nil {
                            isConfirming = true
                        } else {
                            goBack()
                        }
                    } label: {
                        if viewModel.isRollingBack {
                            ProgressView()
                        } else {
                            Image(systemName: "chevron.left")
                        }
                    }
                    .disabled(isDisabled || viewModel.isLoading || viewModel.isRollingBack)
                    .accessibilityLabel(Text(L10n.tr("Voltar")))
                    // Voice Control: "Toque em Voltar" for the icon-only chevron.
                    .voiceControlNames([L10n.tr("Voltar"), L10n.tr("Anterior")])
                    .voiceOverValue(viewModel.isRollingBack ? L10n.tr("Carregando") : "")
                }
            }
            .confirmationDialog(
                "Voltar para a etapa anterior?",
                isPresented: $isConfirming,
                titleVisibility: .visible
            ) {
                Button("Voltar", role: .destructive) { goBack() }
                Button("Cancelar", role: .cancel) {}
            } message: {
                if let confirmationMessage {
                    Text(confirmationMessage)
                }
            }
            .alert("Não deu para voltar", isPresented: Binding(
                get: { viewModel.rollbackErrorMessage != nil },
                set: { if !$0 { viewModel.rollbackErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { viewModel.rollbackErrorMessage = nil }
            } message: {
                Text(viewModel.rollbackErrorMessage ?? "")
            }
    }
    
    /// Undoes the previous step and goes back to it.
    private func goBack() {
        HapticsManager.impact(.light)
        Task { await viewModel.goBack() }
    }
}

extension View {
    /// Adds the onboarding "voltar" button (toolbar cancellation item, `chevron.left`).
    ///
    /// - Parameters:
    ///   - viewModel: The onboarding state shared by every step.
    ///   - isDisabled: Blocks going back while the screen is busy with something of its own.
    ///   - confirmationMessage: Asks before going back, for steps whose undo affects others.
    ///   - isHidden: Leaves the view untouched (e.g. the screen opened from settings).
    func onboardingBackButton(
        viewModel: OnboardingViewModel,
        isDisabled: Bool = false,
        confirmationMessage: LocalizedStringKey? = nil,
        isHidden: Bool = false
    ) -> some View {
        modifier(OnboardingBackButtonModifier(
            viewModel: viewModel,
            isDisabled: isDisabled,
            confirmationMessage: confirmationMessage,
            isHidden: isHidden
        ))
    }
}
