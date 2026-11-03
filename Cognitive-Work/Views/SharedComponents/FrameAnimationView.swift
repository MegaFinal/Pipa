//
//  FrameAnimationView.swift
//  Cognitive-Work
//

import SwiftUI

/// What is drawn behind a ``LoadingAnimation``.
enum LoadingBackground {
    /// A full-screen illustration from the asset catalog.
    case scenery(String)
    /// A light-blue sky with clouds drifting slowly to the side (``DriftingClouds``).
    case driftingClouds
}

/// The hand-drawn loading animations, exported frame by frame from Procreate.
///
/// The frames live in `Assets.xcassets/LoadingAnimations`, named `<framePrefix>_<index>`.
enum LoadingAnimation {
    /// Two people flying kites on the hills. Plays forward and back.
    case kites
    /// A kite that grows and bursts in orange until it covers the whole screen.
    case burst
    
    /// The start of every frame's asset name.
    var framePrefix: String {
        switch self {
        case .kites: "loadingKites"
        case .burst: "loadingBurst"
        }
    }
    
    /// How many frames the animation has.
    var frameCount: Int {
        switch self {
        case .kites: 16
        case .burst: 21
        }
    }
    
    /// Playback speed.
    ///
    /// The burst was exported from Procreate as 42 frames where each drawing repeats twice, so
    /// the catalog keeps only the 21 different ones and plays them at half the speed: the same
    /// timing as the 42 frames at 12 fps (3.5 s), with half the assets.
    var framesPerSecond: Double {
        switch self {
        case .kites: 12
        case .burst: 8
        }
    }
    
    /// The frame shown instead of the animation when Reduce Motion is on.
    var stillFrame: Int {
        switch self {
        case .kites: 0
        case .burst: 12
        }
    }
    
    /// Whether the animation plays forward and then backward ("vai e volta") instead of
    /// jumping from the last frame back to the first.
    var autoreverses: Bool {
        switch self {
        case .kites: true
        case .burst: false
        }
    }
    
    /// What is drawn behind the animation.
    var background: LoadingBackground {
        switch self {
        case .kites: .scenery("loadingKitesBackground")
        case .burst: .driftingClouds
        }
    }
    
    /// How long one full pass of the animation takes (forward and back, with ``autoreverses``).
    var cycleDuration: TimeInterval {
        let steps = autoreverses ? 2 * (frameCount - 1) : frameCount
        return Double(steps) / framesPerSecond
    }
    
    /// How far from the bottom of the screen the drawing's base sits, as a fraction of the
    /// screen height. For the kites it puts the people's feet on the front hill of the background.
    var groundLevel: CGFloat {
        switch self {
        case .kites: 0.17
        case .burst: 0
        }
    }
    
    /// Whether the drawing fills the screen (cropping the edges) instead of fitting inside it.
    var fillsScreen: Bool {
        switch self {
        case .kites: false
        case .burst: true
        }
    }
    
    /// The frame to show `elapsed` seconds after the animation started, repeating forever.
    ///
    /// With ``autoreverses`` the cycle is 0, 1 … last … 1, 0: the first and last frames show only
    /// once per turn, so the motion doesn't pause at either end.
    func frameIndex(after elapsed: TimeInterval) -> Int {
        let step = Int(max(elapsed, 0) * framesPerSecond)
        guard autoreverses, frameCount > 1 else { return step % frameCount }
        
        let cycle = 2 * (frameCount - 1)
        let position = step % cycle
        return position < frameCount ? position : cycle - position
    }
}

/// Plays a ``LoadingAnimation`` over and over (looping or back and forth), or shows a still
/// frame when Reduce Motion is on.
struct FrameAnimationView: View {
    /// Which animation plays.
    let animation: LoadingAnimation
    
    /// When on, only ``LoadingAnimation/stillFrame`` is shown.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    /// When the animation started, so it always begins on the first frame.
    @State private var startDate = Date()
    
    var body: some View {
        if reduceMotion {
            frame(animation.stillFrame)
        } else {
            TimelineView(.animation(minimumInterval: 1 / animation.framesPerSecond)) { context in
                frame(animation.frameIndex(after: context.date.timeIntervalSince(startDate)))
            }
        }
    }
    
    /// One frame, fitted or filled according to the animation.
    private func frame(_ index: Int) -> some View {
        Image("\(animation.framePrefix)_\(index)")
            .resizable()
            .aspectRatio(contentMode: animation.fillsScreen ? .fill : .fit)
    }
}

#Preview("Kites") {
    FrameAnimationView(animation: .kites)
}

#Preview("Burst") {
    FrameAnimationView(animation: .burst)
}
