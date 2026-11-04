//
//  HeaderFade.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 26/10/26.
//

import SwiftUI

/// The gradient behind a page's fixed header: opaque at the top (under the status bar), then
/// transparent a little below the header, so a list scrolls "under" it instead of being cut off.
struct HeaderFade: View {

    /// The page's background color.
    var color: Color = Color(.systemBackground)

    /// How far the fade reaches below the header.
    private let fadeLength: CGFloat = 24

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: color, location: 0),
                .init(color: color, location: 0.8),
                .init(color: color.opacity(0), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .padding(.bottom, -fadeLength)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }
}
