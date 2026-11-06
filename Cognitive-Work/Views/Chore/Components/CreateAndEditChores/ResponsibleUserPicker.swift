//
//  ResponsibleUserPicker.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 30/08/26.
//

import SwiftUI
import CloudKit

/// Lets the user visually pick which house members are responsible for a chore.
///
/// Selected users are presented as a row of avatars that wraps to new lines when they don't fit. Tapping an avatar removes it from the
/// active selection. The trailing "+" button invokes a `Menu` listing every available user to add.
struct ResponsibleUserPicker: View {
    
    /// Every user in the house that can be assigned to the chore.
    let availableUsers: [UserModel]
    
    /// The collection of users currently bound to the chore.
    @Binding var selectedUsers: [UserModel]
    
    /// Evaluates if a given user is already present in the active selection.
    private func isSelected(_ user: UserModel) -> Bool {
        selectedUsers.contains { $0.id == user.id }
    }
    
    /// Avatar and "+" button size, as a fraction of the screen width.
    private let avatarWidthMultiplier = 0.11
    
    var body: some View {
        // Wraps to a new line when the avatars don't fit (big houses), instead of squeezing them.
        WrappingHStack(spacing: 10, lineSpacing: 12) {
            // MARK: - Selected members (tap one, or its "–" badge, to remove it)
            ForEach(selectedUsers) { selectedUser in
                UserProfilePictureTag(user: selectedUser, widthMultiplier: avatarWidthMultiplier)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "minus.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.choreOrange)
                            .font(.system(size: 18))
                            .offset(x: 3, y: -3)
                    }
                    .onTapGesture {
                        selectedUsers.removeAll { $0.id == selectedUser.id }
                    }
                    // VoiceOver: the avatar is a "remove this person" button.
                    .accessibilityElement(children: .ignore)
                    .voiceOverLabel(selectedUser.name)
                    .voiceOverHint(L10n.tr("Toque duas vezes para remover dos responsáveis."))
                    .accessibilityAddTraits(.isButton)
                    .voiceControlNames([selectedUser.name, L10n.tr("Remover \(selectedUser.name)")])
                    .accessibilityAction {
                        selectedUsers.removeAll { $0.id == selectedUser.id }
                        VoiceOver.announce(L10n.tr("\(selectedUser.name) removido"))
                    }
            }
            
            // MARK: - "+" menu to add or remove members
            Menu {
                ForEach(availableUsers) { user in
                    Button {
                        if isSelected(user) {
                            selectedUsers.removeAll { $0.id == user.id }
                        } else {
                            selectedUsers.append(user)
                        }
                    } label: {
                        if isSelected(user) {
                            Label(user.name, systemImage: "checkmark")
                        } else {
                            Text(user.name)
                        }
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22))
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(width: width * avatarWidthMultiplier, height: width * avatarWidthMultiplier)
                    .background(Color.blue)
                    .clipShape(Circle())
            }
            .voiceOverLabel(L10n.tr("Adicionar responsável"))
            .voiceControlNames([L10n.tr("Adicionar responsável"), L10n.tr("Adicionar"), L10n.tr("Mais")])
            .accessibilityValue(selectedUsers.isEmpty
                                ? L10n.tr("Sem responsável")
                                : selectedUsers.map(\.name).formatted(.list(type: .and).locale(L10n.locale)))
        }
    }
}

// MARK: - Previews

#Preview("Muitos moradores") {
    @Previewable @State var selected: [UserModel] = (1...9).map { index in
        let user = UserModel(name: "Morador \(index)", tier: .tier1, ownerRecordName: "preview-\(index)")
        user.recordID = CKRecord.ID(recordName: "preview-picker-user-\(index)")
        return user
    }
    ResponsibleUserPicker(availableUsers: selected, selectedUsers: $selected)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(22)
        .background(Color(.systemGray6))
}
