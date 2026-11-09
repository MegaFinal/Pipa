//
//  CoachMarkOverlay.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 09/11/26.
//

import SwiftUI

// MARK: - Anchors

/// Where each component of a tour is, by ``CoachMarkStep/id``.
struct CoachMarkAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {

    /// Marks this view as the component a tour step (``CoachMarkStep/id``) points at. Also gives
    /// it that id, so the tour can scroll to it.
    func coachMarkAnchor(_ id: String) -> some View {
        self
            .anchorPreference(key: CoachMarkAnchorKey.self, value: .bounds) { [id: $0] }
            .id(id)
    }

    /// Draws `tour`'s current step over this view: the screen dimmed except for the component,
    /// and a pop-up explaining it. Apply it to the screen's `ScrollView`, which scrolls to each
    /// component as the tour reaches it.
    func coachMarks(_ tour: CoachMarkTour) -> some View {
        modifier(CoachMarksModifier(tour: tour))
    }
}

/// See ``SwiftUI/View/coachMarks(_:)``.
private struct CoachMarksModifier: ViewModifier {
    let tour: CoachMarkTour

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        ScrollViewReader { scroll in
            content
                .overlayPreferenceValue(CoachMarkAnchorKey.self) { anchors in
                    GeometryReader { proxy in
                        if let step = tour.currentStep, let anchor = anchors[step.id] {
                            CoachMarkOverlay(
                                step: step,
                                target: proxy[anchor],
                                isLastStep: tour.isOnLastStep,
                                onNext: { withAnimation(animation) { tour.next() } },
                                onClose: { withAnimation(animation) { tour.finish() } }
                            )
                            .transition(.opacity)
                        }
                    }
                    .ignoresSafeArea()
                    .animation(animation, value: tour.currentStep?.id)
                }
                // Brings each component on screen (the last ones may be below the fold).
                .onChange(of: tour.currentStep?.id) { _, id in
                    guard let id else { return }
                    withAnimation(animation) { scroll.scrollTo(id, anchor: .center) }
                }
        }
    }

    private var animation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.35)
    }
}

// MARK: - Overlay

/// One step of a tour: the screen dimmed with a hole around the component, a white ring around
/// it, and the pop-up below it (or above it, when the component is in the lower half).
struct CoachMarkOverlay: View {
    let step: CoachMarkStep
    /// The component's frame, in this view's coordinates.
    let target: CGRect
    let isLastStep: Bool
    let onNext: () -> Void
    let onClose: () -> Void

    /// Space between the component and the ring.
    private let ringPadding: CGFloat = 8
    private let cornerRadius: CGFloat = 28
    /// Space between the ring and the pop-up.
    private let gap: CGFloat = 26

    private var spotlight: CGRect { target.insetBy(dx: -ringPadding, dy: -ringPadding) }

    var body: some View {
        GeometryReader { proxy in
            let showsBelow = spotlight.midY < proxy.size.height / 2

            ZStack {
                // MARK: - Dimmed screen with a hole on the component (blocks touches)
                SpotlightShape(hole: spotlight, cornerRadius: cornerRadius)
                    .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .accessibilityHidden(true)

                // MARK: - White ring and the dot that links it to the pop-up
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: spotlight.width, height: spotlight.height)
                    .position(x: spotlight.midX, y: spotlight.midY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                Circle()
                    .fill(Color.white)
                    .frame(width: 10, height: 10)
                    .position(x: spotlight.midX, y: showsBelow ? spotlight.maxY + gap / 2 : spotlight.minY - gap / 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                // MARK: - Pop-up
                CoachMarkCard(
                    title: step.title,
                    message: step.message,
                    buttonTitle: isLastStep ? L10n.tr("Entendi") : L10n.tr("Próximo"),
                    onNext: onNext,
                    onClose: onClose
                )
                .frame(maxWidth: 360)
                .padding(.horizontal, 24)
                .padding(.top, showsBelow ? spotlight.maxY + gap : 0)
                .padding(.bottom, showsBelow ? 0 : proxy.size.height - spotlight.minY + gap)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: showsBelow ? .top : .bottom)
                .id(step.id)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
    }
}

/// The whole rectangle minus a rounded hole, for an even-odd fill. Animates the hole between steps.
private struct SpotlightShape: Shape {
    var hole: CGRect
    var cornerRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(hole.minX, hole.minY), AnimatablePair(hole.width, hole.height)) }
        set {
            hole = CGRect(
                x: newValue.first.first,
                y: newValue.first.second,
                width: newValue.second.first,
                height: newValue.second.second
            )
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRoundedRect(in: hole, cornerSize: CGSize(width: cornerRadius, height: cornerRadius), style: .continuous)
        return path
    }
}

// MARK: - Pop-up

/// The white pop-up of a step: title, close button, message and a black button.
struct CoachMarkCard: View {
    let title: String
    let message: String
    let buttonTitle: String
    let onNext: () -> Void
    let onClose: () -> Void

    /// VoiceOver lands on the pop-up as each step shows.
    @AccessibilityFocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Text(verbatim: title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.black)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($isFocused)

                Spacer(minLength: 0)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, -4)
                .padding(.trailing, -6)
                .voiceOverLabel(L10n.tr("Fechar dicas"))
            }

            Text(verbatim: message)
                .font(.system(size: 16))
                .foregroundStyle(.subTitleGray)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onNext) {
                Text(verbatim: buttonTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.black))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .onAppear { isFocused = true }
    }
}

// MARK: - Previews

#Preview("Pop-up") {
    CoachMarkCard(
        title: "Suas moedas",
        message: "Você ganha moedas fazendo tarefas e contribuindo com a casa. Use para comprar cupons.",
        buttonTitle: "Próximo",
        onNext: {},
        onClose: {}
    )
    .padding(24)
    .background(Color.gray)
}

#Preview("Tour") {
    CoachMarkPreview()
}

/// Preview host: three components and a tour over them that never gets remembered.
private struct CoachMarkPreview: View {
    @State private var tour = CoachMarkTour(storageKey: "preview.tour", remembersCompletion: false)

    var body: some View {
        ScrollView {
            VStack(spacing: 40) {
                Capsule().fill(Color.choreYellow).frame(width: 110, height: 44)
                    .coachMarkAnchor("a")
                RoundedRectangle(cornerRadius: 28).fill(Color.choreBlue).frame(height: 300)
                    .coachMarkAnchor("b")
                RoundedRectangle(cornerRadius: 20).fill(Color.choreGreen).frame(height: 160)
                    .coachMarkAnchor("c")
            }
            .padding(30)
        }
        .coachMarks(tour)
        .onAppear {
            tour.startIfNeeded(with: [
                CoachMarkStep(id: "a", title: "Primeiro", message: "Pop-up abaixo do componente."),
                CoachMarkStep(id: "b", title: "Segundo", message: "O destaque anima de um componente para o outro."),
                CoachMarkStep(id: "c", title: "Terceiro", message: "Na metade de baixo, o pop-up fica acima.")
            ])
        }
    }
}
