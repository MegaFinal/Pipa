//
//  CouponGridView.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 27/10/26.
//

import SwiftUI

/// Every coupon of one of the rewards tab's lists ("Cupons disponíveis" or "Seus cupons"), in a
/// grid of two columns. Tapping a ticket brings it to the center of the screen, like in the tab.
struct CouponGridView: View {

    /// Which list the grid shows.
    enum Source {
        /// Coupons anyone can still buy in this cycle.
        case available
        /// Coupons the member holds in this cycle.
        case mine
    }

    /// The title in the navigation bar.
    let title: String
    /// The list shown.
    let source: Source
    /// Gives the coupons and buys them.
    let viewModel: GamificationViewModel

    /// Id of the coupon brought to the center of the screen, if any.
    @State private var focusedKey: String?

    /// Lets a ticket fly from the grid to the center and back.
    @Namespace private var ticketNamespace

    private var entries: [CouponEntry] {
        source == .available ? viewModel.availableEntries : viewModel.myEntries
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())],
                spacing: 20
            ) {
                ForEach(entries) { entry in
                    CouponCell(
                        entry: entry,
                        viewModel: viewModel,
                        focusedKey: focusedKey,
                        namespace: ticketNamespace,
                        onSelect: { focusCoupon($0, in: $focusedKey) }
                    )
                }
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 16)
        }
        .background(Color.white.ignoresSafeArea())
        .overlay {
            if entries.isEmpty {
                CouponEmptyState(
                    title: source == .available ? "Nenhum cupom disponível" : "Você ainda não tem cupons",
                    message: source == .available
                        ? "Quando houver cupons à venda, eles aparecem aqui."
                        : "Os cupons que você comprar neste ciclo aparecem aqui."
                )
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(focusedKey == nil ? .automatic : .hidden, for: .navigationBar)
        .couponFocus(
            viewModel: viewModel,
            entries: viewModel.catalog.entries,
            focusedKey: $focusedKey,
            namespace: ticketNamespace
        )
    }
}

/// The mascot over the soft yellow disc, like ``ChoresEmptyState``.
struct CouponEmptyState: View {

    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(RoomColor.yellow.lowOpacityColor.opacity(0.3))

                Image("loadingIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96)
            }
            .frame(width: 150, height: 150)
            .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.titleGray)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.system(size: 16))
                    .foregroundStyle(.subTitleGray)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
