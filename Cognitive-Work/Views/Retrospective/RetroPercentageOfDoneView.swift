//
//  RetroPercentageOfDoneView.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 29/09/26.
//

import SwiftUI

/// The retrospective's percentage page: how much of the user's schedule they did, drawn as a
/// purple pie that empties while the number counts up.
///
/// Reads only `viewModel.percentageContent`; all numbers and messages come from the view model.
struct RetroPercentageOfDoneView: View {
    /// The retrospective's view model (shared with the other pages).
    let viewModel: RetroViewModel
    /// Animated value (0...100) that drives the pie and the counter.
    @State private var percentage: Double = 0.0

    /// This page's content.
    private var content: RetroPercentageContent { viewModel.percentageContent }

    /// Whether this page is the one on screen.
    private var isActive: Bool { viewModel.isPageActive(.percentage) }

    /// What restarts the animation: the page becoming visible or the percentage changing.
    private struct AnimationKey: Equatable {
        let isActive: Bool
        let target: Double
    }

    var body: some View {
        ZStack {
            // MARK: - Background: purple with the white pie
            Color(.chorePurple)
                .overlay{
                    PieSlice(progress: percentage / 100)
                        .padding(.bottom, height * 0.127)
                        .frame(width: height * 2, height: height * 2)
                        .ignoresSafeArea()
                        .foregroundStyle(.white)
                }
                .ignoresSafeArea()

            // MARK: - Keyhole shape over the pie
            VStack{
                Keyhole()
                    .aspectRatio(width * 0.8 / height * 1.5, contentMode: .fit)
                    .padding(.top, height * 0.24)
                    .foregroundStyle(.white)
                
            }
                

            // MARK: - Texts and buttons
            VStack {
                Spacer ()
                
                // MARK: Percentage and summary
                AnimatedPercentageText(value: percentage)
                    .bold()
                    .font(.system(size: 64))
                    .padding(.bottom, height * 0.03)
//                Text(content.summary)
                Text(try! AttributedString(markdown: content.summary))
                    .font(.title)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, height * 0.008)
                    .frame(width: width * 0.796)
                Text(content.subtitle)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.subTitleGray)
                
                Spacer()
                
                // MARK: Cheering word
                Text(content.closing)
                    .bold()
                    .font(.custom("Alan Sans", size: 40))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.bottom, height * 0.018)
                
                // MARK: Actions: see later or continue
                Button {
                    withAnimation {
                        viewModel.skipRetrospective()
                    }
                } label: {
                    Text("ver depois")
                        .fontWeight(.semibold)
                        .font(.subheadline)
                        .foregroundStyle(.subTitleGray)
                }
                .padding(.bottom, height * 0.014)
                
                Button {
                    withAnimation {
                        viewModel.advance()
                    }
                } label: {
                    Text("Continuar")
                        .frame(minWidth: width * 0.69, minHeight: height * 0.037)
                        .multilineTextAlignment(.center)
                        .fontWeight(.medium)
                        .font(.system(size: 17))
                }
                .buttonStyle(.glassProminent)
                .glassEffectTransition(.identity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        // MARK: - Pie and counter animation
        // Not onAppear: changing the state there can be applied before the first frame is drawn,
        // so the view would appear already filled. Drawing 0 first, then animating, always plays.
        // Keyed on the page being the visible one: the paged TabView builds this page while the
        // previous one is still on screen, and the animation would play where nobody sees it.
        // Re-runs every time the page becomes visible and if the data changes.
        .task(id: AnimationKey(isActive: isActive, target: content.percentage)) {
            percentage = 0
            guard isActive else { return }
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 2)) {
                percentage = content.percentage
            }
        }
    }
}

#if DEBUG
#Preview("0%") {
    RetroPreviewHost(completed: 0, total: 20, page: .percentage) { RetroPercentageOfDoneView(viewModel: $0) }
}

#Preview("25%") {
    RetroPreviewHost(completed: 25, total: 100, page: .percentage) { RetroPercentageOfDoneView(viewModel: $0) }
}

#Preview("50%") {
    RetroPreviewHost(completed: 50, total: 100, page: .percentage) { RetroPercentageOfDoneView(viewModel: $0) }
}

#Preview("75%") {
    RetroPreviewHost(completed: 75, total: 100, page: .percentage) { RetroPercentageOfDoneView(viewModel: $0) }
}

#Preview("100%") {
    RetroPreviewHost(completed: 100, total: 100, page: .percentage) { RetroPercentageOfDoneView(viewModel: $0) }
}
#endif
