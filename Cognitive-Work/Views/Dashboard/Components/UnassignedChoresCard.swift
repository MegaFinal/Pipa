//
//  UnassignedChoresCard.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 26/10/26.
//

import SwiftUI

/// The chores nobody owns, hanging on a clothesline. Tapping one shows its details under the line;
/// tapping those goes on to choose the day.
struct UnassignedChoresCard: View {
    let viewModel: ClotheslineViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summary
            
            if let item = viewModel.selectedItem {
                UnassignedChoreRow(
                    item: item,
                    carouselViewModel: viewModel.carouselViewModel,
                    onPick: { viewModel.pick($0) }
                )
                .padding([.horizontal, .bottom], 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: width - 32, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(.rect(cornerRadius: 31, style: .continuous))
    }
    
    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding([.horizontal, .top], 16)
                .accessibilityElement(children: .ignore)
                .voiceOverLabel(L10n.tr("\(viewModel.items.count) tarefas sem dono"))
                .accessibilityAddTraits(.isHeader)
            
            if viewModel.isEmpty {
                Text("Nenhuma tarefa disponível no momento.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else {
                ClotheslineCarousel(tiles: viewModel.tiles) { id in
                    withAnimation(.snappy) { viewModel.toggleSelection(of: id) }
                }
            }
        }
    }
    
    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(viewModel.items.count)")
                .font(.custom("Alan Sans", size: 64))
                .bold()
                .foregroundStyle(Color.choreOrange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Tarefas sem dono")
                    .font(.custom("Alan Sans", size: 24))
                    .bold()
                
                Text("O trabalho de notar, lembrar e distribuir tarefas também faz parte da organização da casa")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
