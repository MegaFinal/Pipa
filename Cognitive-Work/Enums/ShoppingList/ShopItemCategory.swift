//
//  ShopItemCategory.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 18/09/26.
//

import SwiftUI

/// The aisle a shopping list item belongs to.
///
/// The raw value is saved in CloudKit, so cases must not be renamed.
enum ShopItemCategory: String, CaseIterable, Identifiable, Codable {
    /// Packaged food (rice, pasta, snacks...).
    case food
    /// Fruits and vegetables.
    case produce
    /// Drinks.
    case drinks
    /// Cleaning products.
    case cleaning
    /// Personal hygiene products.
    case hygiene
    /// Things for the house (bulbs, batteries...).
    case home
    /// Pet food and supplies.
    case pets
    /// Anything else.
    case other

    /// Identifier for SwiftUI lists (the raw value).
    var id: String { rawValue }

    /// The fixed order of the cards on the shopping list
    static let listOrder: [ShopItemCategory] = [.food, .drinks, .produce, .cleaning, .other, .hygiene, .pets, .home]

    /// Preselected when adding an item: the first one in the picker.
    static let `default`: ShopItemCategory = .food

    /// Name shown to the user.
    var displayName: String {
        switch self {
        case .food: return L10n.tr("Alimentos")
        case .produce: return L10n.tr("Hortifruti")
        case .drinks: return L10n.tr("Bebidas")
        case .cleaning: return L10n.tr("Produtos de limpeza")
        case .hygiene: return L10n.tr("Farmácia")
        case .home: return L10n.tr("Casa")
        case .pets: return L10n.tr("Pets")
        case .other: return L10n.tr("Outros")
        }
    }

    /// Icon drawn on cards and chips: the `ShoppingListSymbols` artwork (the home category has
    /// none yet, so it keeps an SF Symbol). Drawn with ``SymbolImage``.
    var symbol: String {
        switch self {
        case .food: return "food"
        case .produce: return "fruit"
        case .drinks: return "drinks"
        case .cleaning: return "cleaning"
        case .hygiene: return "farmacy"
        case .home: return "house"
        case .pets: return "pets"
        case .other: return "plastic.bag"
        }
    }

    /// Reuses the rooms' palette, so cards look like the chore cards.
    var roomColor: RoomColor {
        switch self {
        case .food: return .orange
        case .produce: return .green
        case .drinks: return .yellow
        case .cleaning: return .blue
        case .hygiene: return .blue
        case .home: return .yellow
        case .pets: return .green
        case .other: return .purple
        }
    }

    /// The texture drawn behind the category's icon tile. Falls back to clouds where the
    /// asset catalog has no such pattern in the category's color (see ``RoomTexturePattern``).
    var texturePattern: RoomTexturePattern {
        switch self {
        case .food, .pets: return .worms
        case .produce, .home: return .clouds
        case .drinks: return .halfCircle
        case .cleaning: return .sparkles
        case .hygiene, .other: return .stars
        }
    }

    /// The category's main color (from ``roomColor``).
    var color: Color { roomColor.uiColor }
    /// The soft version of ``color``, for backgrounds.
    var softColor: Color { roomColor.lowOpacityColor }
}
