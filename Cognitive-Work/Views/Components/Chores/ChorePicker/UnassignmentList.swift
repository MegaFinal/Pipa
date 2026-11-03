//
//  UnassignmentList.swift
//  Cognitive-Work
//
//  Created by anshu Li on 16/09/26.
//

import SwiftUI

/// The pop-up list of chores nobody is responsible for, opened by the "hand" button on the chores
/// screen. Tapping a row picks the chore.
struct UnassignmentList: View {
    /// The chores (or occurrences) without anyone responsible.
    let items: [CarouselViewModel.UnassignedItem]
    /// Runs when the user picks a chore.
    let onPick: (CarouselViewModel.UnassignedItem) -> Void
    
    /// The chores screen's view model.
    @Bindable var carouselViewModel: CarouselViewModel
    
    /// Height of the scrolling area (title included) while the popup rests.
    private let scrollHeight: CGFloat = 220
    /// How far the content fades out over the popup's bottom padding.
    private let bottomFade: CGFloat = 20
    
    /// Hides the content gradually at its bottom edge (a mask, so it works over the glass).
    private var bottomFadeMask: some View {
        VStack(spacing: 0) {
            Rectangle()
            
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: bottomFade)
        }
    }
    
    var body: some View {
        Group {
            if items.isEmpty {
                // MARK: - Empty message
                content
            } else {
                // MARK: - Title and chores scroll together
                ScrollView(showsIndicators: false) {
                    content
                }
                // The content scrolls through the popup's bottom padding and fades out there,
                // instead of being cut sharply above the edge. The content margin keeps the
                // last row clear of the fade when the list is at rest.
                .contentMargins(.bottom, bottomFade, for: .scrollContent)
                .frame(maxHeight: scrollHeight + bottomFade)
                // The mask goes before the negative padding: it has to cover the whole extended
                // area, not just the smaller one the layout reserves.
                .mask { bottomFadeMask }
                .padding(.bottom, -bottomFade)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 20)
        .frame(width: width * 0.7)
        .glassEffect(.regular.tint(.white.opacity(0.35)), in: .rect(cornerRadius: 28))
        .shadow(radius: 28, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) {
            carouselViewModel.dismissUnassignedList()
        }
    }
    
    // MARK: - Pieces
    
    /// The title with its close hint, then the empty message or the chores.
    private var content: some View {
        VStack(alignment: .leading) {
            // MARK: Header: title and close hint
            HStack {
                Text("Tarefas para pegar")
                    .font(.system(size: 18))
                    .bold()
                    .foregroundStyle(.black)
                    .accessibilityAddTraits(.isHeader)
                
                Spacer()
                
                Image(systemName: "chevron.down")
                    // Visually just a hint; for VoiceOver it closes the popup.
                    .voiceOverLabel(L10n.tr("Fechar"))
                    .accessibilityAddTraits(.isButton)
                    .voiceControlNames([L10n.tr("Fechar"), L10n.tr("Cancelar")])
                    .accessibilityAction {
                        carouselViewModel.dismissUnassignedList()
                    }
            }
            
            // MARK: Empty message or the chores
            if items.isEmpty {
                Text("Nenhuma tarefa disponível no momento.")
                    .font(.system(size: 14))
                    .foregroundStyle(.gray)
                    .padding(.top, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        UnassignedChoreRow(item: item, carouselViewModel: carouselViewModel, onPick: onPick)
                    }
                }
            }
        }
    }
}

#Preview {
    UnassignmentList(items: [], onPick: { _ in }, carouselViewModel: CarouselViewModel())
}
