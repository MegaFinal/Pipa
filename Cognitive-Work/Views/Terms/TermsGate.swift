//
//  TermsGate.swift
//  Cognitive-Work
//

import SwiftUI

extension View {

    /// Blocks the app until the Terms of Use are accepted: shows them on first launch (and when
    /// they change) and replaces the app with a farewell screen when they are declined.
    func requiresTermsAcceptance() -> some View {
        modifier(TermsGate())
    }
}

/// Shows the app, the terms sheet or the farewell screen, depending on the user's decision.
/// See ``SwiftUI/View/requiresTermsAcceptance()``.
private struct TermsGate: ViewModifier {

    /// The user's decision about the terms.
    @State private var viewModel = TermsViewModel()

    /// Wraps the app with the farewell screen and the terms sheet.
    func body(content: Content) -> some View {
        Group {
            // MARK: - Farewell screen after declining, otherwise the app
            if viewModel.decision == .declined {
                TermsDeclinedView(
                    title: viewModel.farewellTitle,
                    message: viewModel.farewellMessage,
                    onReviewTerms: { viewModel.reviewTerms() }
                )
                .transition(.opacity)
            } else {
                content
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.decision)
        // MARK: - Terms sheet (can't be swiped away)
        .sheet(isPresented: Binding(
            get: { viewModel.isShowingTerms },
            set: { _ in }
        )) {
            TermsOfUseView(viewModel: viewModel)
        }
    }
}
