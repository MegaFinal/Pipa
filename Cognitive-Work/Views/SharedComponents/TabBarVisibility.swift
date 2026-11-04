//
//  TabBarVisibility.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 30/09/26.
//

import SwiftUI

/// Owns the tab bar's visibility so it can animate back in when a pushed screen that hides it
/// is popped.
///
/// `.toolbar(.hidden, for: .tabBar)` on a pushed screen makes the bar pop back with no animation,
/// because nothing animates the change when that screen leaves. Instead, each tab's root applies
/// the visibility kept here (``SwiftUI/View/tabBarVisibilityRoot()``), and pushed screens only
/// report that they are on screen (``SwiftUI/View/hidesTabBar()``). When the last of them
/// disappears, the bar comes back `withAnimation`.
///
/// Screens are counted, not flagged, so pushing one hiding screen on top of another keeps the bar
/// hidden whatever order `onAppear`/`onDisappear` fire in.
@MainActor
@Observable
final class TabBarVisibilityController {
    
    /// Used both when the bar comes back and on the tab root, so the two never disagree.
    static let animation: Animation = .easeOut(duration: 0.15)
    
    /// Whether the tab bar shows right now.
    private(set) var visibility: Visibility = .visible
    
    /// How many pushed screens that hide the bar are on screen.
    private var hidingScreens = 0
    
    /// Call when a screen that hides the bar appears.
    func hidingScreenDidAppear() {
        hidingScreens += 1
        visibility = .hidden
    }
    
    /// Call when a screen that hides the bar disappears; the bar comes back after the last one.
    func hidingScreenDidDisappear() {
        hidingScreens = max(hidingScreens - 1, 0)
        guard hidingScreens == 0 else { return }
        
        withAnimation(Self.animation) {
            visibility = .visible
        }
    }
}

/// Applies the controller's visibility to the tab bar. Goes on the root view of each tab's
/// `NavigationStack`.
private struct TabBarVisibilityRoot: ViewModifier {
    /// The shared controller, if the app provides one.
    @Environment(TabBarVisibilityController.self) private var controller: TabBarVisibilityController?
    
    /// Applies the controller's visibility, animated.
    func body(content: Content) -> some View {
        let visibility = controller?.visibility ?? .automatic
        
        content
            .toolbar(visibility, for: .tabBar)
            .animation(TabBarVisibilityController.animation, value: visibility)
    }
}

/// Hides the tab bar while this screen is on screen.
///
/// The screen itself must not apply `.toolbar(.hidden, for: .tabBar)`: that preference is dropped
/// without animation the moment the screen is popped, which is exactly the abrupt pop this avoids.
/// Only the tab root decides the visibility. Without a ``TabBarVisibilityController`` in the
/// environment (onboarding, previews) it falls back to plainly hiding the bar.
private struct HidesTabBar: ViewModifier {
    /// The shared controller, if the app provides one.
    @Environment(TabBarVisibilityController.self) private var controller: TabBarVisibilityController?
    
    /// Reports appearing and disappearing to the controller (or simply hides the bar without one).
    @ViewBuilder
    func body(content: Content) -> some View {
        if let controller {
            content
                .onAppear { controller.hidingScreenDidAppear() }
                .onDisappear { controller.hidingScreenDidDisappear() }
        } else {
            content.toolbar(.hidden, for: .tabBar)
        }
    }
}

extension View {
    /// Lets this tab root show and hide the tab bar with an animation. See ``TabBarVisibilityController``.
    func tabBarVisibilityRoot() -> some View {
        modifier(TabBarVisibilityRoot())
    }
    
    /// Hides the tab bar while this pushed screen is visible and animates it back when it leaves.
    func hidesTabBar() -> some View {
        modifier(HidesTabBar())
    }
}
