//
//  DefaultChoreCatalog.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 08/10/26.
//

import Foundation

/// Tells chores that came from the app's suggestions apart from chores the user wrote.
/// > Note: names and descriptions are translated independently: a default name keeps being
/// > translated even if the description was edited; text the user typed is never translated.
enum DefaultChoreCatalog {
    
    /// Every suggested chore, as "name + description" keys.
    private static let entries: Set<String> = {
        var keys = Set<String>()
        for room in DefaultRoomsOnboarding.allCases {
            for chore in room.defaultChores {
                keys.insert(key(name: chore.name, description: chore.description))
            }
        }
        return keys
    }()
    
    /// Every text the app itself provides in Portuguese and translates on display: default room
    /// names plus the suggested chores' names and descriptions. ``String/localizedDefault`` only
    /// translates text in this set, so whatever the user types is never swapped for a translation
    /// (typing "Qua" used to become "Wed", the weekday abbreviation from the catalog).
    static let defaultTexts: Set<String> = {
        var texts = Set(DefaultRoomsOnboarding.allCases.map(\.rawValue))
        for room in DefaultRoomsOnboarding.allCases {
            for chore in room.defaultChores {
                texts.insert(chore.name)
                texts.insert(chore.description)
            }
        }
        return texts
    }()

    /// Default texts by their folded form (no case, accents or extra spaces), so "lavar roupas"
    /// typed in lowercase is still recognized as the default "Lavar roupas".
    private static let defaultTextsByFolded: [String: String] = {
        var map: [String: String] = [:]
        for text in defaultTexts { map[folded(text)] = text }
        return map
    }()

    /// The catalog key of `text` when it's one of the app's default texts, ignoring case,
    /// accents and spaces at the ends; `nil` for anything else.
    static func defaultKey(for text: String) -> String? {
        if defaultTexts.contains(text) { return text }
        return defaultTextsByFolded[folded(text)]
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether `name` and `description` are exactly one of the app's suggested chores.
    static func isSuggestion(name: String, description: String) -> Bool {
        entries.contains(key(name: name, description: description))
    }
    
    /// One string that identifies a name + description pair (used to compare chores).
    private static func key(name: String, description: String) -> String {
        // Unit separator: cannot appear in text typed by the user.
        "\(name)\u{1F}\(description)"
    }
}

// MARK: - Display text

// Name and description are translated each on its own: a default name stays translated even
// when the description was changed (or comes from an older version of the catalog), so a card
// never mixes languages for the app's own texts. Anything the user wrote stays as written.

extension ChoreModel {
    /// The name to display: translated when it's one of the app's default names.
    var localizedName: String { name.localizedDefault }

    /// The description to display: translated when it's one of the app's default descriptions.
    var localizedDescription: String { description.localizedDefault }
}

extension ChoreDTO {
    /// The name to display: translated when it's one of the app's default names.
    var localizedName: String { name.localizedDefault }
}
