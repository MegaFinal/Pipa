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
                Spacer()
            }
        
                // MARK: - Title and explanation
                Text("Um novo morador entrou na casa!")
                    .font(.title)
                    .bold()
                    .multilineTextAlignment(.leading)
                    .padding(.bottom, 8)
                
                Text("Clique no botão abaixo para dividir as tarefas novamente ou divida depois acessando a tela de notificações.")
                    .font(.title3)
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
                        .font(.subheadline)
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
    }
}

#Preview {
    NewUserPopUp(onPress: {}, onDismiss: {})
}
