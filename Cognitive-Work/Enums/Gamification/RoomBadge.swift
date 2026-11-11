//
//  RoomBadge.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 11/11/26.
//

import Foundation

/// A badge a member unlocks by doing the chores of one of the app's default rooms
/// (``DefaultRoomsOnboarding``).
///
/// Each default room has its own ladder of badges, from the first to unlock to the last
/// (``DefaultRoomsOnboarding/badges``). A badge unlocks once the member has checked off
/// ``threshold`` chores in rooms of its kind (``RoomBadgeProgressModel``). Rooms whose chores
/// come around more often (most of the kitchen's are daily) ask for more check-offs, so every
/// ladder takes about the same time to climb.
///
/// The raw value is what CloudKit stores (``RoomBadgeProgressModel/unlocked``): it must not change.
enum RoomBadge: String, CaseIterable, Identifiable {

    // MARK: Cozinha
    case torreDeLouca
    case panoDePratoDaVo
    case chefeMasterDeDelicias

    // MARK: Quarto
    case cadeiraArara
    case oitoHorasDeSono
    case fortalezaDeTravesseiros

    // MARK: Escritório
    case cabosEmbolados
    case chuvaDePostIt
    case misterCorp

    // MARK: Sala de Estar
    case aspiradorDeFarelo
    case sofaQueEngoleControle
    case guardiaoDoControleRemoto

    // MARK: Jardim
    case samambaiaDesidratada
    case duendeDeJardim
    case visitaDeBeijaFlor

    // MARK: Varanda
    case pomboFolgado
    case cadeiraDeBalanco
    case sonecaNaRede

    // MARK: Banheiro
    case monstroDoRalo
    case espelhoEspelhoMeu
    case fadaDoBanhoPremium

    // MARK: Área de Serviço
    case meiaSemPar
    case varalDeBandeirinha
    case cheirinhoDeRoupaLimpa

    // MARK: Despensa
    case paoMofado
    case poteDeSorveteComFeijao
    case dataDeValidadeInfinita

    // MARK: Garagem
    case quartinhoDaBagunca
    case bikeDeRodinha
    case brilhandoNoLavaJato

    // MARK: Lavabo
    case saboneteDeEnfeite
    case aromatizanteDeCheiroDePonei

    // MARK: - Identity

    /// Stable identity used by `ForEach`.
    var id: String { rawValue }

    // MARK: - Room

    /// The kind of room whose chores unlock the badge.
    var room: DefaultRoomsOnboarding {
        switch self {
        case .torreDeLouca, .panoDePratoDaVo, .chefeMasterDeDelicias: .kitchen
        case .cadeiraArara, .oitoHorasDeSono, .fortalezaDeTravesseiros: .bedroom
        case .cabosEmbolados, .chuvaDePostIt, .misterCorp: .homeOffice
        case .aspiradorDeFarelo, .sofaQueEngoleControle, .guardiaoDoControleRemoto: .livingRoom
        case .samambaiaDesidratada, .duendeDeJardim, .visitaDeBeijaFlor: .garden
        case .pomboFolgado, .cadeiraDeBalanco, .sonecaNaRede: .balcony
        case .monstroDoRalo, .espelhoEspelhoMeu, .fadaDoBanhoPremium: .bathroom
        case .meiaSemPar, .varalDeBandeirinha, .cheirinhoDeRoupaLimpa: .laundryRoom
        case .paoMofado, .poteDeSorveteComFeijao, .dataDeValidadeInfinita: .pantry
        case .quartinhoDaBagunca, .bikeDeRodinha, .brilhandoNoLavaJato: .garage
        case .saboneteDeEnfeite, .aromatizanteDeCheiroDePonei: .powderRoom
        }
    }

