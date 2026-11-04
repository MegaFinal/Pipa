//
//  PullDownAtTopGesture.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 15/09/26.
//

import SwiftUI

/// Triggers an action when the user drags downward past a threshold and releases,
/// but only when the drag started with the nearest `ScrollView` already at its top
/// edge (pull-to-refresh style).
///
/// Reads the drag's own translation instead of relying purely on `ScrollView`
/// geometry, so it also works on non-scrollable views (e.g. a plain `ZStack`) —
/// there, `isAtTop` simply stays `true` and the gesture behaves unconditionally.
/// Uses `.simultaneousGesture` and a vertical-dominance check so it never steals
/// or gets stolen by a sibling/child gesture (e.g. a card's own horizontal
/// `DragGesture`).
struct PullDownAtTopGesture: ViewModifier {
    
    /// How far (in points) the user must drag down before releasing triggers the action.
    let threshold: CGFloat
    
    /// The action executed when a valid pull-down is released.
    let action: () -> Void
    
    /// Whether the nearest `ScrollView` (if any) is currently at its top edge.
    /// Stays `true` when there's no `ScrollView` ancestor, so the gesture keeps
    /// working unconditionally on plain views like the Carousel's empty state.
    @State private var isAtTop: Bool = true
    
    /// Current vertical translation of the in-progress drag (0 while idle, dragging up,
    /// or the drag didn't start at the top).
    @State private var translation: CGFloat = 0
    
    /// Whether we've already captured `isAtTop` for the drag currently in progress.
    @State private var hasCheckedStart = false
    
    /// Snapshot of `isAtTop` taken at the very start of the current drag.
    @State private var gestureStartedAtTop = false
    
    /// Adds the rubber-band offset, the scroll-position tracking and the drag gesture.
    func body(content: Content) -> some View {
        content
        // Small rubber-band feedback while dragging; purely visual.
            .offset(y: translation * 0.4)
        // Passively tracks whether the enclosing ScrollView is at its top edge.
        // No-op when there's no ScrollView ancestor (isAtTop just stays true).
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top <= 1
            } action: { _, newValue in
                isAtTop = newValue
            }
        // `.simultaneousGesture` (not `.gesture`) so this never wins gesture
        // priority away from a child's own `DragGesture` (e.g. card swiping)
        // or from the ScrollView's own native scrolling.
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        // Decide once per gesture, using the top-of-scroll state
                        // from right before this drag began.
                        if !hasCheckedStart {
                            gestureStartedAtTop = isAtTop
                            hasCheckedStart = true
                        }
                        // If the list wasn't already at the top, this is just a
                        // normal scroll — never treat it as a pull-down.
                        guard gestureStartedAtTop else { return }
                        
                        // Only react to drags that are mostly vertical, so a
                        // horizontal card swipe never gets misread as a pull-down.
                        let isMostlyVertical = abs(value.translation.height) > abs(value.translation.width)
                        guard isMostlyVertical else { return }
                        translation = max(0, value.translation.height)
                    }
                    .onEnded { value in
                        let isMostlyVertical = abs(value.translation.height) > abs(value.translation.width)
                        let didPassThreshold = gestureStartedAtTop && isMostlyVertical && value.translation.height > threshold
                        
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                            translation = 0
                            if didPassThreshold {
                                action()
                            }
                        }
                        hasCheckedStart = false
                        gestureStartedAtTop = false
                    }
            )
    }
}

extension View {
    /// Adds a pull-down-at-top trigger to a view. On a `ScrollView`, only fires
    /// when the drag starts at the top edge; on a non-scrollable view, fires
    /// unconditionally on a sufficiently long, mostly-vertical downward drag.
    /// - Parameters:
    ///   - threshold: Minimum downward drag distance, in points, required to trigger the action.
    ///   - action: The closure executed when the pull-down is released past the threshold.
    func onPullDownAtTop(threshold: CGFloat = 70, action: @escaping () -> Void) -> some View {
        modifier(PullDownAtTopGesture(threshold: threshold, action: action))
    }
}
