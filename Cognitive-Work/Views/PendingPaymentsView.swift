//
//  PendingPaymentsView.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 08/10/26.
//

import SwiftUI

/// "Pendências": who owes whom for the house's shopping. Rendering only; the numbers, texts and
/// settling live in ``PendingPaymentsViewModel``.
struct PendingPaymentsView: View {

    /// The debts, texts and settle actions.
    @State private var viewModel: PendingPaymentsViewModel

    /// Creates the screen with a ready view model (previews).
    init(viewModel: PendingPaymentsViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    /// Used by ``ShopListView`` to open the screen on the list it already has loaded.
    init(shopList: ShopListViewModel) {
        self._viewModel = State(initialValue: PendingPaymentsViewModel(shopList: shopList))
    }

    var body: some View {
        let groups = viewModel.groups

        // MARK: - The whole page scrolls: title, balance, totals, then the receipts
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Pendências")
                    .font(.custom("Alan Sans", size: 34))
                    .fontWeight(.bold)
                    .padding(.horizontal, 10)
                    .accessibilityAddTraits(.isHeader)

                // Balance, then "Você deve" / "Te devem"
                VStack(spacing: 16) {
                    DebtBalanceCard(
                        title: viewModel.balanceTitle,
                        caption: viewModel.balanceCaption,
                        amountText: viewModel.balanceText,
                        color: viewModel.balanceColor,
                        accessibilityAmount: viewModel.balanceAccessibilityText
                    )
                    summaryCards
                }

                // MARK: Empty state, or one receipt per housemate
                if groups.isEmpty {
                    emptyState
                        .padding(.top, 40)
                } else {
                    VStack(alignment: .leading, spacing: 28) {
                        ForEach(groups) { group in
                            section(for: group)
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                    }
                    .padding(.top, 10)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 60)
        }
        .background(Color.white.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.snappy, value: viewModel.selectedDirection)
        .animation(.snappy, value: viewModel.groups.map(\.id))
        // MARK: - "Pix copiado" toast
        .overlay(alignment: .bottom) {
            if viewModel.isPixCopied {
                pixCopiedToast
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: viewModel.isPixCopied)
        // MARK: - Alerts: missing Pix key and errors
        .alert(
            "Chave Pix não cadastrada",
            isPresented: Binding(
                get: { viewModel.missingPixKeyName != nil },
                set: { if !$0 { viewModel.missingPixKeyName = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.missingPixKeyMessage)
        }
        .alert(
            "Não foi possível concluir",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Pieces

    /// The two total cards; tapping one selects its side.
    private var summaryCards: some View {
        HStack(spacing: 12) {
            ForEach(DebtDirection.allCases) { direction in
                DebtSummaryCard(
                    title: viewModel.title(for: direction),
                    amount: viewModel.amountParts(viewModel.total(for: direction)),
                    isSelected: viewModel.selectedDirection == direction,
                    banner: viewModel.banner,
                    onTap: {
                        HapticsManager.selection()
                        viewModel.selectedDirection = direction
                    },
                    accessibilityText: viewModel.summaryAccessibilityLabel(for: direction)
                )
            }
        }
    }

    /// One housemate's section: their items, the net total and the pay/settle button.
    private func section(for group: DebtGroup) -> some View {
        DebtGroupSection(
            user: group.counterparty,
            title: viewModel.title(for: group),
            banner: group.counterparty.banner,
            totalText: viewModel.currencyText(group.total),
            rows: group.entries.map {
                .init(
                    id: $0.id,
                    name: $0.name,
                    amountText: viewModel.currencyText($0.amount),
                    accessibilityAmount: viewModel.accessibilityAmount($0.amount)
                )
            },
            settleTitle: viewModel.settleButtonTitle(for: group),
            settleSystemImage: nil,
            isPaid: viewModel.isPaid(group),
            isSettling: viewModel.isSettling,
            onSettle: { viewModel.settleTapped(for: group) },
            isConfirmingSettlement: viewModel.settlementRequest?.id == group.id,
            confirmationTitle: viewModel.confirmationTitle,
            confirmationMessage: viewModel.confirmationMessage,
            confirmationButtonTitle: viewModel.confirmationButtonTitle,
            onConfirmSettlement: { viewModel.confirmSettlementAnnouncing() },
            onCancelSettlement: { viewModel.cancelSettlement() },
            headerAccessibilityText: viewModel.headerAccessibilityLabel(for: group),
            totalAccessibilityText: viewModel.accessibilityAmount(group.total),
            settleAccessibilityLabel: viewModel.settleAccessibilityLabel(for: group),
            settleAccessibilityValue: viewModel.settleAccessibilityValue(for: group)
        )
    }

    /// Shown for a moment after "Pagar" copies the Pix "copia e cola".
    private var pixCopiedToast: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
            Text("Pix copia e cola copiado!")
        }
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Capsule().fill(Color.green))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .accessibilityElement(children: .combine)
    }

    /// Shown when the selected side has no debts.
    private var emptyState: some View {
        VStack(spacing: 10) {
            SymbolImage(name: "plastic.bag")
                .frame(width: 64, height: 64)
                .foregroundStyle(.choreYellow)
                .accessibilityHidden(true)

            Text(viewModel.emptyTitle)
                .font(.custom("Alan Sans", size: 24))
                .fontWeight(.bold)
                .foregroundStyle(.titleGray)

            Text(viewModel.emptyMessage)
                .font(.system(size: 16))
                .foregroundStyle(.subTitleGray)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Você deve") {
    NavigationStack {
        PendingPaymentsView(viewModel: ShopListPreviewData.debtsViewModel)
    }
}

#Preview("Te devem") {
    let viewModel = ShopListPreviewData.debtsViewModel
    viewModel.selectedDirection = .owedToYou

    return NavigationStack {
        PendingPaymentsView(viewModel: viewModel)
    }
}

#Preview("Sem pendências") {
    NavigationStack {
        PendingPaymentsView(viewModel: ShopListPreviewData.noDebtsViewModel)
    }
}
