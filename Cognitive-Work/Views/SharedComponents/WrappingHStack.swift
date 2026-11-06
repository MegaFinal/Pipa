//
//  WrappingHStack.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 06/11/26.
//

import SwiftUI

/// Lays its views out in a row, like an `HStack`, and moves to a new line below when the next
/// one doesn't fit, like words in a paragraph. Rows start at the leading edge.
struct WrappingHStack: Layout {

    /// Space between two views of a row.
    var spacing: CGFloat = 8
    /// Space between two rows.
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, maxWidth: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                // Centered on the row, so views of different heights line up.
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    /// One line of views: their indexes and how much room they take.
    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// Splits the views into lines no wider than `maxWidth`. A view wider than that gets a line
    /// of its own.
    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let widthWithView = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty, widthWithView > maxWidth {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

// MARK: - Previews

#Preview {
    WrappingHStack(spacing: 10, lineSpacing: 10) {
        ForEach(0..<9) { index in
            Circle()
                .fill(Color.choreBlue)
                .frame(width: 44, height: 44)
                .overlay { Text("\(index + 1)").foregroundStyle(.white) }
        }
    }
    .frame(width: 220, alignment: .leading)
    .padding()
    .border(.gray)
}
