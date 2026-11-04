//
//  EditNameView.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 21/10/26.
//

import SwiftUI

/// Sheet where the user changes their name
struct EditNameView: View {
    @Bindable var viewModel: UserProfileViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Seu nome", text: $viewModel.editedName)
                        .characterLimit(TextLimits.userName, text: $viewModel.editedName)
                        .submitLabel(.done)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.groupedBackground.ignoresSafeArea())
            .disabled(viewModel.isSaving)
            .navigationTitle("Editar nome")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        Task { await viewModel.saveChanges() }
                    }
                    .disabled(!viewModel.canSave)
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isSaving)
        .onAppear { viewModel.startEditing() }
        .onDisappear {
            if viewModel.isEditing && !viewModel.isSaving { viewModel.cancelEditing() }
        }
        .onChange(of: viewModel.didSaveSuccessfully) { _, didSave in
            guard didSave else { return }
            viewModel.didSaveSuccessfully = false
            dismiss()
        }
        .alert(
            "Erro ao salvar",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

#Preview {
    EditNameView(viewModel: UserProfileViewModel())
}
