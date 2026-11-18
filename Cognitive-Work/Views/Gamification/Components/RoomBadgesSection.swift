//
//  RoomBadgesSection.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 11/11/26.
//

import SwiftUI

/// The member's room badges (``RoomBadge``): one row per kind of default room the house has,
/// with its ladder of badges and how far the next one is.
struct RoomBadgesSection: View {

    /// The kinds of default room to show, in order.
    let rooms: [DefaultRoomsOnboarding]
    /// The member's progress.
    let progress: RoomBadgeProgressModel
    /// Id (``RoomBadge/id``) of the badge brought to the center of the screen, if any.
    @Binding var focusedBadgeKey: String?
    /// Lets a badge fly from its row to the center and back.
    let namespace: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(verbatim: L10n.tr("Badges dos cômodos"))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.black)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 30)

            if rooms.isEmpty {
                Text(verbatim: L10n.tr("As badges aparecem aqui quando a casa tiver cômodos como Cozinha, Sala de Estar ou Banheiro."))
                    .font(.system(size: 15))
                    .foregroundStyle(.subTitleGray)
                    .padding(.horizontal, 30)
            } else {
                ForEach(rooms) { room in
                    RoomBadgeRow(
                        room: room,
                        progress: progress,
                        focusedBadgeKey: $focusedBadgeKey,
                        namespace: namespace
                    )
                }
            }
        }
    }
}

/// One room's ladder of badges and the progress towards the next one.
private struct RoomBadgeRow: View {

    /// Width and height of each badge in the row.
    private static let iconSize: CGFloat = 84

    let room: DefaultRoomsOnboarding
    let progress: RoomBadgeProgressModel
    /// Id (``RoomBadge/id``) of the badge in focus; `nil` when none. Tapping one of this row's
    /// badges sets it, so it flies to the center (``FocusedBadgeView``).
    @Binding var focusedBadgeKey: String?
    /// Lets a badge fly from here to the center and back.
    let namespace: Namespace.ID

    private var count: Int { progress.count(for: room) }
    private var next: RoomBadge? { progress.nextBadge(in: room) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(verbatim: room.rawValue.localizedDefault)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(verbatim: next.map { "\(min(count, $0.threshold))/\($0.threshold)" } ?? L10n.tr("Completo!"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.subTitleGray)
                    .monospacedDigit()
            }

            HStack(spacing: 16) {
                ForEach(room.badges) { badge in
                    // While a badge is in focus its place stays empty, so the row doesn't jump
                    // and the badge can fly back into it (same trick as ``CouponCell``).
                    if focusedBadgeKey == badge.id {
                        Color.clear
                            .frame(width: Self.iconSize, height: Self.iconSize)
                            .accessibilityHidden(true)
                    } else {
                        Button {
                            focusBadge(badge.id, in: $focusedBadgeKey)
                        } label: {
                            RoomBadgeIcon(badge: badge, isUnlocked: progress.isUnlocked(badge), size: Self.iconSize)
                        }
                        .buttonStyle(.plain)
                        .matchedGeometryEffect(id: badge.id, in: namespace)
                    }
                }
            }

            if let next {
                ProgressView(value: Double(min(count, next.threshold)), total: Double(next.threshold))
                    .tint(room.color.uiColor)
                    .accessibilityLabel(L10n.tr("\(count) de \(next.threshold) tarefas para \(next.title)"))
            }
        }
        .padding(.horizontal, 30)
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    @Previewable @State var focusedBadgeKey: String?
    @Previewable @Namespace var namespace

    var progress = RoomBadgeProgressModel(ownerRecordName: "preview")
    progress.apply([
        RoomBadgeChange(room: .kitchen, delta: 37),
        RoomBadgeChange(room: .garage, delta: 25)
    ], dayKey: "2026-11-11")
    return ScrollView {
        RoomBadgesSection(
            rooms: [.kitchen, .powderRoom, .garage],
            progress: progress,
            focusedBadgeKey: $focusedBadgeKey,
            namespace: namespace
        )
    }
    .badgeFocus(progress: progress, focusedBadgeKey: $focusedBadgeKey, namespace: namespace)
}
