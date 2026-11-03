//
//  LoadingHarvii.swift
//  Cognitive-Work
//
//  Created by Carolina Sun on 28/10/26.
//

import SwiftUI

struct LoadingHarvii: View {
    /// Mock columns, built only once since ``ChoreDTO`` is a class.
    private let columns = ChoreDTO.columnsMock
    
    /// Speed of each column, in points per second.
    private static let speeds: [Double] = [17, 19, 17, 19]
    
    /// Starting offset of each column, in points. A card plus its spacing is 186pt.
    private static let phases: [Double] = [93, 40, 0, 40]
    
    /// Side margin of the whole screen, the same as the onboarding steps.
    private var sideMargin: CGFloat { width * 0.0565 }
    
    var body: some View {
        VStack(alignment: .center, spacing: 64) {
            ZStack {
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
                .frame(width: width * 0.87, height: height * 0.25, alignment: .top)
                .clipped()
                .accessibilityDecorative()
                
                RoundedRectangle(cornerRadius: 15)
                    .stroke(.black, lineWidth: 10)
                    .fill(.onboardingBackground.opacity(0.2))
                    .frame(width: width * 0.87, height: height * 0.25)
            }

            header
            .multilineTextAlignment(.center)
            
        }
    
    }
    private var header: some View {
        VStack(alignment: .center, spacing: height * 0.014) {
            // MARK: - Title
            Text("Harvii está recebendo as suas tarefas")
                .font(.custom("Alan Sans", size: 32, relativeTo: .largeTitle))
                .bold()
                .foregroundStyle(.titleGray)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            
            // MARK: - Description and optional detail
            VStack(alignment: .leading, spacing: 10) {
                Text("Pode levar até um minuto para a conexão estar completa. A tela do e-paper pisca um pouco antes de atualizar, é normal.")
            }
            .foregroundStyle(.subTitleGray)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: width * 0.8778, alignment: .leading)

    }
}

#Preview {
    LoadingHarvii()
}
