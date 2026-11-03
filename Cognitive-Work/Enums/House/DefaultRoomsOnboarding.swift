//
//  Room.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 28/08/26.
//

import Foundation

/// A room of the house used to suggest a starting set of chores during onboarding.
///
/// Each case exposes a ``displayName`` for the UI and a ``defaultChores`` list
/// with the chores most households run for that room. The suggestions are meant
/// as a starting point: the user still toggles ``ChoreDTO/isSelected`` on the
/// selection screen before anything is persisted.
///
/// Example:
/// ```swift
/// let chores = DefaultRoomsOnboarding.kitchen.defaultChores
/// // -> [Lavar a louça, Limpar a bancada e o fogão, ...]
/// ```
enum DefaultRoomsOnboarding: String, CaseIterable, Identifiable {

    /// The raw value is the room's Portuguese name, which is also saved as the room's `kind`.
    /// A bedroom.
    case bedroom = "Quarto"
    /// The living room.
    case livingRoom = "Sala de Estar"
    /// The laundry area.
    case laundryRoom = "Área de Serviço"
    /// The kitchen.
    case kitchen = "Cozinha"
    /// A bathroom.
    case bathroom = "Banheiro"
    /// A home office.
    case homeOffice = "Escritório"
    /// A balcony.
    case balcony = "Varanda"
    /// The pantry.
    case pantry = "Despensa"
    /// A small guest bathroom (toilet and sink only).
    case powderRoom = "Lavabo"
    /// The garage.
    case garage = "Garagem"
    /// The garden.
    case garden = "Jardim"

    // MARK: - Identity

    /// Stable identity used by `ForEach` and `Picker`.
    var id: String { rawValue }
    
    // MARK: - Room
    
    /// The order rooms are offered in on the room selection screen.
    static let onboardingOrder: [DefaultRoomsOnboarding] = [
        .bedroom, .livingRoom, .kitchen, .laundryRoom, .bathroom, .balcony,
        .homeOffice, .pantry, .powderRoom, .garage, .garden
    ]
    
    /// The room type a saved room was created from, matched by its `kind` (e.g. `"Quarto"` for
    /// "Quarto 2") or, for rooms saved before `kind` existed, by its name.
    init?(kind: String?, name: String) {
        self.init(rawValue: kind ?? name)
    }
    
    /// Name of the room's icon in the `ChoresSymbols/DefaultRooms` asset folder.
    var symbol: String {
        switch self {
        case .bedroom: "bed.stripes"
        case .livingRoom: "sofa"
        case .laundryRoom: "clothes.line.stripes"
        case .kitchen: "stove.pans"
        case .bathroom: "toilet"
        case .homeOffice: "computer"
        case .balcony: "balcony.plastic.chair"
        case .pantry: "pantry"
        case .powderRoom: "sink"
        case .garage: "garage.car"
        case .garden: "snake.plant"
        }
    }
    
    /// Palette color for this room (see ``RoomColor``).
    var color: RoomColor {
        switch self {
        case .bathroom, .powderRoom, .laundryRoom: .blue
        case .livingRoom, .garage: .orange
        case .kitchen, .pantry: .yellow
        case .bedroom, .homeOffice: .purple
        case .balcony, .garden: .green
        }
    }
    
    /// Room representation used by the selection screen and the onboarding chore previews.
    ///
    /// The single source of truth for a default room's name, symbol and color: the selection
    /// screen (``OnboardingViewModel/availableRooms``) and the saved ``RoomModel`` both come
    /// from here, so they can't drift apart again.
    var roomDTO: RoomDTO {
        RoomDTO(name: rawValue, symbol: symbol, color: color)
    }

    // MARK: - Default Chores

    /// Chores suggested for this room during onboarding.
    ///
    /// > Important: ``ChoreDTO`` is a reference type, so every access builds a
    /// > brand new batch of instances. Store the result once (in the view model
    /// > or in `@State`) instead of calling this inside `body`, otherwise the
    /// > toggles reset on each redraw.
    var defaultChores: [ChoreDTO] {
        switch self {
        case .bedroom:
            DefaultRoomsOnboarding.bedroomChores
        case .livingRoom:
            DefaultRoomsOnboarding.livingRoomChores
        case .laundryRoom:
            DefaultRoomsOnboarding.laundryRoomChores
        case .kitchen:
            DefaultRoomsOnboarding.kitchenChores
        case .bathroom:
            DefaultRoomsOnboarding.bathroomChores
        case .homeOffice:
            DefaultRoomsOnboarding.homeOfficeChores
        case .balcony:
            DefaultRoomsOnboarding.balconyChores
        case .pantry:
            DefaultRoomsOnboarding.pantryChores
        case .powderRoom:
            DefaultRoomsOnboarding.powderRoomChores
        case .garage:
            DefaultRoomsOnboarding.garageChores
        case .garden:
            DefaultRoomsOnboarding.gardenChores
        }
    }

}

