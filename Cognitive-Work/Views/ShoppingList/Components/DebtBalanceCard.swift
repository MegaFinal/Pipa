//
//  DebtBalanceCard.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 09/10/26.
//

import SwiftUI

/// The overall balance on the "Pendências" screen
struct DebtBalanceCard: View {

    /// "Saldo".
    let title: String
    /// What the balance means ("A casa te deve"…).
    let caption: String
    /// The amount, formatted as money.
    let amountText: String
    /// The amount's color (green, orange or yellow).
    let color: RoomColor
    /// The amount as VoiceOver should read it ("55 reais"); `amountText` when `nil`.
    var accessibilityAmount: String? = nil

    var body: some View {
        HStack(alignment: .center) {
            // MARK: - Title and caption
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.custom("Alan Sans", size: 24))
                    .fontWeight(.bold)
                    .foregroundStyle(.black)

                Text(caption)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.subTitleGray)
            }

            Spacer(minLength: 12)

            // MARK: - Amount
            Text(amountText)
                .font(.custom("Alan Sans", size: 38))
                .fontWeight(.bold)
                .foregroundStyle(color.uiColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .voiceOverLabel(accessibilityAmount ?? amountText)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: amountText)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Saldo") {
    VStack(spacing: 20) {
        DebtBalanceCard(title: "Saldo", caption: "A casa te deve", amountText: "+R$55,00", color: .green)
        DebtBalanceCard(title: "Saldo", caption: "Você deve à casa", amountText: "-R$30,00", color: .orange)
        DebtBalanceCard(title: "Saldo", caption: "Tudo certo por aqui", amountText: "R$0,00", color: .yellow)
    }
    .padding()
}
