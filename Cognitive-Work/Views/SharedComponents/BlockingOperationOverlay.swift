//
//  BlockingOperationOverlay.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 28/09/26.
//

import SwiftUI

/// Prevents the user from leaving or interacting with a screen while a destructive,
/// non-cancellable CloudKit operation (delete or unlink) is in flight.
struct BlockingOperationOverlay: ViewModifier {
    /// Whether the blocking screen shows.
    @Binding var isPresented: Bool
    /// What is happening (a localization key, e.g. "Excluindo sua casa...").
    let message: String
    
    /// Disables the screen and covers it with the loading screen while ``isPresented`` is `true`.
    func body(content: Content) -> some View {
        content
            .disabled(isPresented)
            .navigationBarBackButtonHidden(isPresented)
            .interactiveDismissDisabled(isPresented)
            .fullScreenCover(isPresented: $isPresented) {
                BlockingOperationView(message: message)
            }
    }
}

/// Full-screen, non-dismissable loading state shown by ``BlockingOperationOverlay``.
private struct BlockingOperationView: View {
    /// What is happening (a localization key).
    let message: String
    
    var body: some View {
        VStack(spacing: 20) {
            // MARK: - Spinner and message
            ProgressView()
                .scaleEffect(1.5)
                .padding(.bottom, 8)
            // `message` is a localization key ("Excluindo sua casa...").
            Text(LocalizedStringKey(message))
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .interactiveDismissDisabled()
        // One modal element announcing the operation; VoiceOver can't reach the screen behind.
        .accessibilityElement(children: .ignore)
        .voiceOverLabel(L10n.tr(key: message))
        .accessibilityAddTraits([.isModal, .updatesFrequently])
        .onAppear {
            VoiceOver.announce(L10n.tr(key: message))
        }
    }
}

extension View {
    /// Blocks interaction and navigation away from this screen for as long as `isPresented`
    /// is `true`. Use for any destructive delete/unlink operation that must not be
    /// interrupted or abandoned mid-flight. See ``BlockingOperationOverlay``.
    func blockingOperation(isPresented: Binding<Bool>, message: String) -> some View {
        modifier(BlockingOperationOverlay(isPresented: isPresented, message: message))
    }
}
