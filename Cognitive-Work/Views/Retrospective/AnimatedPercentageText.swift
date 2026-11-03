//
//  AnimatedPercentageText.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 29/09/26.
//

import SwiftUI

/// Text that shows a percentage and interpolates its value frame by frame,
/// so it follows the exact same animation (duration and curve) as any other animated value.
struct AnimatedPercentageText: View, Animatable {
    /// The percentage to show, from `0` to `100`.
    var value: Double

    /// Lets SwiftUI animate ``value``, so the number counts up during the animation.
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        // MARK: - Rounded percentage (fixed-width digits so it doesn't wobble)
        // FormatStyle instead of "\(n)%": languages write percentages differently ("45 %",
        // "%45"), and a "%" in a localized string makes Xcode warn about it.
        Text(verbatim: ChartA11y.percent(value / 100))
            .monospacedDigit()
    }
}

#Preview {
    @Previewable @State var value = 0.0
    AnimatedPercentageText(value: value)
        .font(.system(size: 64).bold())
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6)) { value = 100 }
        }
}
