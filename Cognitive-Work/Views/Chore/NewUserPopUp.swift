//
//  NewUserPopUp.swift
//  Cognitive-Work
//
//  Created by Isabela Hissa Pinto on 09/10/26.
//

import SwiftUI

/// The pop-up shown to the admin when a new member joins the house, offering to divide the
/// chores again now or later.
struct NewUserPopUp: View {
    /// Runs on "Divisão automática de tarefas".
    var onPress: () -> Void
    /// Runs on "Dividir mais tarde".
    var onDismiss: () -> Void

    /// Moves the VoiceOver cursor to the title when the pop-up appears.
    @AccessibilityFocusState private var isTitleFocused: Bool
    
    var body: some View {
        VStack (alignment: .leading) {
            
            // MARK: - Icon
            HStack {
                Spacer()
                Image(systemName: "person.circle")
                    .resizable()
                    .frame(width: width * 0.24, height: width * 0.24)
                    .padding(.bottom, height * 0.04)
                    .foregroundStyle(.choreOrange)
                    .padding(.top, height * 0.04)
                    .accessibilityDecorative()
                Spacer()
            }
        
                // MARK: - Title and explanation
                Text("Um novo morador entrou na casa!")
                    .font(.system(size: 28))
                    .bold()
                    .multilineTextAlignment(.leading)
                    .padding(.bottom, 8)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($isTitleFocused)
                
                Text("Clique no botão abaixo para dividir as tarefas novamente ou divida depois acessando a tela de notificações.")
                    .font(.system(size: 20))
                    .fontWeight(.regular)
                    .multilineTextAlignment(.leading)
                    .padding(.bottom, 32)
            
            // MARK: - Actions: divide now or later
            Button {
                onPress()
            } label: {
                Text("Divisão automática de tarefas")
                    .frame(minWidth: width * 0.69, minHeight: height * 0.037)
                    .multilineTextAlignment(.center)
                    .fontWeight(.medium)
                    .font(.system(size: 18))
            }
            .padding(.bottom, 16)
            .buttonStyle(.glassProminent)
            .glassEffectTransition(.identity)
            
            HStack {
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Text("Dividir mais tarde")
                        .fontWeight(.semibold)
                        .font(.system(size: 15))
                        .foregroundStyle(.gray) 
                }
                Spacer()
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 22)
        .frame(width: width * 0.87)
        .background(
            RoundedRectangle(cornerRadius: 32)
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.2), radius: 3.2, x: 0, y: 4)
        )
        // MARK: - Accessibility: a modal the user can close with the escape gesture
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { onDismiss() }
        .task {
            // Waits for the appear transition, otherwise the focus stays on the screen behind.
            try? await Task.sleep(for: .seconds(0.4))
            isTitleFocused = true
        }
    }
}

#Preview {
    NewUserPopUp(onPress: {}, onDismiss: {})
}
