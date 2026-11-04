//
//  ProfileBannerSheet.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 08/10/26.
//

import SwiftUI
import PhotosUI

/// Sheet where the user picks their picture and profile banner
struct ProfileBannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var photoSelection: PhotosPickerItem?
    @State private var selectedColor: RoomColor
    @State private var selectedPattern: RoomTexturePattern
    
    let image: UIImage?
    
    let photoPickerStyle: ProfilePhotoPicker.Style
    let onConfirm: (ProfileBanner) -> Void
    
    init(banner: ProfileBanner,
         image: UIImage? = nil,
         photoSelection: Binding<PhotosPickerItem?>,
         photoPickerStyle: ProfilePhotoPicker.Style,
         onConfirm: @escaping (ProfileBanner) -> Void) {
        self.image = image
        _photoSelection = photoSelection
        self.photoPickerStyle = photoPickerStyle
        self.onConfirm = onConfirm
        _selectedColor = State(initialValue: banner.color)
        _selectedPattern = State(initialValue: banner.pattern)
    }
    
    private var pattern: RoomTexturePattern {
        selectedPattern.resolved(for: selectedColor)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    hero
                    colorPicker
                    patternPicker
                }
                .padding(.bottom, 30)
            }
            .ignoresSafeArea(edges: .top)
            .scrollBounceBehavior(.basedOnSize)
            .background(Color.groupedBackground.ignoresSafeArea())
            .navigationTitle("Editar Perfil")
            .navigationBarTitleDisplayMode(.inline)
            // MARK: - Toolbar: cancel / confirm
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .voiceOverLabel(L10n.tr("Cancelar"))
                    .voiceControlNames([L10n.tr("Fechar"), L10n.tr("Cancelar")])
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        HapticsManager.notify(.success)
                        onConfirm(ProfileBanner(color: selectedColor, pattern: pattern))
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .voiceOverLabel(L10n.tr("Confirmar"))
                    .voiceControlNames([L10n.tr("Confirmar"), L10n.tr("Salvar"), L10n.tr("OK")])
                }
            }
        }
    }
    
    // MARK: - Banner
    
    private var hero: some View {
        ProfileHero(
            banner: ProfileBanner(color: selectedColor, pattern: pattern),
            image: image
        ) {
            ProfilePhotoPicker(selection: $photoSelection, style: photoPickerStyle)
        }
        .animation(.easeInOut(duration: 0.3), value: selectedColor)
        .animation(.easeInOut(duration: 0.3), value: pattern)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.tr("Pré-visualização do banner: \(selectedColor.voiceOverName), \(pattern.displayName)"))
    }
    
    // MARK: - Color
    
    /// One swatch per room color.
    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Cor")
            
            HStack(spacing: 29) {
                ForEach(RoomColor.allCases) { color in
                    ColorSwatch(color: color, isSelected: selectedColor == color) {
                        HapticsManager.selection()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                            selectedColor = color
                            selectedPattern = selectedPattern.resolved(for: color)
                        }
                    }
                }
                .padding(.bottom, 10)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .foregroundColor(.white)
        )
    }
    
    // MARK: - Pattern
    
    private var patternPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Estampas")
            
            HStack(spacing: 14) {
                ForEach(RoomTexturePattern.allCases, id: \.self) { option in
                    PatternSwatch(
                        color: selectedColor,
                        pattern: option,
                        isSelected: pattern == option,
                        isAvailable: option.isAvailable(for: selectedColor)
                    ) {
                        HapticsManager.selection()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                            selectedPattern = option
                        }
                    }
                }
                .padding(.bottom, 10)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .foregroundColor(.white)
        )
    }
    
    /// A section title ("Cor", "Grafismo").
    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 18, weight: .medium))
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    ProfileBannerSheet(banner: .default, photoSelection: .constant(nil), photoPickerStyle: .pencilButton) { _ in }
}
