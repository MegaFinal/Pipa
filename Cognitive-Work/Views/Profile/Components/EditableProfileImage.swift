//
//  EditableProfileImage.swift
//  Cognitive-Work
//
//  Created by Carolina Sun on 31/08/26.
//

import SwiftUI
import PhotosUI

/// Displays the user's profile photo, optionally wrapped in a `PhotosPicker` for editing.
///
/// In read-only mode, shows the `ProfileImage` as static content. In editing mode, wraps it in
/// a `PhotosPicker` with a camera badge overlay so the user can select a new photo.
struct EditableProfileImage: View {
    /// The user's photo, or `nil` for the placeholder.
    let image: UIImage?
    /// Whether the photo can be changed (wraps it in a photo picker).
    let isEditing: Bool
    /// The photo picked in the picker.
    @Binding var selection: PhotosPickerItem?
    
    /// Shows a spinner over the photo while `true`.
    var isLoading: Bool = false
    
    /// The user's banner. When set, the photo is drawn inside a ring with the banner's color and texture.
    var banner: ProfileBanner? = nil
    
    /// Runs when the pencil button on the banner is tapped. `nil` hides the button.
    var onEditBanner: (() -> Void)? = nil
    
    /// Size the empty-state circle is drawn at (from the handoff).
    fileprivate var elipseSize: CGFloat { width * 0.8 }

    /// Space the component claims in its parent's layout. The placeholder is
    /// larger and overflows this slot visually, so it never pushes or squeezes
    /// the views around it.
    private let layoutSize: CGFloat = 285

    var body: some View {
        Group {
            // MARK: - Photo picker while editing, plain photo otherwise
            if isEditing {
                PhotosPicker(selection: $selection, matching: .images) {
                    profileImage
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .accessibilityLabel(image == nil
                                    ? L10n.tr("Adicionar foto de perfil")
                                    : L10n.tr("Alterar foto de perfil"))
                .voiceOverValue(isLoading ? L10n.tr("Carregando foto") : "")
                // Voice Control: "Toque em Foto" instead of the full sentence.
                .voiceControlNames([L10n.tr("Foto"), L10n.tr("Alterar foto"), L10n.tr("Foto de perfil")])
            } else {
                profileImage
                    .accessibilityElement(children: .ignore)
                    .voiceOverLabel(L10n.tr("Foto de perfil"))
                    .accessibilityAddTraits(.isImage)
                    .accessibilityHidden(image == nil && !isLoading)
            }
        }
        .frame(width: layoutSize, height: layoutSize)
        // MARK: - Banner edit button
        .overlay {
            if banner != nil, let onEditBanner {
                bannerEditButton(action: onEditBanner)
            }
        }
    }
    
    /// The avatar: inside the banner ring when there is a banner, otherwise the plain circle.
    @ViewBuilder
    private var profileImage: some View {
        if let banner {
            bannerAvatar(banner)
        } else {
            plainProfileImage
        }
    }
    
    /// The circular avatar, falling back to a placeholder when no picture was chosen yet.
    private var plainProfileImage: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 285, height: 285)
                    .clipped()
                    .background(Color(.systemBackground))
            } else {
                placeholderRing
                    .overlay {
                        if !isLoading {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 65))
                                .foregroundStyle(.gray)
                        }
                    }
            }
        }
        .overlay {
            if isLoading {
                ZStack {
                    Color.black.opacity(image == nil ? 0 : 0.3)
                    ProgressView()
                        .controlSize(.large)
                        .tint(image == nil ? .gray : .white)
                }
            }
        }
        .clipShape(Circle())
        .shadow(radius: 5)
    }
}

extension EditableProfileImage {
    /// The dotted circle shown when there is no photo.
    fileprivate var placeholderRing: some View {
        Image("OnboardingElipse")
            .resizable()
            .frame(width: elipseSize, height: elipseSize)
    }
    
    /// Size of the photo inside the banner ring.
    fileprivate var innerSize: CGFloat { elipseSize * 0.7 }
    
    /// The photo inside a ring with the banner's color and texture.
    fileprivate func bannerAvatar(_ banner: ProfileBanner) -> some View {
        ZStack {
            RoomTextureBackground(color: banner.color, pattern: banner.pattern, zoom: 2)
                .frame(width: elipseSize, height: elipseSize)
            
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.white
                    if !isLoading {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 65))
                            .foregroundStyle(.gray)
                    }
                }
                
                if isLoading {
                    Color.black.opacity(image == nil ? 0 : 0.3)
                    ProgressView()
                        .controlSize(.large)
                        .tint(image == nil ? .gray : .white)
                }
            }
            .frame(width: innerSize, height: innerSize)
            .clipShape(Circle())
        }
        .frame(width: elipseSize, height: elipseSize)
        .clipShape(Circle())
        .shadow(radius: 5)
    }
    
    /// The pencil button at the bottom-right of the avatar, to change the banner.
    fileprivate func bannerEditButton(action: @escaping () -> Void) -> some View {
        let offset = elipseSize / 2 * 0.7071
        return Button {
            HapticsManager.selection()
            action()
        } label: {
            Image(systemName: "pencil")
                .font(.system(size: 28))
                .foregroundColor(.white)
                .padding(18)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(
            .regular.interactive().tint(.black),
            in: .circle
        )
        .disabled(isLoading)
        .voiceOverLabel(L10n.tr("Editar banner"))
        .voiceControlNames([L10n.tr("Editar banner"), L10n.tr("Banner"), L10n.tr("Editar")])
        .offset(x: offset, y: offset)
    }
}

#Preview("Visualização") {
    EditableProfileImage(image: nil, isEditing: false, selection: .constant(nil))
}

#Preview("Edição") {
    EditableProfileImage(image: nil, isEditing: true, selection: .constant(nil))
}