// MARK: - Chore Catalog

private extension DefaultRoomsOnboarding {

    /// Suggested chores for a ``bedroom``.
    static var bedroomChores: [ChoreDTO] {
        let room = DefaultRoomsOnboarding.bedroom.roomDTO
        return [
            ChoreDTO(
                name: "Arrumar a cama",
                description: "Esticar o lençol, ajeitar o edredom e os travesseiros.",
                frequency: .daily,
                duration: 5,
                priorityTag: .low,
                room: room
            ),
            ChoreDTO(
                name: "Trocar lençóis",
                description: "Trocar lençol, fronhas e capa do edredom e levar o usado para lavar.",
                frequency: .weekly,
                duration: 15,
                priorityTag: .medium,
                room: room
            ),
            ChoreDTO(
                name: "Tirar o pó",
                description: "Passar pano nas superfícies do criado-mudo, cômoda e prateleiras.",
                frequency: .weekly,
                duration: 10,
                priorityTag: .low,
                room: room
            ),
            ChoreDTO(
                name: "Limpar o chão",
                description: "Aspirar embaixo da cama, varrer e passar pano no quarto todo.",
                frequency: .weekly,
                duration: 20,
                priorityTag: .medium,
                room: room
            ),
            ChoreDTO(
                name: "Organizar armário",
                description: "Dobrar e guardar as roupas, separar o que não usa mais.",
                frequency: .monthly,
                duration: 40,
                priorityTag: .low,
                room: room
            ),
            ChoreDTO(
                name: "Arejar o quarto",
                description: "Abrir janelas e cortinas para renovar o ar do quarto.",
                frequency: .daily,
                duration: 5,
                priorityTag: .low,
                room: room
            )
        ]
    }

    /// Suggested chores for a ``livingRoom``.
    static var livingRoomChores: [ChoreDTO] {
        let room = DefaultRoomsOnboarding.livingRoom.roomDTO
        return [
            ChoreDTO(
                name: "Organizar a sala",
                description: "Guardar objetos fora do lugar, ajeitar almofadas e mantas.",
                frequency: .daily,
                duration: 10,
                priorityTag: .low,
                room: room,
                
            ),
            ChoreDTO(
                name: "Tirar pó",
                description: "Limpar mesa de centro, estantes, quadros e rodapés.",
                frequency: .weekly,
                duration: 15,
                priorityTag: .low,
                room: room
            ),
            ChoreDTO(
                name: "Aspirar sofá",
                description: "Aspirar entre as almofadas do sofá e os tapetes da sala.",
                frequency: .weekly,
                duration: 20,
                priorityTag: .medium,
                room: room
            ),
            ChoreDTO(
                name: "Varrer o chão",
                description: "Limpar o piso da sala inteira, incluindo cantos e embaixo dos móveis.",
                frequency: .weekly,
                duration: 20,
                priorityTag: .medium,
                room: room
            ),
            ChoreDTO(
                name: "Limpar TV e rack",
                description: "Passar pano de microfibra na tela, no rack e nos controles.",
                frequency: .monthly,
                duration: 10,
                priorityTag: .low,
                room: room
            ),
            ChoreDTO(
                name: "Limpar janelas",
                description: "Lavar os vidros e limpar os trilhos das janelas.",
                frequency: .monthly,
                duration: 30,
                priorityTag: .low,
                room: room
            )
        ]
    }

    /// Suggested chores for a ``laundryRoom``.
    static var laundryRoomChores: [ChoreDTO] {
        let room = DefaultRoomsOnboarding.laundryRoom.roomDTO
        return [
            ChoreDTO(
                name: "Lavar roupas",
                description: "Separar por cor e tecido e colocar na máquina.",
                frequency: .weekly,
                duration: 30,
                priorityTag: .high,
                room: room
            ),
            ChoreDTO(
                name: "Estender roupas",
                description: "Pendurar no varal e recolher assim que secar.",
                frequency: .weekly,
                duration: 15,
                priorityTag: .medium,
                room: room
            ),
            ChoreDTO(
                name: "Dobrar e guardar",
                description: "Dobrar as peças limpas e distribuir nos armários.",
                frequency: .weekly,
                duration: 40,
                priorityTag: .medium,
                room: room
            ),
            ChoreDTO(
                name: "Passar roupa",
                description: "Passar as peças que precisam e deixá-las prontas para guardar.",
                frequency: .weekly,
                duration: 30,
                priorityTag: .low,
                room: room
            ),
            ChoreDTO(
                name: "Limpar o tanque",
                description: "Esfregar o tanque, limpar o filtro e a borracha da máquina.",
                frequency: .monthly,
                duration: 20,
                priorityTag: .low,
                room: room
            ),
            ChoreDTO(
                name: "Repor produtos",
                description: "Conferir o estoque, repor o que acabou e arrumar as prateleiras.",
                frequency: .monthly,
                duration: 15,
                priorityTag: .low,
                room: room
            )
        ]
    }

