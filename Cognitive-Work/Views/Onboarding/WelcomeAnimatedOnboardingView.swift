//
//  WalcomeAnimatedOnboardingView.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 02/10/26.
//

import SwiftUI
import Foundation

/// The welcome screen: columns of chore cards scrolling in the background and a white panel that
/// slides up with the app's pitch and a "Continuar" button.
struct WelcomeAnimatedOnboardingView: View{
    /// The onboarding's view model.
    @Binding var viewModel: OnboardingViewModel
    
    /// Whether the white panel is up (it slides in when the screen appears).
    @State var showSheet: Bool = false
    
    /// Mock columns, built only once since ``ChoreDTO`` is a class.
    private let columns = ChoreDTO.columnsMock
    
    /// Speed of each column, in points per second.
    private static let speeds: [Double] = [17, 19, 17, 19]
    
    /// Starting offset of each column, in points. A card plus its spacing is 186pt.
    private static let phases: [Double] = [93, 40, 0, 40]
    
    var body: some View {
        ZStack {
            // MARK: - Background color
            Color(.onboardingBackground)
            
            // MARK: - Scrolling columns of chore cards
            HStack(alignment: .top, spacing: 16) {
                ForEach(columns.indices, id: \.self) { index in
                    InfinityRow(cards: columns[index],
                                movesUp: index.isMultiple(of: 2),
                                speed: Self.speeds[index % Self.speeds.count],
                                phase: Self.phases[index % Self.phases.count])
                    .frame(width: 110)
                }
            }
            .frame(width: width, height: height, alignment: .top)
            .clipped()
            .accessibilityDecorative()
            
            // MARK: - White panel: pitch texts
            if showSheet {
                
                VStack(alignment: .leading){
                    Text("Dividir a casa vai além da faxina")
                        .font(.custom("Alan Sans", size: 32, relativeTo: .largeTitle))
                        .bold()
                        .font(.largeTitle)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, height * 0.028)
                        .padding(.top, height * 0.052)
                    Text("Cuidar da casa também é lembrar e perceber o que falta. O Pipa organiza as tarefas e reconhece o trabalho de todos.")
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, height * 0.028)
                    
                    Text("Pipa. Para aqueles que notam.")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Spacer()
                }
                .padding(.horizontal, height * 0.028)
                .padding(.bottom, height * 0.15)
                .frame(width: width)
                .frame(minHeight: height * 0.6, alignment: .top)
                .fixedSize(horizontal: false, vertical: true)
                .background(Color.white)
                .clipShape (
                    UnevenRoundedRectangle(topLeadingRadius: 32,topTrailingRadius: 32,style: .continuous)
                )
                // MARK: Round "Continuar" button
                .overlay(alignment: .bottomTrailing) {
                    
                    Button("Continuar", systemImage: "chevron.right") {
                        // A returning user (profile and free time already saved) goes straight
                        // to "create or enter a house"; a new one goes on to the profile.
                        viewModel.advanceFromWelcome()
                    }
                    // Where "Continuar" leads depends on the account check that runs when this
                    // screen opens.
                    .disabled(viewModel.isCheckingAccount)
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
                .frame(maxHeight: .infinity, alignment: .bottom)
                .transition(.move(edge: .bottom))
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1)) {
                showSheet = true
            }
            // The panel replaces the logo screen: VoiceOver re-reads from its title.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                VoiceOver.screenChanged()
            }
        }
        .transition(.move(edge: .bottom))
        .ignoresSafeArea()
    }
}

#Preview {
    @Previewable @State var viewModel = OnboardingViewModel()
    WelcomeAnimatedOnboardingView(viewModel: $viewModel)
}
