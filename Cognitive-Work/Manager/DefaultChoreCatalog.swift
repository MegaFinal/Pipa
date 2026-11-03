//
//  DefaultChoreCatalog.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 08/10/26.
//

import Foundation

/// Tells chores that came from the app's suggestions apart from chores the user wrote.
/// > Note: once the user edits a suggested chore's description, it counts as the user's own text and
/// > stops being translated, name included.
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

extension ChoreModel {
    /// The name to display: translated only if this is a suggested chore, otherwise exactly as written.
    var localizedName: String {
        DefaultChoreCatalog.isSuggestion(name: name, description: description)
            ? name.localizedDefault
            : name
    }
    
    /// The description to display: translated only if this is a suggested chore.
    var localizedDescription: String {
        DefaultChoreCatalog.isSuggestion(name: name, description: description)
            ? description.localizedDefault
            : description
    }
}

extension ChoreDTO {
    /// The name to display: translated only if this is a suggested chore, otherwise exactly as written.
    var localizedName: String {
        DefaultChoreCatalog.isSuggestion(name: name, description: description)
            ? name.localizedDefault
            : name
    }
}