    /// Suggested chores for a ``kitchen``.
    static var kitchenChores: [ChoreDTO] {
        let room = DefaultRoomsOnboarding.kitchen.roomDTO
        return [
            ChoreDTO(
                name: "Lavar a louça",
                description: "Lavar, secar e guardar pratos, panelas e talheres.",
                frequency: .daily,
                duration: 20,
                priorityTag: .high,
                room: room
            ),
            ChoreDTO(
                name: "Limpar fogão",
                description: "Passar pano na pia, na bancada e tirar a gordura do fogão.",
                frequency: .daily,
                duration: 10,
                priorityTag: .high,
                room: room
            ),
            ChoreDTO(
                name: "Tirar o lixo",
                description: "Trocar o saco e levar o lixo para fora.",
                frequency: .daily,
                duration: 5,
                priorityTag: .high,
                room: room
            ),
            ChoreDTO(
                name: "Varrer o chão",
                description: "Limpar o piso da cozinha, incluindo embaixo da mesa e dos armários.",
                frequency: .weekly,
                duration: 20,
                priorityTag: .medium,
                room: room
            ),
            ChoreDTO(
                name: "Limpar geladeira",
                description: "Descartar alimentos vencidos e higienizar as prateleiras e gavetas.",
                frequency: .monthly,
                duration: 30,
                priorityTag: .medium,
                room: room
            ),
            ChoreDTO(
                name: "Repor mantimentos",
                description: "Conferir validades, repor o que acabou e reorganizar as prateleiras.",
                frequency: .monthly,
                duration: 25,
                priorityTag: .low,
                room: room
            ),
            ChoreDTO(
                name: "Limpar micro-ondas",
                description: "Limpar por dentro e por fora com pano úmido e detergente neutro.",
                frequency: .weekly,
                duration: 10,
                priorityTag: .low,
                room: room
            )
        ]
    }

    /// Suggested chores for a ``bathroom``.
    static var bathroomChores: [ChoreDTO] {
        let room = DefaultRoomsOnboarding.bathroom.roomDTO
        return [
            ChoreDTO(
                name: "Limpar o vaso",
                description: "Escovar por dentro, desinfetar o assento e a parte externa.",
                frequency: .weekly,
                duration: 10,
                priorityTag: .high,
                room: room
            ),
            ChoreDTO(
                name: "Limpar a pia",
                description: "Esfregar a cuba, a torneira e deixar o espelho sem manchas.",
                frequency: .weekly,
                duration: 10,
                priorityTag: .medium,
                room: room
            ),
            ChoreDTO(
                name: "Limpar o box",
                description: "Tirar o limo dos azulejos e o acúmulo de sabão do vidro do box.",
                frequency: .weekly,
                duration: 20,
                priorityTag: .medium,
                room: room
            ),
            ChoreDTO(
                name: "Trocar toalhas",
                description: "Recolher as toalhas usadas e pendurar as limpas.",
                frequency: .weekly,
                duration: 5,
                priorityTag: .medium,
                room: room
            ),
            ChoreDTO(
                name: "Repor produtos",
                description: "Conferir papel higiênico, sabonete e shampoo e repor o que faltar.",
                frequency: .weekly,
                duration: 5,
                priorityTag: .low,
                room: room
            ),
            ChoreDTO(
                name: "Lavar o chão",
                description: "Esfregar o piso com desinfetante e desentupir o ralo.",
                frequency: .monthly,
                duration: 20,
                priorityTag: .low,
                room: room
            ),
            ChoreDTO(
                name: "Esvaziar lixeira",
                description: "Trocar o saco da lixeira e levar o lixo para fora.",
                frequency: .weekly,
                duration: 5,
                priorityTag: .medium,
                room: room
            )
        ]
    }

