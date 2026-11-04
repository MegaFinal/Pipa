//
//  ShopListItemCard.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 08/10/26.
//

import SwiftUI
import CloudKit

/// One item of the shopping list
struct ShopListItemCard: View {
    var item: ShopListItem
    var relatedUsers: [UserModel]
    var onToggle: () async -> Void
    var onTap: () -> Void
    
    /// Blocks double taps while the change is being saved.
    @State private var isToggling = false
    
    private var quantityText: String {
        "\(item.quantity) \(item.unitMeasurement.getDisplayName(for: Double(item.quantity)))"
    }
    
    private var priceText: String? {
        guard let value = item.totalValue else { return nil }
        return value.formatted(.currency(code: "BRL").locale(L10n.locale))
    }
    
    var body: some View {
        rowLayout
        .frame(maxWidth: .infinity)
        .opacity(item.isBought ? 0.6 : 1)
        .animation(.snappy, value: item.isBought)
        .contentShape(RoundedRectangle(cornerRadius: 22))
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .ignore)
        .voiceOverLabel(ShopListViewModel.accessibilityLabel(for: item, relatedUsers: relatedUsers))
        .voiceOverHint(ShopListViewModel.accessibilityToggleName(for: item))
        .accessibilityAddTraits(.isButton)
        .voiceControlNames(ShopListViewModel.voiceControlInputLabels(for: item))
        .accessibilityAction {
            toggle()
        }
    }
    
    // MARK: - Layouts

    /// Height of the first line, so the avatars and the check line up with the name.
    private let firstLineHeight: CGFloat = 26

    private var rowLayout: some View {
        HStack(alignment: .top, spacing: 15) {
            if !relatedUsers.isEmpty {
                UserProfilePictureList(users: relatedUsers, widthMultiplier: 0.065, spacing: -10)
                    .frame(height: firstLineHeight)
            }

            VStack(alignment: .leading, spacing: 2) {
                nameText
                    .frame(minHeight: firstLineHeight, alignment: .leading)

                Text(quantityText)
            }

            Spacer(minLength: 16)

            checkButton
                .frame(height: firstLineHeight)
        }
    }

    // MARK: - Pieces
    
    /// The item's name, struck through when bought.
    private var nameText: some View {
        Text(item.name)
            .font(.system(size: 18))
            .fontWeight(.bold)
            .strikethrough(item.isBought)
            .lineLimit(2)
    }
    
    /// The round check button (spinner while saving).
    private var checkButton: some View {
        Button {
            toggle()
        } label: {
            ZStack {
                Image(systemName: item.isBought ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(.black)
                    .font(.system(size: 22))
                    .opacity(isToggling ? 0.4 : 1)
                
                if isToggling {
                    ProgressView().controlSize(.small)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isToggling)
        .voiceOverLabel(item.isBought ? L10n.tr("Marcar como não comprado") : L10n.tr("Marcar como comprado"))
    }

    /// Checks the item off (or puts it back), from the button or from VoiceOver.
    private func toggle() {
        guard !isToggling else { return }
        HapticsManager.notify(item.isBought ? .warning : .success)
        isToggling = true
        Task {
            await onToggle()
            isToggling = false
        }
    }
}

// MARK: - Previews

#Preview {
    VStack(spacing: 14) {
        ShopListItemCard(
            item: ShopListPreviewData.pendingItem,
            relatedUsers: [ShopListPreviewData.jones, ShopListPreviewData.isabela, ShopListPreviewData.carol],
            onToggle: {},
            onTap: {}
        )
        
        ShopListItemCard(
            item: ShopListPreviewData.boughtItem,
            relatedUsers: [ShopListPreviewData.jones, ShopListPreviewData.isabela],
            onToggle: {},
            onTap: {}
        )
        
        ShopListItemCard(
            item: ShopListPreviewData.longNameItem,
            relatedUsers: [],
            onToggle: {},
            onTap: {}
        )
    }
    .padding(.horizontal, 20)
}
