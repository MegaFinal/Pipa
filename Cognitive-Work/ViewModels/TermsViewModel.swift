//
//  TermsViewModel.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 09/10/26.
//

import Foundation

/// Whether the user accepted the current Terms of Use, and what the terms screens show.
@MainActor
@Observable
final class TermsViewModel {

    /// What the user decided about the current terms.
    enum Decision: Equatable {
        /// Not decided yet: the terms screen shows.
        case pending
        /// Accepted the current version.
        case accepted
        /// Declined: the goodbye screen shows.
        case declined
    }

    /// The terms being shown.
    let terms: TermsOfUse

    /// The user's decision.
    private(set) var decision: Decision

    /// `true` while the "accept?" confirmation is open.
    var isConfirmingAcceptance = false

    /// Where the decision is saved.
    @ObservationIgnored private let defaults: UserDefaults

    /// `UserDefaults` keys of the decision.
    private enum Keys {
        static let acceptedVersion = "termsAcceptedVersion"
        static let declined = "termsDeclined"
    }

    /// Loads the saved decision. Accepting an older version counts as not decided.
    init(terms: TermsOfUse = .current, defaults: UserDefaults = .standard) {
        self.terms = terms
        self.defaults = defaults

        if defaults.string(forKey: Keys.acceptedVersion) == terms.version {
            decision = .accepted
        } else if defaults.bool(forKey: Keys.declined) {
            decision = .declined
        } else {
            decision = .pending
        }
    }

    /// Whether the terms screen must show.
    var isShowingTerms: Bool { decision == .pending }

    // MARK: - Texts

    /// The screen's title, translated.
    var title: String { L10n.tr("Termos de Uso") }

    /// Version and last update date, translated.
    var subtitle: String {
        L10n.tr("Versão \(terms.version) · Última atualização: \(terms.lastUpdated)")
    }

    /// The confirmation's title, translated.
    var confirmationTitle: String { L10n.tr("Termos de Uso") }

    /// The confirmation's message, translated.
    var confirmationMessage: String {
        L10n.tr("Ao tocar em Concordar, você aceita os Termos de Uso do \(terms.appName).")
    }

    /// Title of the goodbye screen shown after declining.
    var farewellTitle: String { L10n.tr("Tudo bem, até logo!") }

    /// Message of the goodbye screen shown after declining.
    var farewellMessage: String {
        L10n.tr("Para usar o \(terms.appName) é preciso aceitar os Termos de Uso. Se mudar de ideia, é só rever os termos: a casa vai estar te esperando.")
    }

    // MARK: - Actions

    /// Opens the "accept?" confirmation.
    func requestAcceptance() {
        isConfirmingAcceptance = true
    }

    /// Saves that the user accepted the current version.
    func accept() {
        defaults.set(terms.version, forKey: Keys.acceptedVersion)
        defaults.set(false, forKey: Keys.declined)
        decision = .accepted
    }

    /// Saves that the user declined.
    func decline() {
        defaults.removeObject(forKey: Keys.acceptedVersion)
        defaults.set(true, forKey: Keys.declined)
        decision = .declined
    }

    /// From the farewell screen: shows the terms again.
    func reviewTerms() {
        decision = .pending
    }
}
