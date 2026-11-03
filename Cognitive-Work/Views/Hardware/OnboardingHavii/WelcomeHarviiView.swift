//
//  WelcomeHarviiView.swift
//  Cognitive-Work
//
//  Created by Carolina Sun on 28/10/26.
//

import SwiftUI

struct WelcomeHarviiView: View {
    
    /// Whether the white panel is up (it slides in when the screen appears).
    @State var showSheet: Bool = false
    
    var body: some View {
        
        ZStack{
            Image("onboardingHarvii")
                .resizable()
                .scaledToFit()
                .frame(width: width, height: height - 100, alignment: .top)
                .offset(y: height * 0.04)
                .shadow(radius: 4.0)
            
            // MARK: - White panel: pitch texts
            if showSheet {
                VStack(alignment: .leading){
                    Text("As tarefas da casa, na parede")
                        .font(.custom("Alan Sans", size: 32, relativeTo: .largeTitle))
                        .bold()
                        .font(.largeTitle)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.init(top: height * 0.052, leading: 0, bottom: height * 0.028, trailing: 0))
                    
                    Text("O Harvii recebe as tarefas da Pipa pelo Wi-Fi da sua casa e atualiza sozinho. Ninguém precisa abrir o celular nem escrever nada.")
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Spacer()
                }
                .padding(.horizontal, height * 0.028)
                .padding(.bottom, height * 0.15)
                .frame(width: width)
                .frame(minHeight: height * 0.55, alignment: .top)
                .fixedSize(horizontal: false, vertical: true)
                .background(Color.white)
                .clipShape (
                    UnevenRoundedRectangle(topLeadingRadius: 32,topTrailingRadius: 32,style: .continuous)
                )
                
                // MARK: Round "Continuar" button
                .overlay(alignment: .bottomTrailing) {
                    
                    Button("Continuar", systemImage: "chevron.right") {
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
                
                .frame(maxHeight: .infinity, alignment: .bottom)
                .transition(.move(edge: .bottom))
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1)) {
                showSheet = true
            }
        }
        .background {
            Color(.onboardingBackground)
                .ignoresSafeArea()
        }
        .ignoresSafeArea()

    }
}

#Preview {
    WelcomeHarviiView()
}