    /// Suggested chores for a ``homeOffice``.
    static var homeOfficeChores: [ChoreDTO] {
        let room = DefaultRoomsOnboarding.homeOffice.roomDTO
        return [
            ChoreDTO(
                name: "Organizar mesa",
                description: "Guardar canecas, papéis soltos e deixar a superfície livre.",
                frequency: .daily,
                duration: 5,
                priorityTag: .low,
                room: room
            ),
            ChoreDTO(
                name: "Limpar computador",
                description: "Passar pano de microfibra na tela e tirar a poeira entre as teclas.",
                frequency: .weekly,
                duration: 10,
                priorityTag: .low,
                room: room
            ),
            ChoreDTO(
                name: "Tirar o pó",
                description: "Limpar a mesa, as prateleiras e os equipamentos.",
                frequency: .weekly,
                duration: 10,
                priorityTag: .low,
                room: room
            ),
            ChoreDTO(
                name: "Varrer o chão",
                description: "Limpar o piso, incluindo embaixo da mesa e da cadeira.",
                frequency: .weekly,
                duration: 15,
                priorityTag: .low,
                room: room
            ),
            ChoreDTO(
                name: "Organizar cabos",
                description: "Prender os cabos soltos e conferir as tomadas e o filtro de linha.",
                frequency: .monthly,
                duration: 20,
                priorityTag: .low,
                room: room
            ),
            ChoreDTO(
                name: "Organizar papéis",
                description: "Arquivar o que é importante e descartar os papéis desnecessários.",
                frequency: .monthly,
                duration: 30,
                priorityTag: .low,
                room: room
            ),
            ChoreDTO(
                name: "Esvaziar lixeira",
                description: "Esvaziar a lixeira e descartar papéis e embalagens.",
                frequency: .weekly,
                duration: 5,
                priorityTag: .low,
                room: room
            )
        ]
    }

    /// Suggested chores for a ``balcony``.
    static var balconyChores: [ChoreDTO] {
        let room = DefaultRoomsOnboarding.balcony.roomDTO
        return [
            ChoreDTO(
                name: "Regar plantas",
                description: "Regar os vasos e tirar as folhas secas.",
                frequency: .daily,
                duration: 5,
                priorityTag: .low,
                room: room
            ),
            ChoreDTO(
                name: "Varrer varanda",
                description: "Varrer o piso e recolher folhas e poeira dos cantos.",
                frequency: .weekly,
                duration: 10,
                priorityTag: .medium,
                room: room
            ),
            ChoreDTO(
                name: "Limpar móveis",
                description: "Passar pano nas cadeiras, na mesa e sacudir as almofadas.",
                frequency: .weekly,
                duration: 10,
                priorityTag: .low,
                room: room
            ),
            ChoreDTO(
                name: "Limpar vidros",
                description: "Limpar as portas de vidro e o guarda-corpo.",
                frequency: .monthly,
                duration: 30,
                priorityTag: .low,
                room: room
            ),
            ChoreDTO(
                name: "Lavar o piso",
                description: "Lavar o piso com água e sabão e puxar a água para o ralo.",
                frequency: .monthly,
                duration: 25,
                priorityTag: .low,
                room: room
            )
        ]
    }

    /// Suggested chores for a ``pantry``.
    static var pantryChores: [ChoreDTO] {
        let room = DefaultRoomsOnboarding.pantry.roomDTO
        return [
            ChoreDTO(
                name: "Checar validades",
                description: "Conferir as datas de validade e separar o que vence logo.",
                frequency: .weekly,
                duration: 10,
                priorityTag: .medium,
                room: room
            ),
            ChoreDTO(
                name: "Listar compras",
                description: "Anotar o que está acabando para a próxima compra.",
                frequency: .weekly,
                duration: 5,
                priorityTag: .medium,
                room: room
            ),
            ChoreDTO(
                name: "Guardar compras",
                description: "Guardar as compras novas atrás das mais antigas.",
                frequency: .weekly,
                duration: 15,
                priorityTag: .low,
                room: room
            ),
            ChoreDTO(
                name: "Organizar itens",
                description: "Agrupar por categoria e deixar o que vence antes na frente.",
                frequency: .weekly,
                duration: 15,
                priorityTag: .low,
                room: room
            ),
            ChoreDTO(
                name: "Limpar armários",
                description: "Tirar os itens, passar pano nas prateleiras e reorganizar.",
                frequency: .monthly,
                duration: 30,
                priorityTag: .low,
                room: room
            ),
            ChoreDTO(
                name: "Checar pragas",
                description: "Procurar traças, formigas e sinais de umidade nos mantimentos.",
                frequency: .monthly,
                duration: 10,
                priorityTag: .low,
                room: room
            )
        ]
    }

