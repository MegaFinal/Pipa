//
//  RetroRoomsView.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 29/09/26.
//

import SwiftUI

/// The retrospective's rooms page: a bar chart of how many chores the user did in each room.
///
/// Reads only `viewModel.roomsContent` (and `isRoomsPageActive` to replay the bar animation).
struct RetroRoomsView: View {
    /// The retrospective's view model (shared with the other pages).
    let viewModel: RetroViewModel
    
    /// `false` draws the bars empty; turning it `true` makes them grow.
    @State private var isChartShown = false
    
    /// This page's content.
    private var content: RetroRoomsContent { viewModel.roomsContent }
    
    /// Rooms with fewer chores than this get the same width as a room with this many,
    /// so the "X tarefas" text always fits inside the bar.
    private let minimumChoresForWidth = 2
    
    /// Final width of the bar: proportional to the number of chores of the room, never narrower than the minimum.
    private func barWidth(for bar: RetroRoomsContent.Bar) -> CGFloat {
        let chores = max(bar.choreCount, minimumChoresForWidth)
        let maxChores = max(content.maxChoreCount, minimumChoresForWidth)
        return (width * 0.877) * CGFloat(chores) / CGFloat(maxChores)
    }
    
    var body: some View {
        VStack {
            // MARK: - Title ("N cômodos") and the room worked on most
            Text(content.title)
                .bold()
                .font(.custom("Alan Sans", size: 64))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.top, height * 0.071)
            
            Text(content.subtitle)
                .font(.title)
                .multilineTextAlignment(.center)
                .frame(maxWidth: width * 0.877)
                .padding(.bottom, height * 0.02)
            
            // MARK: - Bar chart: one bar per room
            // Only the chart scrolls (when there are many rooms); title and button stay fixed.
            ScrollView(.vertical, showsIndicators: false) {
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(content.bars.enumerated()), id: \.element.id) { index, bar in
                            Text(bar.roomName)
                                .font(.body)
                                .fontWeight(.semibold)
                                .padding(.bottom, 0.01)
                        
                            Capsule()
                                .frame(width: isChartShown ? barWidth(for: bar) : 0, height: height * 0.041)
                                .foregroundStyle(bar.color.uiColor)
                                .overlay(alignment: .leading) {
                                    Text("\(bar.choreCount) tarefas")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal)
                                        .fixedSize()
                                        .opacity(isChartShown ? 1 : 0)
                                        .animation(.easeIn(duration: 0.3).delay(0.5 + Double(index) * 0.12), value: isChartShown)
                                }
                                // Taller bars take longer, so every bar grows at the same speed.
                                .animation(
                                    .easeOut(duration: 0.5 + 0.7 * Double(bar.choreCount) / Double(max(content.maxChoreCount, 1)))
                                        .delay(Double(index) * 0.12),
                                    value: isChartShown
                                )
                                .padding(.bottom, 0.02)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, width * 0.061)
                .padding(.bottom, height * 0.02)
            }
            .scrollBounceBehavior(.basedOnSize)
            
            Spacer()

            // MARK: - Continue / conclude
            Button {
                withAnimation {
                    viewModel.advance()
                }
            } label: {
                Text(RetroPage.rooms.isLast ? LocalizedStringKey("Concluir") : LocalizedStringKey("Continuar"))
                    .frame(minWidth: width * 0.69, minHeight: height * 0.037)
                    .multilineTextAlignment(.center)
                    .fontWeight(.medium)
                    .font(.system(size: 17))
            }
            .buttonStyle(.glassProminent)
            .glassEffectTransition(.identity)
        }
        // MARK: - Bar animation
        // Bars grow every time this page becomes the visible one.
        .task(id: viewModel.isRoomsPageActive) {
            if viewModel.isRoomsPageActive {
                try? await Task.sleep(for: .seconds(0.3))
                isChartShown = true
            } else {
                // Reset without animating, so the bars grow again next time the page appears.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { isChartShown = false }
            }
        }
    }
}

#if DEBUG
#Preview {
    // Starts on the rooms page so the bars animate in the preview.
    RetroPreviewHost(page: .rooms) { RetroRoomsView(viewModel: $0) }
}
#endif
