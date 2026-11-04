//
//  OnboardingChoreCard.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 02/10/26.
//

import SwiftUI
import Foundation

/// A small chore card used in the onboarding's animated background: name and room icon over
/// the room's color and texture.
struct OnboardingChoreCard: View {
    /// The chore on the card.
    let chore: ChoreDTO
    
    /// The chore's room.
    private var room: RoomDTO { chore.roomDTO }
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Chore name
            Text(chore.name)
                .font(.system(size: 16, weight: .semibold))
                .padding(.top, 14)
                .padding(.horizontal, 3)
            
            Spacer(minLength: 8)
            
            // MARK: - Room icon
            SymbolImage(name: room.symbol)
                .frame(width: 112, height: 112)
            
            Spacer(minLength: 12)
        }
        // MARK: - Card style
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoomTextureBackground(color: room.color, pattern: room.texturePattern)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(chore.name.localizedDefault), \(room.name.localizedDefault)"))
    }
}

// MARK: - Mock Data

extension ChoreDTO {
    /// Sample chore for the onboarding's animated background.
    static func mock(_ name: String, _ room: DefaultRoomsOnboarding) -> ChoreDTO {
        ChoreDTO(name: name,
                 description: "",
                 frequency: .weekly,
                 duration: 10,
                 priorityTag: .low,
                 room: room.roomDTO)
    }
    
    /// Four columns of sample chores, mixing colors so neighboring cards don't repeat.
    static let columnsMock: [[ChoreDTO]] = {
        let blue = [mock("Lavar o box", .bathroom), mock("Limpar a pia", .powderRoom),
                    mock("Lavar a roupa", .laundryRoom), mock("Limpar o espelho", .bathroom),
                    mock("Repor o papel", .powderRoom), mock("Estender a roupa", .laundryRoom),
                    mock("Limpar o ralo", .bathroom), mock("Passar a roupa", .laundryRoom)]
        let orange = [mock("Aspirar a sala", .livingRoom), mock("Lavar o carro", .garage),
                      mock("Passar pano", .livingRoom), mock("Varrer a garagem", .garage),
                      mock("Organizar o sofá", .livingRoom), mock("Guardar ferramentas", .garage),
                      mock("Tirar o pó", .livingRoom), mock("Arrumar a estante", .livingRoom)]
        let green = [mock("Regar as plantas", .garden), mock("Varrer a varanda", .balcony),
                     mock("Podar o jardim", .garden), mock("Regar a varanda", .balcony),
                     mock("Cortar a grama", .garden), mock("Lavar o piso", .balcony),
                     mock("Adubar as plantas", .garden), mock("Recolher a roupa", .balcony)]
        let yellow = [mock("Tirar o lixo", .kitchen), mock("Repor a despensa", .pantry),
                      mock("Lavar a louça", .kitchen), mock("Ver a validade", .pantry),
                      mock("Limpar o fogão", .kitchen), mock("Organizar potes", .pantry),
                      mock("Limpar a bancada", .kitchen), mock("Contar o estoque", .pantry)]
        let purple = [mock("Arrumar a cama", .bedroom), mock("Organizar a mesa", .homeOffice),
                      mock("Trocar lençóis", .bedroom), mock("Limpar o teclado", .homeOffice),
                      mock("Organizar o armário", .bedroom), mock("Guardar papéis", .homeOffice),
                      mock("Abrir a janela", .bedroom), mock("Limpar a tela", .homeOffice)]
        
        func column(_ pattern: [[ChoreDTO]], start: Int) -> [ChoreDTO] {
            var used = [Int](repeating: start, count: pattern.count)
            return (0..<12).map { position in
                let color = position % pattern.count
                defer { used[color] += 1 }
                return pattern[color][used[color] % pattern[color].count]
            }
        }
        
        return [
            column([blue, orange, green], start: 0),
            column([yellow, purple], start: 0),
            column([green, blue, orange], start: 3),
            column([purple, yellow], start: 3)
        ]
    }()
}

#Preview {
    let chore = ChoreDTO()
    OnboardingChoreCard(chore: chore)
}
