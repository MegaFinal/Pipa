//
//  RetroCoinsScatter.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 29/09/26.
//

import SwiftUI

/// Coins floating around the pig, popping in one after another.
/// Each coin has a fixed slot (position, size, rotation), so the layout never changes between redraws.
/// The slots are ordered: the first ones are the most prominent, so more points just reveal more slots.
/// Use it as an `.overlay` of the pig image so the slots are relative to the pig's center.
struct RetroCoinsScatter: View {
    /// How many coins to show (at most ``maxCount``).
    let count: Int

    /// Starts `false` and turns `true` on appear, so each coin pops in.
    @State private var isShown = false

    /// Offsets and sizes are fractions of the screen width, relative to the pig's center.
    private struct Slot {
        /// Horizontal offset.
        let x: CGFloat
        /// Vertical offset.
        let y: CGFloat
        /// The coin's width.
        let size: CGFloat
        /// The coin's tilt, in degrees.
        let rotation: Double
    }

    /// Every coin position, most prominent first.
    private static let slots: [Slot] = [
        Slot(x: 0.24, y: -0.34, size: 0.26, rotation: 10),   // big, top right
        Slot(x: -0.26, y: -0.20, size: 0.16, rotation: -12), // small, left
        Slot(x: -0.08, y: -0.43, size: 0.10, rotation: 20),
        Slot(x: 0.40, y: -0.10, size: 0.08, rotation: -8),
        Slot(x: -0.38, y: -0.02, size: 0.08, rotation: 15)
    ]

    /// The most coins that can be shown.
    static var maxCount: Int { slots.count }

    var body: some View {
        ZStack {
            // MARK: - Coins, each in its slot, popping in one after another
            ForEach(Array(Self.slots.prefix(count).enumerated()), id: \.offset) { index, slot in
                Image("RetroCoin")
                    .resizable()
                    .scaledToFit()
                    .frame(width: width * slot.size, height: width * slot.size)
                    .rotationEffect(.degrees(slot.rotation))
                    .offset(x: width * slot.x, y: width * slot.y)
                    .scaleEffect(isShown ? 1 : 0)
                    .opacity(isShown ? 1 : 0)
                    .animation(
                        .spring(response: 0.5, dampingFraction: 0.55).delay(Double(index) * 0.15),
                        value: isShown
                    )
            }
        }
        .onAppear { isShown = true }
    }
}

#Preview {
    Image("RetroPigCoin")
        .resizable()
        .frame(width: 240, height: 240)
        .overlay { RetroCoinsScatter(count: 5) }
}
