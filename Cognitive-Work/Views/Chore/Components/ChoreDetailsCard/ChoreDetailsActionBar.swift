//
//  ChoreDetailsActionBar.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 26/10/26.
//

import SwiftUI

/// Bar pinned to the top of the details card: close, the people responsible, and edit.
struct ChoreDetailsActionBar: View {
    let viewModel: ChoreDetailsViewModel
    /// Runs when "Fechar" is tapped. `nil` closes the card focused in the carousel.
    var onClose: (() -> Void)?
    
    @State private var showsEditSheet = false
    
    var body: some View {
        HStack {
            closeButton
            Spacer()
            responsibleUsers
            editButton
        }
        .padding(.horizontal, 15)
        .padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    private var closeButton: some View {
        Button {
            if let onClose {
                onClose()
            } else {
                viewModel.carouselViewModel.clearFocus()
            }
        } label: {
            Image(systemName: "xmark")
                .foregroundColor(.black)
        }
        .voiceOverLabel(L10n.tr("Fechar"))
        .voiceControlNames([L10n.tr("Fechar"), L10n.tr("Cancelar"), L10n.tr("Voltar")])
        .padding(12)
        .clipShape(Circle())
        .glassEffect()
    }
    
    /// One avatar for a single responsible, a stacked list for two or more.
    @ViewBuilder
    private var responsibleUsers: some View {
        let users = viewModel.responsibleUsers
        let label = viewModel.carouselViewModel.accessibilityResponsibleText(for: users)
        
        if users.count == 1 {
            UserProfilePictureTag(user: users.first, widthMultiplier: 0.08)
                .accessibilityElement(children: .ignore)
                .voiceOverLabel(label)
        } else {
            UserProfilePictureList(users: users, widthMultiplier: 0.08)
                .accessibilityElement(children: .ignore)
                .voiceOverLabel(label)
        }
    }
    
    private var editButton: some View {
        Button {
            showsEditSheet = true
        } label: {
            Image(systemName: "pencil")
                .foregroundColor(.white)
        }
        .sheet(isPresented: $showsEditSheet) {
            CreateAndEditChoreView(
                originalModel: viewModel.chore,
                availableHouseUsers: viewModel.carouselViewModel.userModels,
                carouselViewModel: viewModel.carouselViewModel,
                targetAssignments: viewModel.targetAssignments
            )
        }
        .voiceOverLabel(L10n.tr("Editar tarefa"))
        .voiceControlNames([L10n.tr("Editar"), L10n.tr("Editar tarefa"), L10n.tr("Lápis")])
        .voiceOverHint(viewModel.isDone ? L10n.tr("Tarefas concluídas não podem ser editadas.") : "")
        .disabled(viewModel.isDone)
        .padding(12)
        .background(viewModel.isDone ? Color.gray : Color.blue)
        .clipShape(Circle())
        .glassEffect()
    }
}
