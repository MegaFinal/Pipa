//
//  ChoresViewButtonsSection.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 31/08/26.
//

import SwiftUI

/// The floating buttons at the bottom-right of the chores screen: show the chores nobody took,
/// and create a new chore.
struct ChoresViewButtonsSection: View {
    
    /// Opens the new-chore form.
    @State private var showCreateView = false
    
    /// The chores screen's view model.
    @Bindable var carouselViewModel: CarouselViewModel

    /// The house members offered in the new-chore form.
    private var houseUsers: [UserModel] {
        carouselViewModel.userModels
    }
    
    var body: some View {
        HStack {
            Spacer()
            
            // MARK: - Unassigned chores button
            FloatingActionButton(systemImage: "hand.tap", symbolSize: 32, foreground: .black, tint: nil) {
                carouselViewModel.toggleUnassignedList()
            }
            .voiceOverLabel(L10n.tr("Tarefas para pegar"))
            .voiceControlNames([L10n.tr("Tarefas para pegar"), L10n.tr("Pegar tarefa"), L10n.tr("Tarefas sem responsável")])
            .voiceOverHint(L10n.tr("Mostra as tarefas sem responsável."))
            .voiceOverValue(carouselViewModel.isShowingUnassignedList ? L10n.tr("expandido") : L10n.tr("recolhido"))
            
            // MARK: - New chore button
            FloatingActionButton(systemImage: "plus") {
                showCreateView = true
            }
            .voiceOverLabel(L10n.tr("Nova tarefa"))
            .voiceControlNames([L10n.tr("Adicionar"), L10n.tr("Mais"), L10n.tr("Nova tarefa"), L10n.tr("Adicionar tarefa")])
        }
        .floatingActionPlacement()
        // MARK: - New-chore form
        .sheet(isPresented: $showCreateView) {
            CreateAndEditChoreView(
                originalModel: ChoreModel(
                    name: "",
                    description: "",
                    isDone: false,
                    frequency: .undefined,
                    duration: 0,
                    isPublic: true,
                    priorityTag: .undefined
                ),
                availableHouseUsers: houseUsers, carouselViewModel: carouselViewModel
            )
        }
    }
}

#Preview {
    NavigationStack {
        ChoresViewButtonsSection(carouselViewModel: CarouselViewModel())
    }
}
