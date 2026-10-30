//
//  ShopListViewModel+Accessibility.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 09/10/26.
//

import Foundation

/// VoiceOver texts and announcements for the shopping list, its item form and the price popup.
extension ShopListViewModel {

    // MARK: - Texts

    /// "5 quilogramas", with the unit in the right plural.
    static func accessibilityQuantity(_ quantity: Int, unit: UnitMeasurement) -> String {
        "\(quantity) \(unit.getDisplayName(for: Double(quantity)))"
    }

    /// "Jones e Carol", in the app's language.
    static func accessibilityList(_ names: [String]) -> String {
        let formatter = ListFormatter()
        formatter.locale = L10n.locale
        return formatter.string(from: names) ?? names.joined(separator: ", ")
    }

    /// One sentence for a whole item card:
    /// "Arroz, 5 quilogramas, Alimentos, R$ 140,00, para Jones e Carol, pendente".
    static func accessibilityLabel(for item: ShopListItem, relatedUsers: [UserModel]) -> String {
        var parts = [
            item.name,
            accessibilityQuantity(item.quantity, unit: item.unitMeasurement),
            item.category.displayName
        ]
        if let total = item.totalValue {
            parts.append(VoiceOver.currency(total))
        }
        let names = relatedUsers.map(\.name).filter { !$0.isEmpty }
        if !names.isEmpty {
            parts.append(L10n.tr("para \(accessibilityList(names))"))
        }
        parts.append(item.isBought ? L10n.tr("comprado") : L10n.tr("pendente"))
        return parts.joined(separator: ", ")
    }

    /// What activating an item card does: checking it off or putting it back.
    static func accessibilityToggleName(for item: ShopListItem) -> String {
        item.isBought ? L10n.tr("Marcar como não comprado") : L10n.tr("Marcar como comprado")
    }

    /// "Alimentos, 3 itens".
    func accessibilityLabel(for section: ShopListSection) -> String {
        let count = section.items.count
        let countText = count == 1 ? L10n.tr("1 item") : L10n.tr("\(count) itens")
        return "\(section.title), \(countText)"
    }

    /// "expandida" or "recolhida".
    func accessibilityValue(for section: ShopListSection) -> String {
        isCollapsed(section) ? L10n.tr("recolhida") : L10n.tr("expandida")
    }

    /// A typed price read as currency ("15 reais"), or empty when nothing was typed.
    static func accessibilityPrice(_ text: String) -> String {
        guard let value = parsePrice(text), value > 0 else { return "" }
        return VoiceOver.currency(value)
    }

    /// The popup's live total, spoken: "3 × 5 reais, total 15 reais". `nil` before a price is typed.
    static func accessibilityPurchaseTotal(text: String, quantity: Int) -> String? {
        guard let unit = parsePrice(text), unit > 0 else { return nil }
        return L10n.tr("\(quantity) × \(VoiceOver.currency(unit)), total \(VoiceOver.currency(unit * Double(quantity)))")
    }

    // MARK: - Voice Control

    /// Speakable names for an item card, whose activation checks it off: the name shown on the
    /// card first, then "Comprar Arroz" / "Marcar Arroz" ("Desmarcar Arroz" once bought).
    static func voiceControlInputLabels(for item: ShopListItem) -> [String] {
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return [L10n.tr("Item")] }
        if item.isBought {
            return [name, L10n.tr("Desmarcar \(name)")]
        }
        return [name, L10n.tr("Comprar \(name)"), L10n.tr("Marcar \(name)")]
    }

    // MARK: - Actions that announce their result

    /// ``toggleBought(_:)``, then says "Item comprado" / "Item devolvido à lista" when the item
    /// changed (not when the price popup opened instead).
    func toggleBoughtAnnouncing(_ item: ShopListItem) async {
        let wasBought = item.isBought
        await toggleBought(item)
        guard item.isBought != wasBought else { return }
        VoiceOver.announce(item.isBought ? L10n.tr("Item comprado") : L10n.tr("Item devolvido à lista"))
    }

    /// ``confirmPurchase(of:valueText:)``, then says "Item comprado".
    func confirmPurchaseAnnouncing(of item: ShopListItem, valueText: String?) async {
        let wasBought = item.isBought
        await confirmPurchase(of: item, valueText: valueText)
        if item.isBought && !wasBought {
            VoiceOver.announce(L10n.tr("Item comprado"))
        }
    }

    /// ``deleteItem(_:)``, then says "Item excluído".
    func deleteItemAnnouncing(_ item: ShopListItem) async {
        if await deleteItem(item) {
            VoiceOver.announce(L10n.tr("Item excluído"))
        }
    }
}
