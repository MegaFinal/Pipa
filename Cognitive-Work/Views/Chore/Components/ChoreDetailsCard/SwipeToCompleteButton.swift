//
//  SwipeToCompleteButton.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 26/08/26.
//

import SwiftUI

/// The "Deslize para concluir" slider: the user drags the round button to the right to complete
/// a chore. Small vibrations follow the drag and a stronger one confirms it.
///
/// VoiceOver and Voice Control users complete it with a tap instead.
struct SwipeToCompleteButton: View {
    
    /// Whether the chore is already done (the button stays at the end).
    var isDone: Bool
    
    /// Runs when the user completes the swipe.
    var action: () -> Void
    /// The button's color.
    var color: Color = .black
    
    /// How far the round button was dragged, in points.
    @State private var dragOffset: CGFloat = 0
    
    /// Tracks which progress "steps" have already fired a haptic during this drag, so each one only fires once per gesture instead of repeatedly.
    @State private var reachedSteps: Set<Int> = []
    
    /// The control's height.
    private let height: CGFloat = 54
    /// Space between the round button and the capsule's edge.
    private let circlePadding: CGFloat = 5
    
    /// Progress fractions at which a light "tick" haptic fires during the drag.
    private let progressSteps: [CGFloat] = [0.15, 0.3, 0.45, 0.5, 0.75]
    /// Fraction of the way the user must drag to complete.
    private let completionThreshold: CGFloat = 0.70
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let circleWidth = height - (circlePadding * 2)
            let maxDrag = width - circleWidth - (circlePadding * 2)
            let circleOffset = isDone ? maxDrag : dragOffset
            
            ZStack(alignment: .leading) {
                // MARK: - Track
                Capsule()
                    .foregroundColor(isDone ? .gray.opacity(0.2) : color.opacity(0.2))
                
                // MARK: - Text (fades as the button moves)
                Text(isDone ? "Tarefa concluida!" : "Deslize para concluir")
                    .foregroundColor(.black)
                    .font(.system(size: 15))
                    .frame(maxWidth: .infinity)
                    .opacity(isDone ? 1.0 : Double(1.0 - (dragOffset / (maxDrag * 0.8))))
                
                // MARK: - Round button with the checkmark
                Circle()
                    .fill(isDone ? .titleGray : color)
                    .frame(width: circleWidth, height: circleWidth)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 20))
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    )
                    .offset(x: circleOffset)
                    .padding(circlePadding)
                
                // MARK: - Drag gesture
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                guard !isDone else { return }
                                
                                let translation = value.translation.width
                                if translation > 0 {
                                    dragOffset = min(translation, maxDrag)
                                }
                                guard maxDrag > 0 else { return }
                                let progress = dragOffset / maxDrag
                                
                                // MARK: - Haptics along the way
                                for (index, step) in progressSteps.enumerated() {
                                    if progress >= step && !reachedSteps.contains(index) {
                                        reachedSteps.insert(index)
                                        HapticsManager.impact(.light, intensity: 0.6)
                                    }
                                }
                                if progress >= completionThreshold && !reachedSteps.contains(999) {
                                    reachedSteps.insert(999)
                                    HapticsManager.impact(.heavy)
                                }
                            }
                            .onEnded { _ in
                                guard !isDone else { return }
                                
                                if dragOffset > maxDrag * 0.70 {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        dragOffset = maxDrag
                                    }
                                    
                                    HapticsManager.notify(.success)
                                    
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        action()
                                    }
                                } else {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                        dragOffset = 0
                                    }
                                    
                                    HapticsManager.impact(.light)
                                }
                            }
                    )
            }
            .animation(.easeInOut, value: isDone)
            .onChange(of: isDone) { _, newValue in
                if !newValue {
                    // if it was selected from the outside button, returns the swipe to zero
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        dragOffset = 0
                    }
                }
            }
        }
        .frame(height: height)
        // MARK: - VoiceOver
        // The swipe is replaced by a plain double tap.
        .accessibilityElement(children: .ignore)
        .voiceOverLabel(isDone ? L10n.tr("Tarefa concluída") : L10n.tr("Concluir tarefa"))
        .voiceOverHint(isDone ? "" : L10n.tr("Toque duas vezes para marcar a tarefa como concluída."))
        .voiceOverTraits(.isButton, when: !(isDone))
        // Voice Control: "Toque em Concluir" replaces the swipe.
        .voiceControlNames(isDone
            ? [L10n.tr("Tarefa concluída")]
            : [L10n.tr("Concluir"), L10n.tr("Concluir tarefa"), L10n.tr("Deslize para concluir")])
        .accessibilityAction {
            completeFromAccessibility()
        }
    }
    
    /// VoiceOver alternative to the swipe: completes the task right away.
    private func completeFromAccessibility() {
        guard !isDone else { return }
        HapticsManager.notify(.success)
        action()
        VoiceOver.announce(L10n.tr("Tarefa concluída"))
    }
}

#Preview {
    SwipeToCompleteButton(isDone: false) {
        print("Tarefa concluída!")
    }
}
