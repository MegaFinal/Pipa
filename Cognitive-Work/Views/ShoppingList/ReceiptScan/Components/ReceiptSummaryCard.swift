//
//  ReceiptSummaryCard.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 06/11/26.
//

import SwiftUI

/// The top of the receipt review: the products' total, drawn like the balance on "Pendências"
/// (``DebtBalanceCard``). Green when it matches the receipt, orange with the receipt's total
/// when it doesn't, yellow when the receipt had no total to compare.
struct ReceiptSummaryCard: View {

    /// How the sum compares with the receipt.
    enum Status: Equatable {
        case matches
        /// The receipt's printed total ("R$ 25,49").
        case differs(receiptTotal: String)
        case unknown
    }

    /// "R$ 20,59".
    let totalText: String
    let status: Status

    var body: some View {
        DebtBalanceCard(
            title: L10n.tr("Total"),
            caption: caption,
            amountText: totalText,
            color: color
        )
    }

    private var caption: String {
        switch status {
        case .matches: L10n.tr("Bate com o total da nota")
        case .differs(let receiptTotal): L10n.tr("Total da nota: \(receiptTotal)")
        case .unknown: L10n.tr("Soma dos itens")
        }
    }

    private var color: RoomColor {
        switch status {
        case .matches: .green
        case .differs: .orange
        case .unknown: .yellow
        }
    }
}

// MARK: - Previews

#Preview {
    VStack(spacing: 20) {
        ReceiptSummaryCard(totalText: "R$ 25,49", status: .matches)
        ReceiptSummaryCard(totalText: "R$ 20,59", status: .differs(receiptTotal: "R$ 25,49"))
        ReceiptSummaryCard(totalText: "R$ 20,59", status: .unknown)
    }
    .padding()
}
