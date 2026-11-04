//
//  UnassignedChoreRow.swift
//  Cognitive-Work
//
//  Created by anshu Li on 16/09/26.
//

import SwiftUI

/// A chore nobody owns: name, frequency and priority tags and the room's icon, on the room's
/// color. Tapping it starts picking the chore.
struct UnassignedChoreRow: View {
    let item: CarouselViewModel.UnassignedItem
    let carouselViewModel: CarouselViewModel
    let onPick: (CarouselViewModel.UnassignedItem) -> Void
    
    private var room: RoomModel? { carouselViewModel.getRoom(for: item.chore) }
    
    var body: some View {
        Button {
            onPick(item)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.chore.localizedName)
                        .font(.system(size: 17))
                        .foregroundStyle(.white)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 6) {
                        CapsuleTag(
                            tagName: item.chore.frequency.displayName,
                            tagColor: item.chore.frequency.color,
                            textColor: item.chore.frequency.textColor,
                            horizontalPadding: 6,
                            verticalPadding: 1.5
                        )
                        
                        CapsuleTag(
                            tagName: item.chore.priorityTag.displayName,
                            tagColor: item.chore.priorityTag.color,
                            horizontalPadding: 6,
                            verticalPadding: 1.5
                        )
                    }
                }
                .padding(5)
                
                Spacer()
                
                SymbolImage(name: room?.symbol ?? item.chore.symbolName)
                    .frame(width: 34, height: 34)
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(room?.color.uiColor ?? .gray, in: .rect(cornerRadius: 22))
        }
        .buttonStyle(ScaleButtonStyle())
        .voiceOverLabel(accessibilityLabel)
        .voiceControlNames([item.chore.localizedName, L10n.tr("Pegar \(item.chore.localizedName)")])
        .voiceOverHint(L10n.tr("Toque duas vezes para pegar esta tarefa."))
    }
    
    /// "Lavar a louça, Cozinha, Prioridade média, …, sexta-feira, 25 de setembro".
    private var accessibilityLabel: String {
        var parts = [
            item.chore.localizedName,
            carouselViewModel.accessibilityRoomName(for: item.chore),
            carouselViewModel.accessibilityTagsText(for: item.chore)
        ]
        if let date = item.displayDate {
            parts.append(CarouselViewModel.accessibilityDateText(date))
        }
        return parts.joined(separator: ", ")
    }
    
    private struct ScaleButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.7 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}
