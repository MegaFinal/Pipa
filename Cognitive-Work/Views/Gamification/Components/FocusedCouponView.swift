//
//  FocusedCouponView.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 20/10/26.
//

import SwiftUI

/// A coupon brought to the center of the screen, over a white background.
///
/// Pulling the ticket's stub sideways tears it off: past ``tearDistance`` the stub flies away, the
/// celebration starts right away and the coupon is bought meanwhile. If the purchase fails, the
/// celebration stops and the stub comes back. A coupon that can't be bought (already held,
/// someone else's, another one of the room already held this cycle, too expensive) only gives a
/// little and springs back.
///
/// Haptics follow the tear: a tick for every dash of the perforation pulled, a stronger one when
/// it's far enough to tear, and success when the stub comes off, with a celebration of confetti,
/// stars and sparkles all over the screen (``CouponCelebration``); an error one if the purchase
/// then fails.
///
/// The white background and closing it on a tap belong to the presenting screen
/// (``GamificationView``); this view only calls ``onClose``.
struct FocusedCouponView: View {

    /// The coupon shown.
    var coupon: CouponModel
    /// The color of the coupon's room.
    var roomColor: RoomColor
    /// The SF Symbol of the coupon's room.
    var roomSymbol: String
    /// Whether the user has enough coins to buy it.
    var isAffordable: Bool
    /// Whether it can be bought, or why not.
    var state: CouponCard.PurchaseState
    /// `true` while a purchase is being saved.
    var isBuying: Bool

    /// Shared with the ticket in the list, so it flies from there to the center and back.
    var namespace: Namespace.ID
    /// The id used to match the ticket in the list.
    var matchID: String

    /// Buys the coupon; returns whether the purchase went through.
    var onBuy: () async -> Bool
    /// Closes the focused coupon.
    var onClose: () -> Void

    /// How far down the ticket has to be pulled to tear the stub off.
    static let tearDistance: CGFloat = 110

    /// How far the finger pulled sideways (always positive).
    @State private var pull: CGFloat = 0

    /// Which way the finger pulled: 1 to the right, -1 to the left.
    @State private var pullDirection: CGFloat = 1

    /// The stub came off and the purchase is running (or done).
    @State private var isTorn = false

    /// Purchases that finished, so the outcome is handled on the next render.
    @State private var finishedAttempts = 0

    /// Outcome of the last purchase.
    @State private var lastPurchaseSucceeded = false

    /// The stub came off: confetti and the success message show while the purchase is saved.
    @State private var isCelebrating = false

    /// When the celebration started, so closing waits for it to play out.
    @State private var celebrationStart = Date.now

    /// Purchases that failed, for the error haptic.
    @State private var failedAttempts = 0

    /// The ticket's frame on screen, where the celebration bursts from.
    @State private var ticketFrame: CGRect = .zero

    /// Turns off the confetti and big movements when the user asked for less motion.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Whether the coupon can be torn right now.
    private var canBuy: Bool {
        state == .available && isAffordable && !isBuying
    }

    /// Whether the pull is far enough to tear the stub off.
    private var isPastTearPoint: Bool {
        canBuy && pull >= Self.tearDistance
    }

    /// How many dashes of the perforation (``CouponTicket/perforationDashCount``) the pull went
    /// through: the whole line is torn at ``tearDistance``, one tick per dash. Stops one short of
    /// the last dash, which is the stronger "far enough" tap (``isPastTearPoint``).
    private var tearStep: Int {
        guard canBuy, !isTorn else { return 0 }
        let dashes = CouponTicket.perforationDashCount(width: max(ticketFrame.width, 1))
        let perDash = Self.tearDistance / CGFloat(dashes)
        return min(Int(pull / perDash), dashes - 1)
    }

