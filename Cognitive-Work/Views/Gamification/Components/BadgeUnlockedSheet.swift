//
//  BadgeUnlockedSheet.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 11/11/26.
//

import SwiftUI

/// Celebrates the room badges (``RoomBadge``) the member just unlocked by checking chores off.
struct BadgeUnlockedSheet: View {

    /// The badges just unlocked, in the order of their room's ladder.
    let badges: [RoomBadge]
    /// Closes the sheet.
    var onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 24) {
            Text(verbatim: badges.count == 1 ? L10n.tr("Badge desbloqueada!") : L10n.tr("Badges desbloqueadas!"))
                .font(.system(size: 24, weight: .bold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(badges) { badge in
                        VStack(spacing: 10) {
                            RoomBadgeIcon(badge: badge, size: badges.count == 1 ? 140 : 100)
                            Text(verbatim: badge.title)
                                .font(.system(size: 17, weight: .semibold))
                                .multilineTextAlignment(.center)
                            Text(verbatim: badge.room.rawValue.localizedDefault)
                                .font(.system(size: 15))
                                .foregroundStyle(.subTitleGray)
                        }
                        .frame(maxWidth: 180)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, 24)
                .frame(minWidth: 0, maxWidth: .infinity)
            }

            Button(action: onClose) {
                Text(verbatim: L10n.tr("Oba!"))
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 32)
        .overlay {
            if !reduceMotion {
                CouponCelebration(colors: celebrationColors)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }
        }
    }

    /// The rooms' colors first, then the rest of the palette.
    private var celebrationColors: [Color] {
        badges.map { $0.room.color.uiColor } + [.choreYellow, .choreOrange, .choreGreen, .choreBlue, .chorePurple]
    }
}

#Preview {
    BadgeUnlockedSheet(badges: [.torreDeLouca]) {}
}
