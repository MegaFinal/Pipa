//
//  UserProfileViewModel+Accessibility.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 09/10/26.
//

import Foundation

extension UserProfileViewModel {

    /// The profile header as one VoiceOver sentence: "Dayô, Nível 1, 120 pontos, 30 moedas".
    var accessibilityProfileSummary: String {
        guard let user else { return L10n.tr("Carregando perfil") }

        let points = user.points == 1 ? L10n.tr("1 ponto") : L10n.tr("\(user.points) pontos")
        let coins = user.coins == 1 ? L10n.tr("1 moeda") : L10n.tr("\(user.coins) moedas")
        return [user.name, user.tier.displayName, points, coins]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// Short names Voice Control users can say for the profile header ("Dayô", "Perfil"),
    /// instead of the whole VoiceOver sentence.
    var accessibilityProfileInputLabels: [String] {
        [user?.name ?? "", L10n.tr("Perfil")].filter { !$0.isEmpty }
    }
}
