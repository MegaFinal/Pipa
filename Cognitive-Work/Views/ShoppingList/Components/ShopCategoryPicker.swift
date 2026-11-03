//
//  ShopCategoryPicker.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 08/10/26.
//

import SwiftUI

/// A horizontally scrolling row of category chips for the shopping item form.
struct ShopCategoryPicker: View {

    /// The selected category.
    @Binding var selection: ShopItemCategory

    var body: some View {
        ScrollViewReader { proxy in
            // MARK: - Scrolling row of chips (starts scrolled to the selection)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(ShopItemCategory.allCases) { category in
                        chip(for: category)
                            .id(category)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
            .onAppear {
                proxy.scrollTo(selection, anchor: .center)
            }
        }
    }

    /// One chip: the category's icon and name, filled with its color when selected.
    private func chip(for category: ShopItemCategory) -> some View {
        let isSelected = category == selection

        return Button {
            HapticsManager.selection()
            withAnimation(.snappy) { selection = category }
        } label: {
            HStack(spacing: 6) {
                SymbolImage(name: category.symbol)
                    .frame(width: 24, height: 24)

                Text(category.displayName)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Color.white : Color.titleGray)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(isSelected ? category.color : category.softColor.opacity(0.45))
            )
            .shadow(color: .black.opacity(isSelected ? 0.18 : 0), radius: 3, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .voiceOverLabel(category.displayName)
        .voiceOverTraits(.isSelected, when: isSelected)
    }
}

#Preview("Categorias") {
    @Previewable @State var food = ShopItemCategory.food
    @Previewable @State var pets = ShopItemCategory.pets

    VStack(alignment: .leading, spacing: 24) {
        ShopCategoryPicker(selection: $food)
        ShopCategoryPicker(selection: $pets)
    }
    .padding()
}
