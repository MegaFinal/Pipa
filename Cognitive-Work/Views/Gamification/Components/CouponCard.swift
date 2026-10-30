//
//  CouponCard.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 15/10/26.
//

import SwiftUI

/// One coupon in the rewards tab: a vertical ticket.
struct CouponCard: View {
    var coupon: CouponModel
    var roomColor: RoomColor
    var roomSymbol: String = "house"
    var isAffordable: Bool
    var state: PurchaseState = .available
    var isBuying: Bool = false

    /// Sizes of the ticket's texts and symbol, fixed by the caller.
    var metrics: CouponTicket.Metrics = .card
    /// Called when the ticket is tapped.
    var onSelect: () -> Void = {}

    /// Whether a coupon can be bought by the user, or why not.
    enum PurchaseState: Equatable {
        case available
        case ownedByMe
        case taken
        case roomLimitReached
    }

    var body: some View {
        Button(action: onSelect) {
            CouponTicket(
                coupon: coupon,
                roomColor: roomColor,
                roomSymbol: roomSymbol,
                isAffordable: isAffordable,
                state: state,
                isBuying: isBuying,
                metrics: metrics
            )
        }
        .buttonStyle(.plain)
        .voiceOverLabel(CouponTicket.accessibilityText(coupon: coupon, state: state, isAffordable: isAffordable))
        .accessibilityHint(Text(verbatim: L10n.tr("Abre o cupom em destaque")))
    }
}

// MARK: - Ticket

/// A coupon drawn as a vertical ticket
struct CouponTicket: View {

    var coupon: CouponModel
    var roomColor: RoomColor
    var roomSymbol: String
    var isAffordable: Bool
    var state: CouponCard.PurchaseState
    var isBuying: Bool = false

    /// Sizes of the texts and the symbol
    var metrics: Metrics = .card

    /// The fixed sizes of what is written and drawn on a ticket.
    struct Metrics {
        /// Font size of the coupon's name.
        var titleSize: CGFloat
        /// Font size of "Desbloqueie em".
        var captionSize: CGFloat
        /// Font size of the rank's name.
        var tierSize: CGFloat
        /// Size of the room's symbol.
        var symbolSize: CGSize

        /// For the tickets in the lists and the grid.
        static let card = Metrics(titleSize: 22, captionSize: 12, tierSize: 14, symbolSize: CGSize(width: 90, height: 80))

        /// For the ticket in focus.
        static let focused = Metrics(titleSize: 51, captionSize: 26, tierSize: 30, symbolSize: CGSize(width: 250, height: 210))
    }

    var stubOffset: CGSize = .zero
    var stubRotation: Angle = .zero

    static let designWidth: CGFloat = 345
    static let aspectRatio: CGFloat = 345.0 / 510.0
    static let stubFraction: CGFloat = 0.235
    static let cornerRadius: CGFloat = 20
    static let notchRadius: CGFloat = 16

    static let perforationDash: [CGFloat] = [12, 8]
    private static let perforationInset: CGFloat = 4