    var body: some View {
        ZStack {
            // MARK: - Ticket and hint
            content

            // MARK: - Back button
            backButton

            // MARK: - Celebration
            // Confetti, stars and sparkles all over the screen once it's bought.
            if isCelebrating && !reduceMotion {
                CouponCelebration(
                    colors: celebrationColors,
                    burstCenter: CGPoint(x: ticketFrame.midX, y: ticketFrame.midY)
                )
                .ignoresSafeArea()
            }
        }
        // MARK: - Accessibility and haptics
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { if !isTorn { onClose() } }
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.8), trigger: tearStep) { old, new in new > old }
        .sensoryFeedback(.impact(weight: .heavy, intensity: 0.9), trigger: isPastTearPoint) { _, isPast in isPast }
        .sensoryFeedback(.success, trigger: isCelebrating) { _, celebrating in celebrating }
        .sensoryFeedback(.error, trigger: failedAttempts)
        .onChange(of: finishedAttempts) { resolvePurchase() }
    }

    /// The round glass button at the top that brings the ticket back to the list.
    private var backButton: some View {
        VStack {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .voiceOverLabel(L10n.tr("Fechar"))
                Spacer()
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .opacity(isTorn ? 0 : 1)
        .disabled(isTorn)
    }

    /// The ticket (with the tear gesture) and the hint under it.
    private var content: some View {
        VStack(spacing: 28) {
            CouponTicket(
                coupon: coupon,
                roomColor: roomColor,
                roomSymbol: roomSymbol,
                isAffordable: isAffordable,
                state: state,
                isBuying: isBuying && !isTorn,
                metrics: .focused,
                stubOffset: stubOffset,
                stubRotation: stubRotation
            )
            .matchedGeometryEffect(id: matchID, in: namespace)
            // A little pop when the purchase goes through.
            .scaleEffect(isCelebrating && !reduceMotion ? 1.05 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.45), value: isCelebrating)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { ticketFrame = $0 }
            .contentShape(Rectangle())
            .gesture(tearGesture)
            .accessibilityElement(children: .ignore)
            .voiceOverLabel(CouponTicket.accessibilityText(coupon: coupon, state: state, isAffordable: isAffordable))
            .accessibilityActions {
                if canBuy && !isTorn {
                    Button(L10n.tr("Comprar")) { tear() }
                }
            }

            hint
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
    }

    /// The room's color first, then the rest of the palette.
    private var celebrationColors: [Color] {
        [roomColor.uiColor, roomColor.uiColor, .choreYellow, .choreOrange, .choreGreen, .choreBlue, .chorePurple]
    }

    // MARK: - Tearing

    /// Where the stub is: following the finger, or flown off once torn.
    private var stubOffset: CGSize {
        if isTorn { return CGSize(width: pullDirection * 600, height: 90) }
        return CGSize(width: pull * pullDirection, height: pull * 0.06)
    }

    /// How much the stub tilts while pulled (none with reduced motion).
    private var stubRotation: Angle {
        guard !reduceMotion else { return .zero }
        if isTorn { return .degrees(pullDirection * 30) }
        return .degrees(pullDirection * min(pull / Self.tearDistance * 14, 20))
    }

    /// Pulls the stub sideways; tears it if released past ``tearDistance``, otherwise springs back.
    private var tearGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !isTorn else { return }
                let sideways = abs(value.translation.width)
                if value.translation.width != 0 { pullDirection = value.translation.width > 0 ? 1 : -1 }
                // Can't be bought: it only gives a little, so it's clear it won't tear.
                pull = canBuy ? sideways : min(sideways * 0.25, 24)
            }
            .onEnded { _ in
                guard !isTorn else { return }
                if isPastTearPoint {
                    tear()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) { pull = 0 }
                }
            }
    }

    /// Tears the stub off, starts the celebration and buys the coupon.
    private func tear() {
        guard canBuy else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeIn(duration: 0.4)) {
            isTorn = true
        }
        // Celebrates at once instead of waiting for CloudKit; undone if the purchase fails.
        celebrationStart = .now
        isCelebrating = true
        Task {
            lastPurchaseSucceeded = await onBuy()
            finishedAttempts += 1
        }
    }

    /// Closes once the celebration played out on success; otherwise stops it and puts the stub
    /// back (the reason is shown by the rewards tab's alert).
    private func resolvePurchase() {
        if lastPurchaseSucceeded {
            let elapsed = Date.now.timeIntervalSince(celebrationStart)
            let remaining = max(CouponCelebration.duration - 0.4 - elapsed, 0.3)
            Task {
                try? await Task.sleep(for: .seconds(remaining))
                onClose()
            }
        } else {
            failedAttempts += 1
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                isCelebrating = false
                isTorn = false
                pull = 0
            }
        }
    }

    // MARK: - Hint

    /// The text under the ticket: the success message, or why it can't be bought, or how to buy it.
    @ViewBuilder
    private var hint: some View {
        Group {
            if isCelebrating {
                VStack(spacing: 10) {
                    Image(systemName: "party.popper.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(roomColor.uiColor)
                        .symbolEffect(.bounce, options: .repeat(2), isActive: !reduceMotion)
                        .accessibilityHidden(true)
                    Text(verbatim: L10n.tr("Cupom comprado!"))
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(.titleGray)
                    Text(verbatim: L10n.tr("Você está livre dessa tarefa na próxima divisão."))
                }
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else {
                switch state {
                case .ownedByMe:
                    Text(verbatim: L10n.tr("Esse cupom já é seu neste ciclo."))
                case .taken:
                    Text(verbatim: L10n.tr("Alguém já comprou esse cupom neste ciclo."))
                case .roomLimitReached:
                    Text(verbatim: L10n.tr("Você já tem um cupom desse cômodo neste ciclo."))
                case .available where !isAffordable:
                    Text(verbatim: L10n.tr("Moedas insuficientes"))
                case .available:
                    VStack(spacing: 6) {
                        Text(verbatim: L10n.tr("Destaque o ticket para comprá-lo"))
                    }
                }
            }
        }
        .font(.system(size: 28, weight: .semibold))
        .foregroundStyle(.subTitleGray)
        .multilineTextAlignment(.center)
        .contentTransition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: isTorn)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isCelebrating)
    }
}
