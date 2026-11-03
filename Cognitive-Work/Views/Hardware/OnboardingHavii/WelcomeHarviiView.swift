//
//  WelcomeHarviiView.swift
//  Cognitive-Work
//
//  Created by Carolina Sun on 28/10/26.
//

import SwiftUI

struct WelcomeHarviiView: View {
    /// The device connection's view model.
    @Bindable var viewModel: HardwareViewModel
    
    /// Closes the sheet.
    @Environment(\.dismiss) private var dismiss
    
    /// Whether the white panel is up (it slides in when the screen appears).
    @State var showSheet: Bool = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                heroImage
                
                if showSheet {
                    pitchPanel
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .transition(.move(edge: .bottom))
                }
            }
            .navigationDestination(isPresented: $viewModel.navigateToEnterHarviiNetworkView) {
                EnterHarviiNetwork(viewModel: viewModel, onClose: { dismiss() })
            }
            .onAppear {
                withAnimation(.easeOut(duration: 1)) {
                    showSheet = true
                }
            }
            .toolbar { closeToolbarItem }
            .background {
                Color(.onboardingBackground)
                    .ignoresSafeArea()
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - Subviews

private extension WelcomeHarviiView {
    
    /// Harvii picture at the top of the screen.
    var heroImage: some View {
        Image("onboardingHarvii")
            .resizable()
            .scaledToFit()
            .frame(width: width, height: height - 100, alignment: .top)
            .offset(y: height * 0.04)
            .shadow(radius: 4.0)
    }
    
    /// White panel with the pitch texts and the round "Continuar" button.
    var pitchPanel: some View {
        pitchTexts
            .padding(.horizontal, height * 0.028)
            .padding(.bottom, height * 0.15)
            .frame(width: width)
            .frame(minHeight: height * 0.55, alignment: .top)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color.white)
            .clipShape(
                UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous)
            )
            .overlay(alignment: .bottomTrailing) {
                continueButton
            }
    }
    
    /// Title and description of the panel.
    var pitchTexts: some View {
        VStack(alignment: .leading) {
            Text("As tarefas da casa, na parede")
                .font(.custom("Alan Sans", size: 32, relativeTo: .largeTitle))
                .bold()
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, height * 0.052)
                .padding(.bottom, height * 0.028)
            
            Text("O Harvii recebe as tarefas da Pipa pelo Wi-Fi da sua casa e atualiza sozinho. Ninguém precisa abrir o celular nem escrever nada.")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
    }
    
    /// Round chevron that goes to the next step.
    var continueButton: some View {
        Button("Continuar", systemImage: "chevron.right") {
            viewModel.navigateToEnterHarviiNetworkView = true
        }
        // Voice Control: short names for the icon-only chevron.
        .voiceControlNames([L10n.tr("Continuar"), L10n.tr("Próximo"), L10n.tr("Avançar")])
        .bold()
        .labelStyle(.iconOnly)
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .padding(.bottom, height * 0.073)
        .padding(.trailing, width * 0.061)
    }
    
    /// "X" that closes the sheet.
    var closeToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .voiceOverLabel(L10n.tr("Fechar"))
            .voiceControlNames([L10n.tr("Fechar"), L10n.tr("Cancelar")])
        }
    }
}

#Preview {
    WelcomeHarviiView(viewModel: HardwareViewModel())
}