    /// Suggested chores for a ``powderRoom``.
    static var powderRoomChores: [ChoreDTO] {
        let room = DefaultRoomsOnboarding.powderRoom.roomDTO
        return [
            ChoreDTO(
                name: "Limpar o vaso",
                description: "Escovar por dentro, desinfetar o assento e a parte externa.",
                frequency: .weekly,
                duration: 10,
                priorityTag: .high,
                room: room
            ),
            ChoreDTO(
                name: "Limpar a pia",
                description: "Esfregar a cuba e a torneira e secar a bancada.",
                frequency: .weekly,
                duration: 5,
                priorityTag: .medium,
                room: room
            ),
            ChoreDTO(
                name: "Trocar a toalha",
                description: "Recolher a toalha de rosto usada e pendurar uma limpa.",
                frequency: .weekly,
                duration: 5,
                priorityTag: .medium,
                room: room
            ),
            ChoreDTO(
                name: "Repor sabonete",
                description: "Conferir sabonete e papel higiênico e repor o que faltar.",
                frequency: .weekly,
                duration: 5,
                priorityTag: .low,
                room: room
            ),
            ChoreDTO(
                name: "Limpar espelho",
                description: "Tirar manchas e respingos do espelho.",
                frequency: .weekly,
                duration: 5,
                priorityTag: .low,
                room: room
            ),
            ChoreDTO(
                name: "Lavar o chão",
                description: "Esfregar o piso com desinfetante e limpar o ralo.",
                frequency: .monthly,
                duration: 15,
                priorityTag: .low,
                room: room
            ),
            ChoreDTO(
                name: "Esvaziar lixeira",
                description: "Trocar o saco da lixeira e levar o lixo para fora.",
                frequency: .weekly,
                duration: 5,
                priorityTag: .low,
                room: room
            )
        ]
    }

    /// Suggested chores for a ``garage``.
    static var garageChores: [ChoreDTO] {
        let room = DefaultRoomsOnboarding.garage.roomDTO
        return [
            ChoreDTO(
                name: "Varrer garagem",
                description: "Varrer o piso e recolher folhas e poeira.",
                frequency: .weekly,
                duration: 20,
                priorityTag: .low,
                room: room
            ),
            ChoreDTO(
                name: "Tirar manchas",
                description: "Remover manchas de óleo e sujeira do piso.",
                frequency: .monthly,
                duration: 30,
                priorityTag: .low,
                room: room
            ),
            ChoreDTO(
                name: "Organizar caixas",
                description: "Reorganizar caixas, ferramentas e objetos guardados.",
                frequency: .monthly,
                duration: 40,
                priorityTag: .low,
                room: room
            ),
            ChoreDTO(
                name: "Tirar teias",
                description: "Tirar as teias de aranha dos cantos e do teto.",
                frequency: .monthly,
                duration: 15,
                priorityTag: .low,
                room: room
            ),
            ChoreDTO(
                name: "Lavar o carro",
                description: "Lavar a parte de fora e aspirar a parte de dentro.",
                frequency: .monthly,
                duration: 60,
                priorityTag: .medium,
                room: room
            )
        ]
    }

    /// Suggested chores for a ``garden``.
    static var gardenChores: [ChoreDTO] {
        let room = DefaultRoomsOnboarding.garden.roomDTO
        return [
            ChoreDTO(
                name: "Regar jardim",
                description: "Regar os canteiros e as plantas, de preferência cedo ou no fim do dia.",
                frequency: .daily,
                duration: 15,
                priorityTag: .medium,
                room: room
            ),
            ChoreDTO(
                name: "Varrer folhas",
                description: "Varrer e recolher folhas e galhos do chão.",
                frequency: .weekly,
                duration: 15,
                priorityTag: .low,
                room: room
            ),
            ChoreDTO(
                name: "Arrancar ervas",
                description: "Tirar as ervas daninhas dos canteiros.",
                frequency: .weekly,
                duration: 20,
                priorityTag: .low,
                room: room
            ),
            ChoreDTO(
                name: "Cortar grama",
                description: "Cortar a grama e recolher o que foi aparado.",
                frequency: .fortnightly,
                duration: 45,
                priorityTag: .medium,
                room: room
            ),
            ChoreDTO(
                name: "Podar plantas",
                description: "Aparar galhos secos e dar forma às plantas.",
                frequency: .monthly,
                duration: 30,
                priorityTag: .low,
                room: room
            ),
            ChoreDTO(
                name: "Adubar plantas",
                description: "Colocar adubo nos canteiros e nos vasos.",
                frequency: .monthly,
                duration: 15,
                priorityTag: .low,
                room: room
            )
        ]
    }
}
