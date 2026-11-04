//
//  TintedCoinPig.swift
//  Cognitive-Work
//

import SwiftUI

/// The coin piggy bank with its body in the given color. The pig's artwork is split in two assets:
/// the body (`RetroPigBody`, a template image, so it takes the color) and the white details
/// (`RetroPigDetails`: the eye and the shine), which stay white on top of it.
struct TintedCoinPig: View {

    /// The color of the pig's body.
    let color: Color

    var body: some View {
        Image("RetroPigBody")
            .resizable()
            .scaledToFit()
            .foregroundStyle(color)
            .overlay {
                Image("RetroPigDetails")
                    .resizable()
                    .scaledToFit()
            }
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack {
        TintedCoinPig(color: .orange)
        TintedCoinPig(color: .purple)
    }
    .frame(height: 60)
    .padding()
}
