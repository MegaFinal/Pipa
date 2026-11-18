//
//  FocusedBadgeView.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 17/11/26.
//

import SwiftUI

/// A room badge (``RoomBadge``) brought to the center of the screen, highlighted, the way a
/// coupon is in ``FocusedCouponView``.
///
/// Dragging a finger across the badge gives it a light spin, like flicking a coin; it springs
/// back to facing forward once released.
struct FocusedBadgeView: View {

    /// The badge shown.
    let badge: RoomBadge
    /// Whether the member has it.
    let isUnlocked: Bool
    /// Chores checked off in rooms of the badge's kind so far.
    let count: Int

    /// Shared with the icon in its row, so it flies from there to the center and back.
    let namespace: Namespace.ID
    /// The id used to match the icon in the row.
    let matchID: String

    /// Whether the badge is pinned to the profile and how to change it.
    struct Pin {
        /// Whether the badge is pinned now.
        let isPinned: Bool
        /// Whether another badge can still be pinned (``RoomBadgeProgressModel/maxPinned``).
        let canPin: Bool
        /// Pins the badge, or unpins it.
        let toggle: () -> Void
    }

    /// The pin button's state; `nil` hides the button.
    var pin: Pin? = nil

    /// Closes the focused badge.
    let onClose: () -> Void

    /// How far the spin follows the finger, in degrees per point dragged, before clamping.
    private static let spinSensitivity: Double = 0.6

    /// The most the badge tilts, however far the finger drags.
    private static let maxSpin: Double = 20

    /// How far the badge is tilted right now (0 to ``maxSpin``); springs back to 0 once released.
    @State private var spinAngle: Double = 0
    /// The axis the tilt turns around: always perpendicular to the drag, like spinning a
    /// trackball, so the tilt reaches the same ``maxSpin`` whichever way the finger goes.
    @State private var spinAxis: (x: CGFloat, y: CGFloat, z: CGFloat) = (0, 1, 0)

    /// Turns off the spin for users who asked for less motion.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            content
            backButton
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { onClose() }
    }

    /// The badge, its title and its status.
    private var content: some View {
        VStack(spacing: 20) {
            RoomBadgeIcon(badge: badge, isUnlocked: isUnlocked, size: 220)
                .matchedGeometryEffect(id: matchID, in: namespace)
                .rotation3DEffect(.degrees(reduceMotion ? 0 : spinAngle), axis: spinAxis)
                .contentShape(Rectangle())
                .gesture(spinGesture)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(isUnlocked ? badge.title : L10n.tr("\(badge.title), bloqueada"))

            VStack(spacing: 6) {
                Text(verbatim: badge.title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.titleGray)
                    .multilineTextAlignment(.center)

                Text(verbatim: statusText)
                    .font(.system(size: 16))
                    .foregroundStyle(.subTitleGray)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            if let pin {
                pinButton(pin)
            }
        }
    }

    /// "Fixar no perfil" or "Desafixar do perfil". Disabled, with the reason below, once the
    /// member already pinned ``RoomBadgeProgressModel/maxPinned`` other badges.
    private func pinButton(_ pin: Pin) -> some View {
        VStack(spacing: 8) {
            Button(action: pin.toggle) {
                Label(
                    pin.isPinned ? L10n.tr("Desafixar do perfil") : L10n.tr("Fixar no perfil"),
                    systemImage: pin.isPinned ? "pin.slash.fill" : "pin.fill"
                )
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .buttonStyle(.glass)
            .disabled(!pin.isPinned && !pin.canPin)
            .sensoryFeedback(.selection, trigger: pin.isPinned)
            .voiceControlNames(pin.isPinned
                ? [L10n.tr("Desafixar do perfil"), L10n.tr("Desafixar")]
                : [L10n.tr("Fixar no perfil"), L10n.tr("Fixar")])

            if !pin.isPinned && !pin.canPin {
                Text(verbatim: L10n.tr("Você já fixou \(RoomBadgeProgressModel.maxPinned) badges. Desafixe uma para fixar esta."))
                    .font(.system(size: 13))
                    .foregroundStyle(.subTitleGray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .padding(.top, 8)
    }

    /// "Desbloqueada" once unlocked, otherwise how far the room's count is from the threshold.
    private var statusText: String {
        isUnlocked
            ? L10n.tr("Desbloqueada")
            : L10n.tr("\(min(count, badge.threshold))/\(badge.threshold) tarefas em \(badge.room.rawValue.localizedDefault)")
    }

    /// The round glass button at the top that brings the badge back to its row.
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
    }

    /// Tilts the badge like a trackball: around an axis perpendicular to the drag, so it leans
    /// away from wherever the finger slides, the same ``maxSpin`` in every direction. Springs
    /// back once released.
    private var spinGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard !reduceMotion else { return }
                let dx = Double(value.translation.width)
                let dy = Double(value.translation.height)
                let distance = (dx * dx + dy * dy).squareRoot()
                guard distance > 0 else { return }

                spinAngle = min(distance * Self.spinSensitivity, Self.maxSpin)
                // Perpendicular to the drag: sideways drags lean around the vertical axis,
                // vertical drags around the horizontal one, and anything between blends the two.
                spinAxis = (x: CGFloat(dy / distance), y: CGFloat(dx / distance), z: 0)
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) {
                    spinAngle = 0
                }
            }
    }
}

#Preview {
    @Previewable @Namespace var namespace
    FocusedBadgeView(
        badge: .torreDeLouca,
        isUnlocked: true,
        count: 25,
        namespace: namespace,
        matchID: RoomBadge.torreDeLouca.id,
        pin: FocusedBadgeView.Pin(isPinned: false, canPin: true, toggle: {}),
        onClose: {}
    )
}
