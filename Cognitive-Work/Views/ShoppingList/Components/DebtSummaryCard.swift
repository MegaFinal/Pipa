//
//  DebtSummaryCard.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 08/10/26.
//

import SwiftUI

/// One of the two big totals on the "Pendências" screen ("Você deve" / "Te devem").
struct DebtSummaryCard: View {

    /// "Você deve" or "Te devem".
    let title: String
    /// The total, split into currency, whole part and cents.
    let amount: PendingPaymentsViewModel.AmountParts
    /// Whether this card is the selected side.
    let isSelected: Bool
    /// Color and texture shown when the card is selected (the user's profile banner).
    let banner: ProfileBanner
    /// Runs when the card is tapped (selects this side).
    let onTap: () -> Void
    /// What VoiceOver reads for the card ("Você deve, 350 reais"); title and amount when `nil`.
    var accessibilityText: String? = nil

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                // MARK: - Title
                Text(title)
                    .font(.custom("Alan Sans", size: 18))
                    .fontWeight(.semibold)
                    .foregroundStyle(isSelected ? .white : .black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                // MARK: - Amount: "R$" "350" ",00"
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(amount.currency)
                        .font(.system(size: 20, weight: .semibold))

                    Text(amount.whole)
                        .font(.custom("Alan Sans", size: 30))
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)

                    Text(amount.cents)
                        .font(.system(size: 20, weight: .semibold))
                }
                .foregroundStyle(isSelected ? .white : .black)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            // MARK: - Background: a coupon, filled with the user's banner when selected and
            .background {
                ZStack {
                    if isSelected {
                        RoomTextureBackground(color: banner.color, pattern: banner.pattern, zoom: 1.5)
                    } else {
                        Color.white
                    }
                }
                .clipShape(TicketShape())
                .overlay {
                    if !isSelected {
                        TicketShape()
                            .stroke(Color.gray.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    }
                }
                .shadow(color: .black.opacity(isSelected ? 0.18 : 0.05), radius: 6, y: 3)
            }
            .contentShape(TicketShape())
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: isSelected)
        .accessibilityElement(children: .combine)
        .voiceOverLabel(accessibilityText ?? "\(title), \(amount.currency)\(amount.whole)\(amount.cents)")
        .voiceOverTraits(.isSelected, when: isSelected)
        .voiceControlNames([title])
    }
}

#Preview("Cards") {
    let viewModel = ShopListPreviewData.debtsViewModel

    HStack(spacing: 12) {
        DebtSummaryCard(
            title: viewModel.title(for: .youOwe),
            amount: viewModel.amountParts(viewModel.total(for: .youOwe)),
            isSelected: true,
            banner: viewModel.banner,
            onTap: {}
        )
        DebtSummaryCard(
            title: viewModel.title(for: .owedToYou),
            amount: viewModel.amountParts(viewModel.total(for: .owedToYou)),
            isSelected: false,
            banner: viewModel.banner,
            onTap: {}
        )
    }
    .padding()
}
