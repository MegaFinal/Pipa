//
//  RetroCoinsRedeemButton.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 16/10/26.
//

import SwiftUI
import CloudKit

/// A "Resgatar moedas" button: confirms the user's pending cycle payouts and credits them to
/// their wallet (see ``CycleSettlementService``).
///
/// > Note: The retrospective no longer uses it: its coins page redeems with its own button.
///
/// The data comes from ``RetroCoinsViewModel``, which the presenting screen loads before the
/// retrospective opens. Shows nothing when there is nothing to redeem.
struct RetroCoinsRedeemButton: View {

    /// The coins to redeem and the redeem action.
    let viewModel: RetroCoinsViewModel

    var body: some View {
        VStack(spacing: 6) {
            // MARK: - Redeemed confirmation, or the redeem button
            if viewModel.didRedeem {
                Label("Moedas resgatadas", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 17))
                    .fontWeight(.semibold)
                    .foregroundStyle(.choreGreen)
            } else if viewModel.pendingAmount > 0 {
                Button {
                    Task { await viewModel.redeem() }
                } label: {
                    Group {
                        if viewModel.isWorking {
                            ProgressView()
                        } else {
                            Text("Resgatar \(viewModel.pendingAmount) moedas")
                        }
                    }
                    .frame(minWidth: width * 0.69, minHeight: height * 0.037)
                    .multilineTextAlignment(.center)
                    .fontWeight(.medium)
                    .font(.system(size: 17))
                }
                .buttonStyle(.glassProminent)
                .disabled(viewModel.isWorking)
            }

            // MARK: - Error
            if let errorText = viewModel.errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.subTitleGray)
                    .multilineTextAlignment(.center)
            }
        }
        // Normally already loaded by the presenting screen; otherwise this loads it.
        .task { await viewModel.load() }
    }
}
