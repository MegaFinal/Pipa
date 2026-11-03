//
//  ProfilePhotoPicker.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 21/10/26.
//

import SwiftUI
import PhotosUI

/// Opens the photo library to change the profile picture.
struct ProfilePhotoPicker: View {
    /// How the picker shows up over the avatar.
    enum Style {
        case pencilButton
        case avatar
    }
    
    /// The photo picked in the library.
    @Binding var selection: PhotosPickerItem?
    /// How the picker shows up.
    let style: Style
    
    var body: some View {
        switch style {
        case .pencilButton:
            picker {
                Image(systemName: "pencil")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .foregroundColor(.black)
                    )
            }
            .padding(11)
            
        case .avatar:
            picker {
                Color.clear.contentShape(Circle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    /// The library button with the label of each style.
    private func picker<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        PhotosPicker(selection: $selection, matching: .images, label: label)
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.tr("Alterar foto de perfil"))
            .voiceControlNames([L10n.tr("Foto"), L10n.tr("Alterar foto"), L10n.tr("Foto de perfil")])
    }
}
