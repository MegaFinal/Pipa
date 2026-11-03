//
//  CarouselCardFrame.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 18/08/26.
//

import SwiftUI
import CloudKit

/// One card of the chores carousel, with its two faces: the chore's front card and, when
/// flipped, its details card. Handles the flip, the focus zoom and which face VoiceOver reads.
struct CarouselCardFrame: View {
    /// The chore on the card.
    let chore: ChoreModel
    /// The specific occurrence this card represents, when it comes from the list
    /// layout. `nil` in the grid, where cards stand for the chore as a whole.
    var recurrentAssignment: RecurrentAssignmentModel?
    
    /// The chores screen's view model.
    let carouselViewModel: CarouselViewModel
    /// Shared namespace for the card's matched-geometry animations.
    let namespace: Namespace.ID
    
    
    /// Whether the card is open in the middle of the screen (it grows).
    var isFocused: Bool = false
    /// The card's flip angle, in degrees.
    var rotation: Double = 0
    /// Whether the back face (details) is the one showing.
    var isShowingBack: Bool = false
    /// Runs when the details card's close button is tapped. `nil` closes the card focused in
    /// the carousel (a card opened from a notification passes its own).
    var onClose: (() -> Void)?
    /// How fast the faces cross-fade during the flip.
    private let fadeDuration: Double = 0.03
    
    var body: some View {
        ZStack {
            // MARK: - Front face: the chore card
            ChoreCarouselCard(chore: chore, namespace: namespace, carouselViewModel: carouselViewModel)
                .opacity(isShowingBack ? 0 : 1)
                .scaleEffect(
                    x: isFocused ? (0.88 / 0.72) : 1.0,
                    y: isFocused ? (0.65 / 0.47) : 1.0
                )
                // Only the face currently shown is read by VoiceOver.
                .accessibilityHidden(isShowingBack)

            // MARK: - Back face: the details card (mirrored so it reads correctly after the flip)
            if isShowingBack || rotation != 0 {
                ChoreDetailsCard(
                    chore: chore,
                    recurrentAssignment: recurrentAssignment,
                    carouselViewModel: carouselViewModel,
                    isShowingBack: isShowingBack,
                    onClose: onClose
                )
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(isShowingBack ? 1 : 0)
                .frame(width: 0, height: 0)
                .scaleEffect(
                    x: isFocused ? 1.0 : (0.72 / 0.88),
                    y: isFocused ? 1.0 : (0.47 / 0.65)
                )
                .transition(.identity)
                .accessibilityHidden(!isShowingBack)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: isFocused)
        .animation(.easeInOut(duration: fadeDuration), value: isShowingBack)
        .rotation3DEffect(.degrees(rotation), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
    }
}
