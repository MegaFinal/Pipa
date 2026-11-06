//
//  ReceiptCategoryCard.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 06/11/26.
//

import SwiftUI

/// The products of one aisle on the receipt review, in a compact version of the shopping
/// list's card (``ShopSectionCard``): a short banner in the aisle's color with its icon, name,
/// count and a chevron that collapses the card, then the rows separated by dotted lines.
struct ReceiptCategoryCard<Row: View>: View {

    let section: ReceiptCategorySection
    /// Whether the rows show (only the banner otherwise).
    let isExpanded: Bool
    /// Collapses or opens the card.
    let onToggle: () -> Void
    @ViewBuilder let row: (ReceiptScanLine) -> Row

    private let cornerRadius: CGFloat = 18

    var body: some View {
        VStack(spacing: 0) {
            header

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(section.lines) { line in
                        row(line)

                        if line.id != section.lines.last?.id {
                            ShopDottedDivider()
                                .padding(.vertical, 10)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemBackground))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
    }

    /// The short banner: icon, aisle, count and the collapse chevron.
    private var header: some View {
        Button {
            HapticsManager.selection()
            onToggle()
        } label: {
            HStack(spacing: 8) {
                SymbolImage(name: section.category.symbol)
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)

                Text(section.category.displayName)
                    .font(.custom("Alan Sans", size: 18))
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("\(section.lines.count)")
                    .font(.system(size: 15))

                Spacer(minLength: 8)

                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.white)
            .padding(.leading, 10)
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 48)
            .background(section.category.color)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .voiceOverLabel(section.category.displayName)
        .voiceOverValue(L10n.tr("\(section.lines.count) itens"))
        .voiceOverHint(isExpanded ? L10n.tr("Toque duas vezes para recolher.") : L10n.tr("Toque duas vezes para expandir."))
        .voiceControlNames([section.category.displayName])
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Previews

#Preview {
    ReceiptCategoryCardPreview()
}

/// Preview host that keeps which cards are collapsed.
private struct ReceiptCategoryCardPreview: View {
    @State private var viewModel = ReceiptScanPreviewData.review(of: ReceiptScanPreviewData.shopList)
    @State private var collapsed: Set<ShopItemCategory> = [.cleaning]

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(viewModel.sections) { section in
                    ReceiptCategoryCard(
                        section: section,
                        isExpanded: !collapsed.contains(section.category),
                        onToggle: {
                            withAnimation(.snappy) {
                                if collapsed.contains(section.category) {
                                    collapsed.remove(section.category)
                                } else {
                                    collapsed.insert(section.category)
                                }
                            }
                        }
                    ) { line in
                        ReceiptLineRow(
                            name: line.name,
                            detailText: viewModel.detailText(for: line),
                            users: viewModel.consumers(for: line),
                            needsReview: line.warning != nil,
                            isIncluded: viewModel.isIncluded(line),
                            onToggle: { viewModel.toggle(line) },
                            onEdit: {}
                        )
                    }
                }
            }
            .padding(20)
        }
    }
}
