//
//  GamificationViewModel+Tour.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 09/11/26.
//

import Foundation

/// The components of the rewards tab the first-visit tour points at (``CoachMarkStep/id``).
enum GamificationTourStop {
    static let coins = "gamification.tour.coins"
    static let ranking = "gamification.tour.ranking"
    static let availableCoupons = "gamification.tour.availableCoupons"
    static let myCoupons = "gamification.tour.myCoupons"
}

extension GamificationViewModel {

    /// Where the tour remembers it was seen (``CoachMarkTour`` adds its own prefix).
    static let tourStorageKey = "gamification.coachMarksSeen"

    /// The tour's steps, in screen order. The coupon steps only when the house has coupons:
    /// otherwise their sections aren't on screen.
    var tourSteps: [CoachMarkStep] {
        var steps = [
            CoachMarkStep(
                id: GamificationTourStop.coins,
                title: L10n.tr("Suas moedas"),
                message: L10n.tr("Você ganha moedas fazendo tarefas e contribuindo com a casa. Use para comprar cupons.")
            ),
            CoachMarkStep(
                id: GamificationTourStop.ranking,
                title: L10n.tr("Ranking da casa"),
                message: L10n.tr("Cada tarefa feita rende pontos e faz sua pipa subir no ranking. Arraste para ver todos os rankings.")
            )
        ]
        if !catalog.entries.isEmpty {
            steps.append(CoachMarkStep(
                id: GamificationTourStop.availableCoupons,
                title: L10n.tr("Cupons disponíveis"),
                message: L10n.tr("Com um cupom, você fica livre da tarefa dele na próxima divisão. Toque em um para comprá-lo.")
            ))
            steps.append(CoachMarkStep(
                id: GamificationTourStop.myCoupons,
                title: L10n.tr("Seus cupons"),
                message: L10n.tr("Os cupons que você comprou ficam aqui até serem usados na próxima divisão.")
            ))
        }
        return steps
    }

    /// Starts the tour the first time the screen opens, once its data is in place (so the coupon
    /// sections it points at are already on screen).
    func startTourIfNeeded() {
        guard hasLoaded else { return }
        tour.startIfNeeded(with: tourSteps)
    }
}
