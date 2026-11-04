//
//  DriftingClouds.swift
//  Cognitive-Work
//

import SwiftUI

/// Clouds drifting slowly to the right across the whole view, coming back in from the left
/// after they leave. Stands still when Reduce Motion is on.
///
/// Uses the ranking's cloud drawings (`rankCloudLight` / `rankCloudMid`).
struct DriftingClouds: View {
    /// One cloud: its drawing, where it starts and how fast it moves.
    private struct Cloud {
        /// The asset name.
        let asset: String
        /// Vertical center, as a fraction of the view's height.
        let y: CGFloat
        /// Width, as a fraction of the view's width.
        let width: CGFloat
        /// Left edge at the start, as a fraction of the view's width.
        let startX: CGFloat
        /// How much of the view's width it crosses per second.
        let speed: CGFloat
    }
    
    /// Height / width of the cloud drawings.
    private static let aspectRatio: CGFloat = 434.0 / 880.0
    
    /// Spread over the screen, each at its own slow speed so they drift apart.
    private static let clouds: [Cloud] = [
        Cloud(asset: "rankCloudLight", y: 0.10, width: 0.70, startX: 0.05, speed: 0.022),
        Cloud(asset: "rankCloudMid", y: 0.25, width: 0.42, startX: 0.62, speed: 0.014),
        Cloud(asset: "rankCloudLight", y: 0.42, width: 0.55, startX: 0.30, speed: 0.018),
        Cloud(asset: "rankCloudLight", y: 0.62, width: 0.38, startX: 0.80, speed: 0.012),
        Cloud(asset: "rankCloudLight", y: 0.82, width: 0.60, startX: 0.10, speed: 0.016)
    ]
    
    /// When on, the clouds stay where they start.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    /// When the clouds started moving.
    @State private var startDate = Date()
    
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                let seconds = reduceMotion ? 0 : timeline.date.timeIntervalSince(startDate)
                
                ZStack(alignment: .topLeading) {
                    ForEach(Self.clouds.indices, id: \.self) { index in
                        let cloud = Self.clouds[index]
                        let cloudWidth = cloud.width * size.width
                        let cloudHeight = cloudWidth * Self.aspectRatio
                        
                        Image(cloud.asset)
                            .resizable()
                            .frame(width: cloudWidth, height: cloudHeight)
                            .offset(
                                x: Self.left(of: cloud, in: size.width, after: seconds),
                                y: cloud.y * size.height - cloudHeight / 2
                            )
                    }
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
            }
        }
        .clipped()
        .accessibilityDecorative()
    }
    
    /// The cloud's left edge `seconds` after the start. Once it has fully left on the right it
    /// re-enters from the left, so the sky never empties.
    private static func left(of cloud: Cloud, in width: CGFloat, after seconds: TimeInterval) -> CGFloat {
        let cloudWidth = cloud.width * width
        let span = width + cloudWidth
        let travelled = cloud.startX * width + cloudWidth + cloud.speed * width * CGFloat(seconds)
        return travelled.truncatingRemainder(dividingBy: span) - cloudWidth
    }
}

#Preview {
    DriftingClouds()
        .background(Color(.lowOpacityBlue.opacity(0.35)))
}
