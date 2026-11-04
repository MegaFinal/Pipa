//
//  WaitingAlgorithmView.swift
//  Cognitive-Work
//
//  Created by anshu Li on 26/08/26.
//

import SwiftUI

/// The waiting screen shown while the division of chores is generated: still chore cards in the
/// background and a card with a spinning icon and "Levantando escalas".
struct WaitingAlgorithmView: View {
    /// Sample chores for the background columns.
    private let columns = ChoreDTO.columnsMock
    /// The icon's angle; animated forever.
    @State private var isRotating = 0.0
    
    var body: some View {
        ZStack {
            // MARK: - Background: columns of sample chore cards
            HStack(alignment: .top, spacing: 16) {
                ForEach(columns.indices, id: \.self) { index in
                    InfinityRow(
                        cards: columns[index],
                        movesUp: index.isMultiple(of: 2),
                        speed: 0,
                        phase: Double(index) * 130
                    )
                    .frame(width: 110)
                }
            }
            .frame(width: width, height: height, alignment: .top)
            .clipped()
            .opacity(0.6)
            // Moving cards in the background are decoration.
            .accessibilityDecorative()
            
            // MARK: - Card: spinning icon, title and explanation
            VStack(spacing: 30) {
                Image("loadingIcon")
                    .rotationEffect(.degrees(isRotating))
                    .accessibilityDecorative()
                    .onAppear {
                        withAnimation(.linear(duration: 1)
                            .speed(0.1).repeatForever(autoreverses: false)) {
                                isRotating = 360.0
                            }
                    }
                
                Text("Levantando escalas")
                    .font(.custom("Alan Sans", size: 32, relativeTo: .largeTitle))
                    .bold()
                    .foregroundStyle(.titleGray)
                
                VStack(spacing: 15) {
                    Text("Estamos ponderando, sorteando e dividindo as tarefas entre os moradores")
//                    Text("Enviaremos uma notificação quando a divisão estiver pronta")
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            }
            .frame(width: width * 0.8)
            .padding(.horizontal, 16)
            .padding(.top, 36)
            .padding(.bottom, 24)
            .background(
                RoundedRectangle(cornerRadius: 32)
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.2), radius: 3.2, x: 0, y: 4)
            )
            // Title and explanation read together, marked as an ongoing state.
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
        }
        .ignoresSafeArea()
        .onAppear {
            VoiceOver.announce(L10n.tr("Levantando escalas. Aguarde enquanto dividimos as tarefas entre os moradores."))
        }
    }
}

#Preview {
    WaitingAlgorithmView()
}
