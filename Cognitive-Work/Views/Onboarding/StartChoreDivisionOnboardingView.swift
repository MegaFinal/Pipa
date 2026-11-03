//
//  StartChoreDivisionOnboardingView.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 05/10/26.
//

import SwiftUI

/// The onboarding step that introduces the chore division to the admin, in three steps:
/// rooms, chores, and the app divides.
struct StartChoreDivisionOnboardingView: View {
    /// The onboarding's view model.
    @Binding var viewModel: OnboardingViewModel
    
    var body: some View {
        VStack(spacing: 30) {
            // MARK: - Header
            OnboardingHeader(
                title: "Hora de começar a divisão de tarefas",
                description: "Como administrador, você deverá selecionar as tarefas que serão divididas entre todos"
            )
            
            // MARK: - Three step cards
            VStack(spacing: 15) {
                InfoCard(
                    number: "1",
                    title: "Defina os cômodos",
                    description: "Escolha os cômodos que existem na sua casa",
                    tagColor: .choreBlue,
                    backgroundColor: .lowOpacityBlue
                )
                
                InfoCard(
                    number: "2",
                    title: "Escolha as tarefas",
                    description: "Selecione as tarefas que serão divididas igualmente entre todos",
                    tagColor: .choreYellow,
                    backgroundColor: .lowOpacityYellow
                )
                
                InfoCard(
                    number: "3",
                    title: "O Pipa divide!",
                    description: "O Pipa pega as informações de todos e divide as tarefas da melhor forma possivel!",
                    tagColor: .chorePurple,
                    backgroundColor: .lowOpacityPurple
                )
            }
            
            Spacer()
            
            // MARK: - "Iniciar divisão" button
            OnboardingProgressButton(
            text: "Iniciar divisão"
            ) {
                viewModel.goToNextView()
            }
        }
        .onboardingBackButton(viewModel: viewModel)
    }
}

/// A numbered step card: a colored number, a title and a description.
private struct InfoCard: View {
    /// The step's number.
    var number: String
    /// The step's title.
    var title: LocalizedStringKey
    /// The step's description.
    var description: LocalizedStringKey
    /// The number circle's color.
    var tagColor: Color
    /// The card's background color.
    var backgroundColor: Color
    
    var body: some View {
        HStack(spacing: 15) {
            // MARK: Number
            Text(number)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding()
                .background(
                    Circle()
                        .foregroundStyle(tagColor)
                )
                .accessibilityLabel(Text(L10n.tr("Etapa \(number) de \(3)")))
            
            // MARK: Title and description
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 20))
                    .bold()
                
                Text(description)
            }
        }
        .frame(width: width * 0.8)
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 32)
                .foregroundColor(backgroundColor.opacity(0.2))
        )
        // Read as one sentence: "Etapa 1 de 3, Defina os cômodos, Escolha os cômodos…".
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    @Previewable @State var viewModel = OnboardingViewModel()
    StartChoreDivisionOnboardingView(viewModel: $viewModel)
}
