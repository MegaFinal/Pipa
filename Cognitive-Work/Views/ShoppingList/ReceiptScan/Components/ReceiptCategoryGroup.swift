//
//  ReceiptCategoryGroup.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 09/11/26.
//

import SwiftUI

/// The products of one aisle on the receipt review. Lighter than the shopping list's cards: a
/// thin line in the aisle's color with its icon and name opens the group, and the rows sit right
/// on the screen's background, separated by the list's dotted lines.
struct ReceiptCategoryGroup<Row: View>: View {

    let section: ReceiptCategorySection
    @ViewBuilder let row: (ReceiptScanLine) -> Row

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            VStack(spacing: 0) {
                ForEach(section.lines) { line in
                    row(line)

                    if line.id != section.lines.last?.id {
                        ShopDottedDivider()
                            .padding(.vertical, 14)
                    }
                }
            }
        }
    }

    /// Icon, aisle and count in the aisle's color, followed by a thin line of the same color.
    private var header: some View {
        HStack(spacing: 8) {
            SymbolImage(name: section.category.symbol)
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)

            Text(section.category.displayName)
                .font(.custom("Alan Sans", fixedSize: 17))
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text("\(section.lines.count)")
                .font(.system(size: 15, weight: .semibold))

            Capsule()
                .fill(section.category.color)
                .frame(height: 2)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
        }
        .foregroundStyle(section.category.color)
        .accessibilityElement(children: .ignore)
        .voiceOverLabel(section.category.displayName)
        .voiceOverValue(L10n.tr("\(section.lines.count) itens"))
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Previews

#Preview {
    let viewModel = ReceiptScanPreviewData.review(of: ReceiptScanPreviewData.shopList)

    ScrollView {
        VStack(spacing: 36) {
            ForEach(viewModel.sections) { section in
                ReceiptCategoryGroup(section: section) { line in
                    ReceiptLineRow(
                        name: viewModel.displayName(for: line),
                        quantityText: ReceiptScanViewModel.quantityText(for: line),
                        priceText: ReceiptScanViewModel.priceText(for: line),
                        warning: line.warning,
                        users: viewModel.consumers(for: line),
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
