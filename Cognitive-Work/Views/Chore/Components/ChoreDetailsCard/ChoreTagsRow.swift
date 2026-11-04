//
//  ChoreTagsRow.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 16/10/26.
//

import SwiftUI

/// The chore's frequency, priority and duration tags, always in this order.
struct ChoreTagsRow: View {
    /// The chore whose tags are shown.
    let chore: ChoreModel
    /// Space between the tags.
    var spacing: CGFloat = 8
    /// Space on the left and right of each tag's text.
    var horizontalPadding: Double = 7
    /// Space above and below each tag's text.
    var verticalPadding: Double = 1.5

    /// The duration group of the chore.
    private var durationTier: ChoreDurationTier {
        ChoreDurationTier.from(minutes: chore.duration)
    }

    var body: some View {
        HStack(spacing: spacing) {
            // MARK: - Frequency tag
            CapsuleTag(
                tagName: chore.frequency.displayName,
                tagColor: chore.frequency.color,
                textColor: chore.frequency.textColor,
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding
            )

            // MARK: - Priority tag
            CapsuleTag(
                tagName: chore.priorityTag.displayName,
                tagColor: chore.priorityTag.color,
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding
            )

            // MARK: - Duration tag
            CapsuleTag(
                tagName: durationTier.displayText,
                tagColor: durationTier.color,
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding
            )
        }
    }
}
