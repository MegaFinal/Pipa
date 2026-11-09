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
    /// When on, the bars appear already full instead of growing.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
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
    
    /// Chores done in each room, for VoiceOver's audio graph.
    private var chartDescriptor: CategoryChartDescriptor {
        CategoryChartDescriptor(
            title: L10n.tr("Tarefas por cômodo"),
            summary: content.subtitle,
            categoryAxisTitle: L10n.tr("Cômodo"),
            valueAxisTitle: L10n.tr("Tarefas"),
            points: content.bars.map { (label: $0.roomName, value: Double($0.choreCount)) }
        )
    }

    var body: some View {
        VStack {
            // MARK: - Title ("N cômodos") and the room worked on most
            Text(content.title)
                .bold()
                .font(.custom("Alan Sans", fixedSize: 64))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.top, height * 0.071)
                .accessibilityAddTraits(.isHeader)
            
            Text(content.subtitle)
                .font(.system(size: 28))
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
                                .font(.system(size: 17))
                                .fontWeight(.semibold)
                                .padding(.bottom, 0.01)
                                // Read together with its bar below, as one element.
                                .accessibilityHidden(true)
                        
                            Capsule()
                                .frame(width: isChartShown ? barWidth(for: bar) : 0, height: height * 0.041)
                                .foregroundStyle(bar.color.uiColor)
                                .overlay(alignment: .leading) {
                                    Text("\(bar.choreCount) tarefas")
                                        .font(.system(size: 15))
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
                                // MARK: Accessibility: "Cozinha, 12 tarefas" as one element
                                .accessibilityElement(children: .ignore)
                                .voiceOverLabel(bar.roomName)
                                .voiceOverValue(L10n.tr("\(bar.choreCount) tarefas"))
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, width * 0.061)
                .padding(.bottom, height * 0.02)
                // MARK: Accessibility: the bars as a chart, with an audio graph
                .accessibilityElement(children: .contain)
                .voiceOverLabel(L10n.tr("Tarefas por cômodo"))
                .accessibilityChartDescriptor(chartDescriptor)
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
            .voiceControlNames([L10n.tr("Continuar"), L10n.tr("Concluir")])
            .glassEffectTransition(.identity)
        }
        // MARK: - Bar animation
        // Bars grow every time this page becomes the visible one.
        .task(id: viewModel.isRoomsPageActive) {
            if viewModel.isRoomsPageActive {
                try? await Task.sleep(for: .seconds(0.3))
                if reduceMotion {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { isChartShown = true }
                } else {
                    isChartShown = true
                }
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
