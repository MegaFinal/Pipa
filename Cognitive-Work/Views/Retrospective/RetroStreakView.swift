//
//  RetroStreakView.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 29/09/26.
//

import SwiftUI

/// The retrospective's streak page: how many days in a row the user did every chore on time.
///
/// > Note: Not finished yet. The number is fixed at 0 and the page is not in the retrospective's
/// > pager (see ``RetroPage``).
struct RetroStreakView: View {
    /// The pager's current page; "Continuar" moves it forward.
    @Binding var page: Int
    /// Set to `true` by "ver depois" to leave the pages.
    @Binding var isRetroDone: Bool
    
    var body: some View {
        VStack {
            
            Spacer()
            
            // MARK: - Flame icon
            Image(systemName: "flame.fill")
                .resizable()
                .frame(width: width * 0.54, height: height * 0.3)
                .foregroundStyle(.gray)
                .padding(.bottom, height * 0.037)
            
            // MARK: - Streak count and messages
            Text("0 dias")
                .bold()
                .font(.system(size: 64))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.bottom, height * 0.014)
            
            Text("seguidos sem atrasar nenhuma tarefa")
                .fontWeight(.regular)
                .font(.title)
                .multilineTextAlignment(.center)
                .padding(.bottom, height * 0.014)
            
            Text("Dá para começar ainda hoje!")
                .font(.callout)
                .foregroundStyle(.gray) //arrumar o cinza depois
                .padding(.bottom, height * 0.093)

            
            // MARK: - Actions: see later or continue
            Button {
                withAnimation {
                    isRetroDone = true
                }
            } label: {
                Text("ver depois")
                    .fontWeight(.semibold)
                    .font(.subheadline)
                    .foregroundStyle(.gray) //arrumar o cinza depois
            }
            
            
            Button {
                withAnimation {
                    page += 1
                }
            } label: {
                Text("Continuar")
                    .frame(minWidth: width * 0.69, minHeight: height * 0.037)
                    .multilineTextAlignment(.center)
                    .fontWeight(.medium)
                    .font(.system(size: 17))
            }
            .buttonStyle(.glassProminent)
            .glassEffectTransition(.identity)
        }
    }
}


#Preview {
    @Previewable @State var page = 1
    @Previewable @State var isRetroDone = false
    RetroStreakView(page: $page, isRetroDone: $isRetroDone)
}