    /// How many dashes the perforation has, between the two notches, for a ticket `width` wide.
    static func perforationDashCount(width: CGFloat) -> Int {
        let length = width - 2 * (notchRadius + perforationInset) * (width / designWidth)
        let period = perforationDash.reduce(0, +) * (width / designWidth)
        return max(Int((length / period).rounded(.up)), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / Self.designWidth
            let stubHeight = proxy.size.height * Self.stubFraction
            let corner = Self.cornerRadius * scale
            let notch = Self.notchRadius * scale

            VStack(spacing: 0) {
                // MARK: - Main part with the perforation
                mainSection(scale: scale)
                    .frame(width: proxy.size.width, height: proxy.size.height - stubHeight)
                    .background {
                        VerticalTicketPartShape(topRadius: corner, bottomRadius: notch)
                            .fill(roomColor.uiColor)
                    }
                    .overlay(alignment: .bottom) {
                        Perforation()
                            .stroke(.white, style: StrokeStyle(
                                lineWidth: 2 * scale,
                                dash: Self.perforationDash.map { $0 * scale }
                            ))
                            .frame(height: 1.5 * scale)
                            .padding(.horizontal, notch + Self.perforationInset * scale)
                    }

                // MARK: - Stub (can be pulled away)
                stub(scale: scale)
                    .frame(width: proxy.size.width, height: stubHeight)
                    .background {
                        VerticalTicketPartShape(topRadius: notch, bottomRadius: corner)
                            .fill(roomColor.uiColor)
                    }
                    .rotationEffect(stubRotation, anchor: .topLeading)
                    .offset(stubOffset)
            }
            // MARK: - Shadow and dimming
            .foregroundStyle(.white)
            .compositingGroup()
            .shadow(color: .black.opacity(0.18), radius: 10 * scale, x: 0, y: 5 * scale)
            .saturation(state == .taken ? 0.2 : 1)
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
    }

    // MARK: - Parts

    /// Above the perforation: the coupon's name and the room's symbol.
    private func mainSection(scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            Text(verbatim: coupon.name)
                .font(.custom("Alan Sans", size: metrics.titleSize))
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8 * scale)

            SymbolImage(name: roomSymbol)
                .frame(width: metrics.symbolSize.width, height: metrics.symbolSize.height)
                .accessibilityHidden(true)

            Spacer(minLength: 8 * scale)
        }
        .padding(.horizontal, 24 * scale)
        .padding(.top, 36 * scale)
        .padding(.bottom, 28 * scale)
    }

    /// Below the perforation: the rank that unlocks the coupon.
    private func stub(scale: CGFloat) -> some View {
        VStack(spacing: 2 * scale) {
            Text(verbatim: L10n.tr("Desbloqueie em"))
                .font(.system(size: metrics.captionSize))
            Text(verbatim: coupon.tier.displayName)
                .font(.system(size: metrics.tierSize, weight: .bold))
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 24 * scale)
        .padding(.top, 12 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if isBuying {
                ProgressView().tint(.white)
            }
        }
    }

    // MARK: - Texts

    /// The text for a coupon that isn't for sale ("Seu cupom", "Já comprado", ...), or `nil` when it is.
    static func stateText(_ state: CouponCard.PurchaseState) -> String? {
        switch state {
        case .available: return nil
        case .ownedByMe: return L10n.tr("Seu cupom")
        case .taken: return L10n.tr("Já comprado")
        case .roomLimitReached: return L10n.tr("Limite do cômodo")
        }
    }

    /// The price as text: "1 moeda" or "N moedas".
    static func priceText(_ coupon: CouponModel) -> String {
        coupon.price == 1 ? L10n.tr("1 moeda") : L10n.tr("\(coupon.price) moedas")
    }

    /// The whole ticket as one VoiceOver sentence: name, rank, price and state.
    static func accessibilityText(coupon: CouponModel, state: CouponCard.PurchaseState, isAffordable: Bool) -> String {
        [coupon.name, L10n.tr("Desbloqueie em"), coupon.tier.displayName, priceText(coupon), stateText(state),
         state == .available && !isAffordable ? L10n.tr("Moedas insuficientes") : nil]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

// MARK: - Shapes

/// One part of a vertical ticket: a rectangle with a round bite out of each corner
struct VerticalTicketPartShape: Shape {

    var topRadius: CGFloat
    var bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var cutouts = Path()
        for corner in [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY)] {
            cutouts.addEllipse(in: Self.circle(at: corner, radius: topRadius))
        }
        for corner in [CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)] {
            cutouts.addEllipse(in: Self.circle(at: corner, radius: bottomRadius))
        }
        return Path(rect).subtracting(cutouts)
    }

    /// A square around a circle of `radius` centered at `center`.
    private static func circle(at center: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}

/// The horizontal line of the perforation, stroked dashed by the caller.
private struct Perforation: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

#Preview {
    // The default rooms' own color and symbol, as the app gives them to their coupons.
    let kitchen = DefaultRoomsOnboarding.kitchen
    let bedroom = DefaultRoomsOnboarding.bedroom
    HStack(spacing: 16) {
        CouponCard(
            coupon: CouponModel(name: "Arrumar a cama", isOnSale: true, price: 20, tier: .aprendiz),
            roomColor: bedroom.color,
            roomSymbol: bedroom.symbol,
            isAffordable: true
        )
        CouponTicket(
            coupon: CouponModel(name: "Lavar a louça", isOnSale: true, price: 120, tier: .almaDaCasa),
            roomColor: kitchen.color,
            roomSymbol: kitchen.symbol,
            isAffordable: true,
            state: .available,
            stubOffset: CGSize(width: 24, height: 6),
            stubRotation: .degrees(8)
        )
    }
    .padding(30)
}
