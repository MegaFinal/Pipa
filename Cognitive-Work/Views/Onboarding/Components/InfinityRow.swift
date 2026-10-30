//
//  InfinityRow.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 02/10/26.
//

import SwiftUI
import Foundation

/// A vertical column of chore cards that scrolls forever.
///
/// The cards are repeated three times and the column is shifted based on the current time.
/// Once the shift reaches the height of one full set of cards (``cycleHeight``), it wraps
/// back to zero. Since the copies are identical, the jump can't be noticed, creating
/// a seamless loop.
///
/// The animation pauses when the user turns on Reduce Motion.
struct InfinityRow: View {
    /// The chores shown in the column, in order.
    let cards: [ChoreDTO]
    
    /// Whether the column scrolls up (`true`) or down (`false`).
    let movesUp: Bool
    
    /// Scrolling speed, in points per second.
    var speed: Double = 18
    
    /// Initial offset, in points, so columns moving the same way don't line up.
    var phase: Double = 0
    
    /// Height of each card.
    let cardHeight: CGFloat = 170
    
    /// Vertical space between cards.
    let spacing: CGFloat = 16

    /// Whether the user turned on Reduce Motion (pauses the scrolling).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool

    var body: some View {
        /// Height of one full set of cards: the distance traveled before the loop restarts.
        let cycleHeight = Double(cards.count) * Double(cardHeight + spacing)

        // MARK: - Time-driven scrolling column of repeated cards
        TimelineView(.animation(paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            
            // Distance traveled so far, wrapped to stay between 0 and `cycleHeight`
            let offset = CGFloat(fmod(time * speed + phase, cycleHeight))

            VStack(spacing: spacing) {
                // 3 copies, so the screen stays covered during the whole loop
                ForEach(0..<cards.count * 3, id: \.self) { index in
                    OnboardingChoreCard(chore: cards[index % cards.count])
                        .frame(height: cardHeight)
                }
            }
            .offset(y: movesUp ? -offset : offset - CGFloat(cycleHeight))
        }
        // Looping decoration: VoiceOver skips it (screens describe it with their own text).
        .accessibilityDecorative()
    }
}
