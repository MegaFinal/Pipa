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
struct ReceiptLineRow: View {

    let name: String
    /// "Na lista · 2 unidades · R$ 5,98".
    let detailText: String
    /// Who splits it.
    let users: [UserModel]
    /// The reader flagged the line: an orange mark beside the name.
    var needsReview = false
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
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 18))
                        .fontWeight(.bold)
                        .lineLimit(2)
                    if needsReview {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.orange)
                            .voiceOverLabel(L10n.tr("Confira este item"))
                    }
                }
                .frame(minHeight: firstLineHeight, alignment: .leading)

                Text(detailText)
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
        .voiceOverHint(L10n.tr("Toque duas vezes para editar."))
        .accessibilityAction(named: L10n.tr("Editar \(name)"), onEdit)
    }
}

// MARK: - Previews

#Preview {
    VStack(spacing: 24) {
        ReceiptLineRow(
            name: "Banana prata",
            detailText: "Na lista · 0,364 kg · R$ 3,62",
            users: [ShopListPreviewData.anshu],
            isIncluded: true,
            onToggle: {},
            onEdit: {}
        )
        ReceiptLineRow(
            name: "Refrigerante guaraná 2l",
            detailText: "1 unidade · R$ 8,49",
            users: ShopListPreviewData.users,
            needsReview: true,
            isIncluded: true,
            onToggle: {},
            onEdit: {}
        )
        ReceiptLineRow(
            name: "Chiclete",
            detailText: "3 unidades · R$ 7,50",
            users: [ShopListPreviewData.jones, ShopListPreviewData.carol],
            isIncluded: false,
            onToggle: {},
            onEdit: {}
        )
    }
    .padding(20)
    .background(Color(.secondarySystemBackground))
}
