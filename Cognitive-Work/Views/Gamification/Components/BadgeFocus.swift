//
//  BadgeFocus.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 17/11/26.
//

import SwiftUI

/// Brings the badge with this id to the center of the screen, animated.
func focusBadge(_ key: String, in focusedKey: Binding<String?>) {
    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
        focusedKey.wrappedValue = key
    }
}

extension View {

    /// Lets the screen bring a room badge (``RoomBadge``) to its center, highlighted
    /// (``FocusedBadgeView``), the same way ``couponFocus(viewModel:entries:focusedKey:namespace:)``
    /// does for coupons.
    ///
    /// - Parameters:
    ///   - progress: Whether the focused badge is unlocked, and how far its room's count is.
    ///   - focusedBadgeKey: Id (``RoomBadge/id``) of the badge in focus; `nil` when none.
    ///   - namespace: The namespace the row's badge icons use.
    ///   - onTogglePin: Pins the badge to the profile or unpins it; `nil` hides the pin button.
    func badgeFocus(
        progress: RoomBadgeProgressModel,
        focusedBadgeKey: Binding<String?>,
        namespace: Namespace.ID,
        onTogglePin: ((RoomBadge) -> Void)? = nil
    ) -> some View {
        modifier(BadgeFocusModifier(
            progress: progress,
            focusedBadgeKey: focusedBadgeKey,
            namespace: namespace,
            onTogglePin: onTogglePin
        ))
    }
}

private struct BadgeFocusModifier: ViewModifier {

    let progress: RoomBadgeProgressModel
    @Binding var focusedBadgeKey: String?
    let namespace: Namespace.ID
    let onTogglePin: ((RoomBadge) -> Void)?

    func body(content: Content) -> some View {
        content
            // The focused badge takes the whole screen, like a focused coupon.
            .toolbar(focusedBadgeKey == nil ? .automatic : .hidden, for: .tabBar)
            .overlay { overlay }
    }

    /// The chosen badge at the center, over a white background. Tapping outside it closes it.
    @ViewBuilder
    private var overlay: some View {
        if let key = focusedBadgeKey, let badge = RoomBadge(rawValue: key) {
            ZStack {
                Color.white
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: close)
                    .accessibilityHidden(true)
                    .transition(.opacity)

                FocusedBadgeView(
                    badge: badge,
                    isUnlocked: progress.isUnlocked(badge),
                    count: progress.count(for: badge.room),
                    namespace: namespace,
                    matchID: key,
                    pin: onTogglePin.map { toggle in
                        FocusedBadgeView.Pin(
                            isPinned: progress.isPinned(badge),
                            canPin: progress.canPinMore,
                            toggle: { toggle(badge) }
                        )
                    },
                    onClose: close
                )
            }
        }
    }

    /// Sends the focused badge back to its row.
    private func close() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            focusedBadgeKey = nil
        }
    }
}
