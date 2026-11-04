//
//  RetroNewChoresDivision.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 29/09/26.
//

import SwiftUI

/// The retrospective's last card for the admin: invites them to generate the new division of
/// chores now or later.
struct RetroNewChoresDivision: View {
    /// Called when "Divisão automática de tarefas" is tapped (`RetroViewModel.requestAutomaticDivision`).
    var onAutomaticDivision: () -> Void = {}
    /// Called when "Dividir mais tarde" is tapped (`RetroViewModel.deferDivision`).
    var onLater: () -> Void = {}
    
    var body: some View {
        VStack {
            // MARK: - Icon
            Image(systemName: "calendar.circle")
                .resizable()
                .frame(width: width * 0.24, height: width * 0.24)
                .padding(.bottom, height * 0.04)
                .foregroundStyle(.choreGreen)
                .padding(.top, height * 0.088)
            
            // MARK: - Title and explanation
            Text("Comece a nova divisão de tarefas da casa!")
                .font(.title)
                .bold()
                .multilineTextAlignment(.leading)
            
            Text("Clique no botão abaixo para dividir as tarefas entre todos os moradores da casa automaticamente")
                .font(.title3)
                .fontWeight(.regular)
                .multilineTextAlignment(.leading)

            Spacer()
            
            // MARK: - Actions: divide now or later
            Button {
                onAutomaticDivision()
            } label: {
                Text("Divisão automática de tarefas")
                    .frame(minWidth: width * 0.69, minHeight: height * 0.037)
                    .multilineTextAlignment(.center)
                    .fontWeight(.medium)
                    .font(.system(size: 18))
            }
            .buttonStyle(.glassProminent)
            .glassEffectTransition(.identity)
            
            Button {
                onLater()
            } label: {
                Text("Dividir mais tarde")
                    .fontWeight(.semibold)
                    .font(.subheadline)
                    .foregroundStyle(.gray) //arrumar o cinza depois
            }
        }
        .padding(16)
    }
}


#Preview {
    RetroNewChoresDivision()
}
