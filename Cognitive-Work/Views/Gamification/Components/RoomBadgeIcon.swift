//
//  RoomBadgeIcon.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 11/11/26.
//

import SwiftUI

/// The artwork of a room badge (``RoomBadge``): in color once unlocked, faded with a lock while
/// locked.
///
/// Badges without artwork in the asset catalog yet show their room's icon on the room's color.
struct RoomBadgeIcon: View {

    /// The badge to draw.
    let badge: RoomBadge
    /// Whether the member has it.
    var isUnlocked: Bool = true
    /// Width and height of the icon.
    var size: CGFloat = 64

    var body: some View {
        artwork
            .frame(width: size, height: size)
            .saturation(isUnlocked ? 1 : 0)
            .opacity(isUnlocked ? 1 : 0.4)
            .overlay(alignment: .bottomTrailing) {
                if !isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: size * 0.2, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(size * 0.08)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                isUnlocked
                ? badge.title
                : L10n.tr("\(badge.title), bloqueada")
            )
    }

    @ViewBuilder
    private var artwork: some View {
        if UIImage(named: badge.imageName) != nil {
            Image(badge.imageName)
                .resizable()
                .scaledToFit()
        } else {
            ZStack {
                Circle()
                    .fill(badge.room.color.uiColor)
                SymbolImage(name: badge.room.symbol)
                    .foregroundStyle(.white)
                    .padding(size * 0.24)
            }
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        RoomBadgeIcon(badge: .torreDeLouca)
        RoomBadgeIcon(badge: .panoDePratoDaVo, isUnlocked: false)
        RoomBadgeIcon(badge: .saboneteDeEnfeite, size: 88)
    }
    .padding()
}
