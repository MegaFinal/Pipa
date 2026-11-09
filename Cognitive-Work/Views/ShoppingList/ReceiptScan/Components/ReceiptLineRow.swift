//
//  ReceiptLineRow.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 06/11/26.
//

import SwiftUI

/// One product read from the receipt, drawn like a shopping list row (``ShopListItemCard``):
/// who it's for, the name and what was bought, and the round check, which here says whether it
/// goes to the list. Tapping the row opens the product's form.
///
/// What the reader couldn't trust shows in orange (the quantity, the price or both), instead of
/// a generic warning icon, so the person sees right away what to fix.
struct ReceiptLineRow: View {

    /// The list item's name for a product on the list, what was read otherwise.
    let name: String
    /// "2 unidades" or "0,364 kg".
    let quantityText: String
    /// "R$ 5,98" or "Sem preço".
    let priceText: String
    /// What the reader flagged, if anything (``ReceiptLineWarning/flagsQuantity`` and
    /// ``ReceiptLineWarning/flagsPrice`` decide what turns orange).
    var warning: ReceiptLineWarning? = nil
    /// Who splits it.
    let users: [UserModel]
    let isIncluded: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void

    /// Height of the first line, so the avatars and the check line up with the name.
    private let firstLineHeight: CGFloat = 26

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            if !users.isEmpty {
                UserProfilePictureList(users: users, widthMultiplier: 0.065, spacing: -10)
                    .frame(height: firstLineHeight)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 18))
                    .fontWeight(.bold)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: firstLineHeight, alignment: .leading)

                // MARK: - Quantity · price, the doubtful part in orange
                HStack(spacing: 4) {
                    Text(verbatim: quantityText)
                        .foregroundStyle(warning?.flagsQuantity == true ? Color.orange : Color.primary)
                        .fontWeight(warning?.flagsQuantity == true ? .semibold : .regular)
                    Text(verbatim: "·")
                    Text(verbatim: priceText)
                        .foregroundStyle(warning?.flagsPrice == true ? Color.orange : Color.primary)
                        .fontWeight(warning?.flagsPrice == true ? .semibold : .regular)
                }
            }

            Spacer(minLength: 16)

            Button {
                HapticsManager.selection()
                onToggle()
            } label: {
                Image(systemName: isIncluded ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(.black)
                    .font(.system(size: 22))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .frame(height: firstLineHeight)
            .voiceOverLabel(L10n.tr("Incluir \(name)"))
            .voiceOverTraits(.isSelected, when: isIncluded)
            .voiceControlNames([L10n.tr("Incluir \(name)")])
        }
        .frame(maxWidth: .infinity)
        .opacity(isIncluded ? 1 : 0.5)
        .animation(.snappy, value: isIncluded)
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .accessibilityElement(children: .combine)
        .voiceOverValue(warning.map(ReceiptScanViewModel.warningText) ?? "")
        .voiceOverHint(L10n.tr("Toque duas vezes para editar."))
        .accessibilityAction(named: L10n.tr("Editar \(name)"), onEdit)
    }
}

// MARK: - Previews

#Preview {
    VStack(spacing: 24) {
        ReceiptLineRow(
            name: "Banana prata",
            quantityText: "0,364 kg",
            priceText: "R$ 3,62",
            users: [ShopListPreviewData.anshu],
            isIncluded: true,
            onToggle: {},
            onEdit: {}
        )
        // Price doesn't match quantity × unit price.
        ReceiptLineRow(
            name: "Refrigerante guaraná 2l",
            quantityText: "1 unidade",
            priceText: "R$ 8,49",
            warning: .totalMismatch(computed: 8.49, printed: 8.94),
            users: ShopListPreviewData.users,
            isIncluded: true,
            onToggle: {},
            onEdit: {}
        )
        // Nothing read: quantity and price in orange.
        ReceiptLineRow(
            name: "Pão de queijo",
            quantityText: "1 unidade",
            priceText: "Sem preço",
            warning: .noAmount,
            users: [ShopListPreviewData.jones],
            isIncluded: true,
            onToggle: {},
            onEdit: {}
        )
        ReceiptLineRow(
            name: "Chiclete",
            quantityText: "3 unidades",
            priceText: "R$ 7,50",
            users: [ShopListPreviewData.jones, ShopListPreviewData.carol],
            isIncluded: false,
            onToggle: {},
            onEdit: {}
        )
    }
    .padding(20)
}
