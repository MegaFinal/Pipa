//
//  ReceiptReviewSection.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 09/11/26.
//

import SwiftUI

/// One of the two parts of the receipt review: "Da sua lista" (products that check off list
/// items) or "Fora da lista" (products added as new, already bought). A title with how many
/// products it has, one short line saying what confirming does with them, then their aisles
/// (``ReceiptCategoryGroup``).
struct ReceiptReviewSection<Row: View>: View {

    let title: String
    /// What confirming does with these products.
    let caption: String
    let sections: [ReceiptCategorySection]
    @ViewBuilder let row: (ReceiptScanLine) -> Row

    private var count: Int { sections.reduce(0) { $0 + $1.lines.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: title)
                        .font(.custom("Alan Sans", fixedSize: 24))
                        .fontWeight(.bold)
                        .foregroundStyle(.black)

                    Text("\(count)")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.subTitleGray)
                }
                .accessibilityElement(children: .ignore)
                .voiceOverLabel(title)
                .voiceOverValue(L10n.tr("\(count) itens"))
                .accessibilityAddTraits(.isHeader)

                Text(verbatim: caption)
                    .font(.system(size: 15))
                    .foregroundStyle(.subTitleGray)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 36) {
                ForEach(sections) { section in
                    ReceiptCategoryGroup(section: section, row: row)
                }
            }
        }
    }
}

// MARK: - Previews

#Preview {
    let viewModel = ReceiptScanPreviewData.review(of: ReceiptScanPreviewData.shopList)

    ScrollView {
        VStack(alignment: .leading, spacing: 56) {
            ReceiptReviewSection(
                title: "Da sua lista",
                caption: "Vão ser marcados como comprados.",
                sections: viewModel.listSections
            ) { line in
                Text(verbatim: viewModel.displayName(for: line))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ReceiptReviewSection(
                title: "Fora da lista",
                caption: "Vão entrar na lista já comprados.",
                sections: viewModel.otherSections
            ) { line in
                Text(verbatim: viewModel.displayName(for: line))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
    }
}
