//
//  MyBadgesRow.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 18/11/26.
//

import SwiftUI

/// The "Minhas Badges" row of the profile: the badges the member pinned (in the focused badge,
/// ``FocusedBadgeView``), in the order they were pinned. Tapping one brings it to the center of
/// the screen, like on the rewards tab.
///
/// Use it inside a `List`, under a view with ``badgeFocus(progress:focusedBadgeKey:namespace:onTogglePin:)``.
struct MyBadgesRow: View {

    let viewModel: MyBadgesViewModel
    /// Id (``RoomBadge/id``) of the badge in focus; `nil` when none.
    @Binding var focusedBadgeKey: String?
    /// Lets a badge fly from the row to the center and back.
    let namespace: Namespace.ID

    /// Width and height of each badge. The ``RoomBadgeProgressModel/maxPinned`` (3) badges fit
    /// on one line at this size, even on smaller iPhones.
    private static let iconSize: CGFloat = 88
    /// Space between badges, across and down.
    private static let spacing: CGFloat = 14
    /// The most badges on one line.
    private static let perLine = RoomBadgeProgressModel.maxPinned

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Minhas Badges")

            if viewModel.hasLoaded {
                badges
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var badges: some View {
        let pinned = viewModel.pinnedBadges
        if pinned.isEmpty {
            Text(verbatim: L10n.tr("Toque numa badge na aba Gamificação e fixe-a para ela aparecer aqui."))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        } else {
            // Lines of up to ``perLine`` badges, each centered, so a short last line sits in the middle.
            VStack(spacing: Self.spacing) {
                ForEach(Array(stride(from: 0, to: pinned.count, by: Self.perLine)), id: \.self) { start in
                    HStack(spacing: Self.spacing) {
                        ForEach(pinned[start..<min(start + Self.perLine, pinned.count)]) { badge in
                            cell(for: badge)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// One pinned badge, or an empty space of its size while it is in focus.
    @ViewBuilder
    private func cell(for badge: RoomBadge) -> some View {
        // While a badge is in focus its place stays empty, so the row doesn't jump and the badge
        // can fly back into it (same trick as ``RoomBadgesSection``).
        if focusedBadgeKey == badge.id {
            Color.clear
                .frame(width: Self.iconSize, height: Self.iconSize)
                .accessibilityHidden(true)
        } else {
            Button {
                focusBadge(badge.id, in: $focusedBadgeKey)
            } label: {
                RoomBadgeIcon(
                    badge: badge,
                    isUnlocked: viewModel.progress.isUnlocked(badge),
                    size: Self.iconSize
                )
            }
            // Plain, so each badge is its own tap target instead of the whole row.
            .buttonStyle(.plain)
            .matchedGeometryEffect(id: badge.id, in: namespace)
        }
    }
}

#Preview {
    @Previewable @State var focusedBadgeKey: String?
    @Previewable @Namespace var namespace

    var progress = RoomBadgeProgressModel(ownerRecordName: "preview")
    progress.apply([RoomBadgeChange(room: .kitchen, delta: 37)], dayKey: "2026-11-18")
    progress.setPinned(.torreDeLouca, true)
    progress.setPinned(.panoDePratoDaVo, true)
    return NavigationStack {
        List {
            Section {
                MyBadgesRow(
                    viewModel: MyBadgesViewModel(previewProgress: progress, rooms: [.kitchen]),
                    focusedBadgeKey: $focusedBadgeKey,
                    namespace: namespace
                )
            }
        }
        .badgeFocus(progress: progress, focusedBadgeKey: $focusedBadgeKey, namespace: namespace)
    }
}
