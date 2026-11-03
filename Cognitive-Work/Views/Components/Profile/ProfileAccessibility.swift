//
//  ProfileAccessibility.swift
//  Cognitive-Work
//
//  VoiceOver names for the profile/room pickers and the member avatar lists.
//

import Foundation

extension RoomColor {
    /// Spoken name of this color for VoiceOver (the pickers only show a swatch).
    var voiceOverName: String {
        switch self {
        case .purple: L10n.tr("Roxo")
        case .orange: L10n.tr("Laranja")
        case .yellow: L10n.tr("Amarelo")
        case .green: L10n.tr("Verde")
        case .blue: L10n.tr("Azul")
        }
    }
}

/// Accessibility text shared by the profile area's components.
enum ProfileAccessibility {

    /// Spoken name of a room icon (SF Symbol) offered by the room form's icon picker.
    static func symbolName(_ symbol: String) -> String {
        if let room = DefaultRoomsOnboarding.allCases.first(where: { $0.symbol == symbol }) {
            return room.rawValue.localizedDefault
        }
        switch symbol {
        case "armchair": return L10n.tr("Poltrona")
        case "twin.bed.stripes": return L10n.tr("Cama de solteiro")
        case "laptop": return L10n.tr("Notebook")
        case "stove.pans": return L10n.tr("Panelas no fogão")
        case "shower": return L10n.tr("Chuveiro")
        case "washing.machine": return L10n.tr("Máquina de lavar")
        case "clothes.basket": return L10n.tr("Cesto de roupa")
        case "clothes.line.filled": return L10n.tr("Varal")
        case "balcony.aluminum.chair": return L10n.tr("Cadeira de varanda")
        case "default.plant": return L10n.tr("Planta")
        case "bicicle": return L10n.tr("Bicicleta")
        case "kite": return L10n.tr("Pipa")
        default: return L10n.tr("Ícone")
        }
    }

    /// Members read as "Fulano, Ciclano e mais 2".
    static func memberList(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return L10n.tr("\(names[0]) e \(names[1])")
        default: return L10n.tr("\(names[0]), \(names[1]) e mais \(names.count - 2)")
        }
    }
}
