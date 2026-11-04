//
//  HouseEditView.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 31/08/26.
//

import SwiftUI
import CloudKit

/// The "Deletar Casa" button, shown only to the house admin.
struct HouseEditView: View {
    /// Loads the house, checks if the user is the admin and deletes the house.
    @State var viewModel: HouseEditViewModel
    
    var body: some View {
        VStack {
            // MARK: - Loading, delete button (admin only) or "no house" message
            if viewModel.isLoading {
                ProgressView()
                    .voiceOverLabel(L10n.tr("Carregando"))
            } else if viewModel.house != nil {
                if viewModel.isUserAdmin {
                    Button {
                        Task {
                            await viewModel.deleteHouse()
                        }
                    } label: {
                        if viewModel.isDeleting {
                            ProgressView()
                                .voiceOverLabel(L10n.tr("Excluindo sua casa..."))
                        } else {
                            Text("Deletar Casa")
                                .foregroundColor(.red)
                        }
                    }
                    .disabled(viewModel.isDeleting)
                    .voiceControlNames([L10n.tr("Deletar Casa"), L10n.tr("Excluir"), L10n.tr("Apagar")])
                }
            } else {
                Text("Nenhuma casa encontrada.")
                    .foregroundColor(.gray)
            }
        }
        .padding()
        // MARK: - Checks whether the user is the admin
        .task {
            await viewModel.checkAdminStatus()
        }
    }
}

#Preview {
    let house = HouseModel(name: "Casa", description: "Casa para o preview")
    // The default zone's ownerName is already CKCurrentUserDefaultName, so isAdmin()
    // resolves to true and the preview renders the delete button.
    house.recordID = CKRecord.ID(recordName: "preview")
    
    let viewModel = HouseEditViewModel(house: house)
    
    return HouseEditView(viewModel: viewModel)
}
