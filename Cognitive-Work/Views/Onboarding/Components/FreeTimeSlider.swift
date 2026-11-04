//
//  FreeTimeSlider.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 25/08/26.
//

import SwiftUI

/// A horizontal slider made of discrete squares, used to select how many
/// free-time blocks the user wants to reserve.
///
/// The component draws `maxRating` squares in a row. Squares up to the current
/// `rating` are painted with `activeColor`, while the remaining ones keep
/// `inactiveColor`. The selection is updated while the user taps or drags
/// anywhere over the row.
///
/// Example:
/// ```swift
/// @State private var freeTimeBlocks = 3
/// FreeTimeSlider(rating: $freeTimeBlocks)
/// ```
struct FreeTimeSlider: View {

    // MARK: - Constants

    /// Layout values shared by the component, kept here to avoid magic numbers.
    private enum Layout {
        /// Corner radius applied to every square of the row.
        static let squareCornerRadius: CGFloat = 9

        /// Extra width added to the mask when every square is selected, so the
        /// last square is fully covered instead of being clipped by rounding.
        static let fullSelectionOverflow: CGFloat = 4

        /// Smallest drag distance required to start tracking.
        /// Zero makes a simple tap update the selection.
        static let minimumDragDistance: CGFloat = 0
    }

    // MARK: - Properties

    /// Number of currently selected squares, ranging from `0` to `maxRating`.
    @Binding var rating: Int

    /// Total amount of squares rendered by the slider.
    var maxRating: Int = 6

    /// Width and height of a single square, in points.
    var squareSize: CGFloat { width * 0.09}

    /// Color applied to the squares inside the current selection.
    var activeColor: Color = .choreBlue

    /// Color applied to the squares outside the current selection.
    var inactiveColor: Color = .delimiteTimeSquareComponent

    /// Horizontal distance between two adjacent squares, in points.
    var spacing: CGFloat = 12

    /// Width required to lay out every square plus the spacing between them.
    private var totalWidth: CGFloat {
        CGFloat(maxRating) * squareSize + spacing * CGFloat(maxRating - 1)
    }
    
    /// Blocks changes while `true` (e.g. while saving).
    @Binding var isLoading: Bool

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            // MARK: Gray squares, with the selected ones painted over them
            ZStack(alignment: .leading) {
                buildSquaresRow(color: inactiveColor)

                buildSquaresRow(color: activeColor)
                    .mask(
                        Rectangle()
                            .size(
                                width: getSelectedWidth(in: geometry.size.width),
                                height: squareSize
                            )
                    )
            }
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            .gesture(buildSelectionGesture(in: geometry.size.width))
        }
        .frame(maxWidth: totalWidth, maxHeight: squareSize)
        // VoiceOver: one adjustable element (swipe up/down) instead of a drag-only row.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(L10n.tr("Tempo livre")))
        .accessibilityValue(Text(Self.accessibilityValue(for: rating)))
        .accessibilityAdjustableAction { direction in
            guard !isLoading else { return }
            switch direction {
            case .increment: rating = min(maxRating, rating + 1)
            case .decrement: rating = max(0, rating - 1)
            @unknown default: break
            }
        }
        // Voice Control can't swipe-adjust: "Mostrar ações para Tempo livre" offers these instead.
        .voiceControlNames([L10n.tr("Tempo livre"), L10n.tr("Horas"), L10n.tr("Controle de tempo")])
        .accessibilityAction(named: Text(L10n.tr("Aumentar"))) {
            guard !isLoading else { return }
            rating = min(maxRating, rating + 1)
        }
        .accessibilityAction(named: Text(L10n.tr("Diminuir"))) {
            guard !isLoading else { return }
            rating = max(0, rating - 1)
        }
    }

    /// Spoken value for a slider level ("2 horas", or "Nenhum tempo livre" at zero).
    static func accessibilityValue(for level: Int) -> String {
        let freeTime = FreeTimeEnum(level)
        return freeTime == .none ? L10n.tr("Nenhum tempo livre") : freeTime.displayName
    }

    // MARK: - View Builders

    /// Builds a row of `maxRating` squares painted with a single color.
    /// - Parameter color: Fill color applied to every square of the row.
    /// - Returns: The horizontal row of squares.
    private func buildSquaresRow(color: Color) -> some View {
        HStack(spacing: spacing) {
            ForEach(0 ..< maxRating, id: \.self) { i in
                let isFirst = i == 0, isLast = i == maxRating - 1
                let big: CGFloat = 17, small = Layout.squareCornerRadius
                UnevenRoundedRectangle(
                    topLeadingRadius:     isFirst ? big : small,
                    bottomLeadingRadius:  isFirst ? big : small,
                    bottomTrailingRadius: isLast  ? big : small,
                    topTrailingRadius:    isLast  ? big : small
                )
                .fill(color)
                .shadow(color: .black.opacity(0.15), radius: 3, x: 1, y: 3)
                .frame(width: squareSize, height: squareSize)
            }
        }
    }

    /// Builds the gesture that updates the selection while the user taps or
    /// drags over the row.
    /// - Parameter rowWidth: Rendered width of the squares row, in points.
    /// - Returns: A drag gesture bound to `updateRating(with:in:)`.
    private func buildSelectionGesture(in rowWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: Layout.minimumDragDistance)
            .onChanged { value in
                if !isLoading {
                    updateRating(with: value.location.x, in: rowWidth)
                }
            }
    }

    // MARK: - Helpers

    /// Calculates the width of the highlighted area for the current `rating`.
    /// - Parameter rowWidth: Rendered width of the squares row, in points.
    /// - Returns: The mask width, in points.
    private func getSelectedWidth(in rowWidth: CGFloat) -> CGFloat {
        guard rating > 0 else { return 0 }
        return CGFloat(rating) * squareSize + CGFloat(rating - 1) * spacing
    }

    /// Converts a horizontal gesture position into a discrete rating and stores
    /// the clamped result in the `rating` binding.
    /// - Parameters:
    ///   - xPosition: Horizontal position of the gesture, in the row coordinate space.
    ///   - rowWidth: Rendered width of the squares row, in points.
    private func updateRating(with xPosition: CGFloat, in rowWidth: CGFloat) {
        guard rowWidth > 0 else {
            return
        }

        let percentage = xPosition / rowWidth
        let rawRating = percentage * CGFloat(maxRating)
        let calculatedRating = Int(ceil(rawRating))
        let clampedRating = max(0, min(maxRating, calculatedRating))

        // if tap to unselect
        let isTappingFirstSquare = clampedRating <= 1
        let hasExistingSelection = rating > 0

        if isTappingFirstSquare && hasExistingSelection {
            rating = 0
            return
        }

        rating = clampedRating
    }
}

#Preview("FreeTimeSlider") {
    @Previewable @State var rating = 3

    VStack(spacing: 32) {
        FreeTimeSlider(rating: $rating, isLoading: .constant(false))

        // Preview only: verbatim, so it doesn't become a key nobody translates.
        Text(verbatim: "Blocos selecionados: \(rating)")
            .font(.system(size: 17, weight: .semibold))
            .contentTransition(.numericText())
            .animation(.default, value: rating)
    }
    .padding()
}
