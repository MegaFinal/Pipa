//
//  ReceiptLineDraft.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 06/11/26.
//

import Foundation

/// A copy of one receipt line while it's edited in ``ReceiptLineFormView``. The review only
/// changes when the person confirms (``ReceiptScanViewModel/save(_:)``); closing the form drops
/// the copy. Changes that depend on the rest of the receipt (the price following the quantity,
/// the aisle following the name, the people following the list item) go through
/// ``ReceiptScanViewModel``.
struct ReceiptLineDraft: Identifiable, Equatable {

    /// The line's id.
    let id: UUID
    /// Added by the person ("Adicionar item"): closing the form without confirming removes it.
    let isNew: Bool
    /// Kilograms for products sold by weight (read from the receipt, not editable), otherwise 0.
    let weightKg: Double
    /// What the reader flagged on the line, if anything.
    let warning: ReceiptLineWarning?

    var name: String
    /// Units bought (0 while the quantity field is empty).
    var quantity: Int
    /// The price field's text ("18,16").
    var priceText: String
    /// The price of one unit, so the total follows the quantity.
    var unitPrice: Double
    /// The list item this line checks off (by ``ShopListItem/id``); `nil` adds a new item.
    var linkedItemID: String?
    /// The aisle, for a line added as a new item.
    var category: ShopItemCategory
    /// The aisle Apple Intelligence chose, if any; sparkles show while ``category`` is still it.
    let aiCategory: ShopItemCategory?
    /// Whether the person picked the aisle (then it no longer follows the name).
    var didPickCategory: Bool
    /// Who splits the price.
    var consumers: [UserModel]
    /// Whether the person picked the people (then they no longer follow the list item).
    var didPickConsumers: Bool

    /// Sold by weight: the quantity comes from the receipt.
    var isWeighed: Bool { weightKg > 0 }

    /// The name without spaces at the ends.
    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether the aisle shown is still the one Apple Intelligence chose.
    var isCategoryFromAI: Bool {
        aiCategory != nil && aiCategory == category
    }
}
