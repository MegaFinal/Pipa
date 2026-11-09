//
//  CoachMarkTour.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 09/11/26.
//

import Foundation

/// One stop of a coach-mark tour: which component it points at and what it says about it.
struct CoachMarkStep: Identifiable, Equatable {
    /// The component's anchor (see ``SwiftUI/View/coachMarkAnchor(_:)``); also its scroll id.
    let id: String
    /// Bold title of the pop-up.
    let title: String
    /// One or two sentences explaining the component.
    let message: String
}

/// A short tour of pop-ups pointing at a screen's components, shown the first time the user
/// opens the screen.
///
/// The screen gives the steps (only for components that are on screen), the overlay
/// (``SwiftUI/View/coachMarks(_:)``) draws the current one, and finishing or closing the tour
/// remembers it, so it never shows again.
@MainActor
@Observable
final class CoachMarkTour {

    /// The steps of the tour that is running.
    private(set) var steps: [CoachMarkStep] = []

    /// Position of the step on screen, or `nil` when the tour isn't running.
    private(set) var currentIndex: Int?

    /// `UserDefaults` key that remembers the tour was seen (``storagePrefix`` + the tour's key).
    @ObservationIgnored
    private let storageKey: String

    /// Prefix of every tour's `UserDefaults` key, so ``resetAll()`` finds them.
    private static let storagePrefix = "coachMarks.seen."

    /// `false` in previews, so the tour shows every time.
    @ObservationIgnored
    private let remembersCompletion: Bool

    /// - Parameters:
    ///   - storageKey: Where to remember that the tour was seen.
    ///   - remembersCompletion: Pass `false` to show it again every time (previews).
    init(storageKey: String, remembersCompletion: Bool = true) {
        self.storageKey = Self.storagePrefix + storageKey
        self.remembersCompletion = remembersCompletion
    }

    /// Forgets every tour seen on this device, so they all show again. Called when the account
    /// is deleted: whoever signs up next is new to the app, even on the same device and Apple ID.
    static func resetAll() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(storagePrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - State

    /// The step on screen, or `nil` when the tour isn't running.
    var currentStep: CoachMarkStep? {
        currentIndex.flatMap { steps.indices.contains($0) ? steps[$0] : nil }
    }

    /// Whether the step on screen is the last one ("Entendi" instead of "Próximo").
    var isOnLastStep: Bool {
        currentIndex == steps.count - 1
    }

    /// Whether the user already went through (or closed) the tour.
    var wasSeen: Bool {
        remembersCompletion && UserDefaults.standard.bool(forKey: storageKey)
    }

    // MARK: - Actions

    /// Starts the tour with `steps`, unless it was already seen or is running.
    func startIfNeeded(with steps: [CoachMarkStep]) {
        guard !wasSeen, currentIndex == nil, !steps.isEmpty else { return }
        self.steps = steps
        currentIndex = 0
    }

    /// Goes to the next step, or finishes the tour on the last one.
    func next() {
        guard let currentIndex else { return }
        if currentIndex + 1 < steps.count {
            self.currentIndex = currentIndex + 1
        } else {
            finish()
        }
    }

    /// Ends the tour (last step or the close button) and remembers it was seen.
    func finish() {
        currentIndex = nil
        steps = []
        if remembersCompletion {
            UserDefaults.standard.set(true, forKey: storageKey)
        }
    }
}