    /// Chores of ``room`` the member has to check off to unlock the badge.
    ///
    /// Worked out from how often the room's default chores come around, so that someone doing
    /// about half of them gets the first badge of a room in about two weeks, the second in about
    /// two months and the last in about six months.
    var threshold: Int {
        switch self {
        case .torreDeLouca: 25
        case .panoDePratoDaVo: 100
        case .chefeMasterDeDelicias: 300

        case .cadeiraArara: 20
        case .oitoHorasDeSono: 75
        case .fortalezaDeTravesseiros: 220

        case .cabosEmbolados: 12
        case .chuvaDePostIt: 50
        case .misterCorp: 150

        case .aspiradorDeFarelo: 12
        case .sofaQueEngoleControle: 45
        case .guardiaoDoControleRemoto: 135

        case .samambaiaDesidratada: 10
        case .duendeDeJardim: 40
        case .visitaDeBeijaFlor: 125

        case .pomboFolgado: 10
        case .cadeiraDeBalanco: 40
        case .sonecaNaRede: 120

        case .monstroDoRalo: 7
        case .espelhoEspelhoMeu: 27
        case .fadaDoBanhoPremium: 80

        case .meiaSemPar: 5
        case .varalDeBandeirinha: 20
        case .cheirinhoDeRoupaLimpa: 60

        case .paoMofado: 5
        case .poteDeSorveteComFeijao: 20
        case .dataDeValidadeInfinita: 60

        case .quartinhoDaBagunca: 2
        case .bikeDeRodinha: 8
        case .brilhandoNoLavaJato: 25

        case .saboneteDeEnfeite: 15
        case .aromatizanteDeCheiroDePonei: 80
        }
    }

    // MARK: - Presentation

    /// The badge's name, in the app's current language.
    var title: String {
        switch self {
        case .torreDeLouca: L10n.tr("Torre de Louça")
        case .panoDePratoDaVo: L10n.tr("Pano de Prato da Vó")
        case .chefeMasterDeDelicias: L10n.tr("Chefe Master de Delícias")

        case .cadeiraArara: L10n.tr("Cadeira Arara")
        case .oitoHorasDeSono: L10n.tr("8 Horas de Sono")
        case .fortalezaDeTravesseiros: L10n.tr("Fortaleza Impenetrável de Travesseiros")

        case .cabosEmbolados: L10n.tr("Cabos Embolados")
        case .chuvaDePostIt: L10n.tr("Chuva de Post-it")
        case .misterCorp: L10n.tr("Mister Corp")

        case .aspiradorDeFarelo: L10n.tr("Aspirador de Farelo")
        case .sofaQueEngoleControle: L10n.tr("Sofá que Engole Controle")
        case .guardiaoDoControleRemoto: L10n.tr("Guardião do Controle Remoto")

        case .samambaiaDesidratada: L10n.tr("Samambaia Desidratada")
        case .duendeDeJardim: L10n.tr("Duende de Jardim")
        case .visitaDeBeijaFlor: L10n.tr("Visita de Beija-Flor")

        case .pomboFolgado: L10n.tr("Pombo Folgado")
        case .cadeiraDeBalanco: L10n.tr("Cadeira de Balanço")
        case .sonecaNaRede: L10n.tr("Soneca na Rede")

        case .monstroDoRalo: L10n.tr("Monstro do Ralo")
        case .espelhoEspelhoMeu: L10n.tr("Espelho Espelho Meu")
        case .fadaDoBanhoPremium: L10n.tr("Fada do Banho Premium")

        case .meiaSemPar: L10n.tr("Meia Sem Par")
        case .varalDeBandeirinha: L10n.tr("Varal de Bandeirinha")
        case .cheirinhoDeRoupaLimpa: L10n.tr("Cheirinho de Roupa Limpa")

        case .paoMofado: L10n.tr("Pão Mofado")
        case .poteDeSorveteComFeijao: L10n.tr("Pote de Sorvete com Feijão")
        case .dataDeValidadeInfinita: L10n.tr("Data de Validade Infinita")

        case .quartinhoDaBagunca: L10n.tr("Quartinho da Bagunça")
        case .bikeDeRodinha: L10n.tr("Bike de Rodinha")
        case .brilhandoNoLavaJato: L10n.tr("Brilhando no Lava-Jato")

        case .saboneteDeEnfeite: L10n.tr("Sabonete de Enfeite")
        case .aromatizanteDeCheiroDePonei: L10n.tr("Aromatizante de Cheiro de Pônei")
        }
    }

    /// Name of the badge's artwork in the asset catalog (`Assets.xcassets/Badges`).
    ///
    /// Badges without artwork yet fall back to their room's icon (see ``RoomBadgeIcon``).
    var imageName: String { "badge_\(rawValue)" }
}

// MARK: - Badges of a room

extension DefaultRoomsOnboarding {
    /// The room's badges, from the first to unlock to the last. Not every room has the same number.
    var badges: [RoomBadge] {
        RoomBadge.allCases
            .filter { $0.room == self }
            .sorted { $0.threshold < $1.threshold }
    }
}
