//
//  CouponFocus.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 27/10/26.
//

import SwiftUI

/// One coupon in a list or grid of the rewards tab. While the coupon is in focus its place stays
/// empty, so the list doesn't jump and the ticket can fly back into it.
struct CouponCell: View {

    /// The coupon shown.
    let entry: CouponEntry
    /// Gives the coupon's state, whether it is affordable and whether it is being bought.
    let viewModel: GamificationViewModel
    /// Id (``CouponEntry/id``) of the coupon in focus, if any.
    let focusedKey: String?
    /// Lets the ticket fly from here to the center of the screen and back.
    let namespace: Namespace.ID
    /// Sizes of the ticket's texts and symbol.
    var metrics: CouponTicket.Metrics = .card
    /// Called with the coupon's id when it is tapped.
    let onSelect: (String) -> Void

    var body: some View {
        if focusedKey == entry.id {
            Color.clear
                .aspectRatio(CouponTicket.aspectRatio, contentMode: .fit)
                .accessibilityHidden(true)
        } else {
            VStack(spacing: 10) {
                CouponCard(
                    coupon: entry.coupon,
                    roomColor: entry.color,
                    roomSymbol: entry.symbol,
                    isAffordable: viewModel.canAfford(entry.coupon),
                    state: viewModel.state(of: entry),
                    isBuying: viewModel.buyingCouponName == entry.id,
                    metrics: metrics,
                    onSelect: { onSelect(entry.id) }
                )
                .matchedGeometryEffect(id: entry.id, in: namespace)
                
                HStack {
                    Text("\(entry.coupon.price)")
                        .font(.system(size: 20))
                        .fontWeight(.bold)
                        .foregroundColor(entry.color.uiColor)
                    TintedCoinPig(color: entry.color.uiColor)
                        .frame(width: width * 0.06)
                }
                .padding(.horizontal, 35)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .foregroundColor(entry.color.uiColor.opacity(0.2))
                )
            }
        }
    }
}

/// Brings the coupon with this id to the center of the screen, animated.
func focusCoupon(_ key: String, in focusedKey: Binding<String?>) {
    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
        focusedKey.wrappedValue = key
    }
}

extension View {

    /// Lets the screen bring a coupon to its center, where it can be bought
    /// (``FocusedCouponView``).
    ///
    /// - Parameters:
    ///   - viewModel: Buys the coupon and gives its state.
    ///   - entries: Every coupon that may be focused. It has to keep the coupon after it was
    ///     bought, since the purchase moves it from one list to another while it is still on screen.
    ///   - focusedKey: Id (``CouponEntry/id``) of the coupon in focus; `nil` when none.
    ///   - namespace: The namespace the ``CouponCell``s of the screen use.
    func couponFocus(
        viewModel: GamificationViewModel,
        entries: [CouponEntry],
        focusedKey: Binding<String?>,
        namespace: Namespace.ID
    ) -> some View {
        modifier(CouponFocusModifier(viewModel: viewModel, entries: entries, focusedKey: focusedKey, namespace: namespace))
    }
}

private struct CouponFocusModifier: ViewModifier {

    let viewModel: GamificationViewModel
    let entries: [CouponEntry]
    @Binding var focusedKey: String?
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        content
            // The focused coupon takes the whole screen.
            .toolbar(focusedKey == nil ? .automatic : .hidden, for: .tabBar)
            .overlay { overlay }
    }

    /// The chosen coupon at the center, over a white background. Tapping outside it closes it.
    @ViewBuilder
    private var overlay: some View {
        if let key = focusedKey, let entry = entries.first(where: { $0.id == key }) {
            ZStack {
                Color.white
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: close)
                    .accessibilityHidden(true)
                    .transition(.opacity)

                FocusedCouponView(
                    coupon: entry.coupon,
                    roomColor: entry.color,
                    roomSymbol: entry.symbol,
                    isAffordable: viewModel.canAfford(entry.coupon),
                    state: viewModel.state(of: entry),
                    isBuying: viewModel.buyingCouponName == key,
                    namespace: namespace,
                    matchID: key,
                    onBuy: { await viewModel.buy(entry.coupon) },
                    onClose: close
                )
            }
        }
    }

    /// Sends the focused coupon back to the list.
    private func close() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            focusedKey = nil
        }
    }
}
