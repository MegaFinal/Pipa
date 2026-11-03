//
//  LanguageManager.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 30/09/26.
//

import SwiftUI

/// Languages the app ships translations for.
enum AppLanguage: String, CaseIterable, Identifiable {
    /// Brazilian Portuguese (the app's original language).
    case portuguese = "pt-BR"
    /// English.
    case english = "en"
    /// Spanish (neutral Latin American: "tú", no regional slang).
    case spanish = "es"
    /// French (France, informal "tu" like the rest of the app).
    case french = "fr"
    /// Korean.
    case korean = "ko"
    /// Japanese.
    case japanese = "ja"

    /// Identifier for SwiftUI lists (the raw value).
    var id: String { rawValue }

    /// Locale used for lookups and for every date/number format in the app.
    var locale: Locale { Locale(identifier: rawValue) }

    /// Name shown in the language picker, always written in the language itself so the user
    /// can find it even when the rest of the UI is in a language they don't read.
    var nativeName: String {
        switch self {
        case .portuguese: return "Português"
        case .english: return "English"
        case .spanish: return "Español"
        case .french: return "Français"
        case .korean: return "한국어"
        case .japanese: return "日本語"
        }
    }

    /// The best match for the device's preferred languages.
    static var systemDefault: AppLanguage {
        let preferred = Locale.preferredLanguages.first ?? AppLanguage.portuguese.rawValue
        return allCases.first { preferred.hasPrefix($0.rawValue) } ?? .portuguese
    }
}

/// Owns the language chosen in "Configurações Gerais" and applies it at runtime.
@Observable
final class LanguageManager {

    /// The single instance used by the app.
    static let shared = LanguageManager()

    /// The `UserDefaults` key where the chosen language is saved.
    private static let storageKey = "appLanguage"

    /// The language currently applied to the app.
    private(set) var current: AppLanguage

    /// `.lproj` bundle matching ``current``; falls back to the main bundle.
    @ObservationIgnored
    private(set) var bundle: Bundle = .main

    /// The locale of ``current``, for formatting dates and numbers.
    var locale: Locale { current.locale }

    /// Loads the saved language (or the device's default) and its translations.
    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.storageKey).flatMap(AppLanguage.init(rawValue:))
        current = stored ?? .systemDefault
        bundle = Self.bundle(for: current)
    }

    /// Switches the whole app to `language` immediately and remembers the choice.
    func setLanguage(_ language: AppLanguage) {
        guard language != current else { return }
        bundle = Self.bundle(for: language)
        current = language
        UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
    }

    /// Looks `key` up in the active language, returning the key itself (Portuguese, the
    /// source language) when there is no translation.
    func localized(_ key: String) -> String {
        _ = current // registers an observation dependency for views calling this in `body`
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    /// Resolves `resource` in the active language, filling in its interpolated values (with the
    /// catalog's plural rules) and formatting them with ``locale``. Falls back to the Portuguese
    /// text written in the code when there is no translation.
    ///
    /// The resource's own bundle and locale are replaced by the ones of ``current``: the
    /// language picked inside the app wins over the device language.
    func localized(_ resource: LocalizedStringResource) -> String {
        _ = current // registers an observation dependency for views calling this in `body`
        return String(
            localized: resource.defaultValue,
            table: resource.table,
            bundle: bundle,
            locale: locale
        )
    }

    /// The translations bundle of `language`, or the main bundle when none is found.
    private static func bundle(for language: AppLanguage) -> Bundle {
        let candidates = [language.rawValue, language.rawValue.replacingOccurrences(of: "-", with: "_"), String(language.rawValue.prefix(2))]
        for candidate in candidates {
            if let path = Bundle.main.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }
        return .main
    }
}

/// Shorthand for strings resolved outside SwiftUI `Text` (enums, view models, `String` params).
///
/// Write the Portuguese text right in the call, with the values interpolated:
///
/// ```swift
/// L10n.tr("Fechar")
/// L10n.tr("Assinado por \(name)")        // key "Assinado por %@"
/// L10n.tr("\(count) moradores")           // key "%lld moradores" (can vary by plural)
/// ```
///
/// The parameter is a `LocalizedStringResource`, so Xcode reads these calls when it builds and
/// keeps `Localizable.xcstrings` in sync: new texts show up in the catalog by themselves and the
/// ones still in use are never marked "stale". Interpolating an `Int` gives `%lld`, a `String`
/// gives `%@`.
enum L10n {
    /// The text of `resource` in the app's current language.
    static func tr(_ resource: LocalizedStringResource) -> String {
        LanguageManager.shared.localized(resource)
    }

    /// The text of a key only known at run time (an enum's raw value, default content saved in
    /// the database…).
    ///
    /// - Important: Xcode can't see keys passed this way. Mark them "manual" in
    ///   `Localizable.xcstrings`, or they show up as stale. Prefer ``tr(_:)`` with a literal.
    static func tr(key: String) -> String {
        LanguageManager.shared.localized(key)
    }

    /// Locale to use in every `formatted(...)`/`DateFormatter` call.
    static var locale: Locale { LanguageManager.shared.locale }
}

// MARK: - Default content

extension String {
    /// Translates text that comes from the app's default catalog (room names, suggested chore
    /// names and descriptions, see ``DefaultChoreCatalog/defaultTexts``) into the current language.
    ///
    /// Defaults are saved once, in Portuguese (the source language), so they never change when
    /// the user switches language. Translating them when they are *displayed* keeps the stored
    /// data untouched and makes the change immediate. Text with no translation (anything the
    /// user typed) is returned as is, and numbered rooms such as "Quarto 2" translate their base
    /// name and keep the number ("Bedroom 2").
    var localizedDefault: String {
        // Only the app's own default content is translated. Any other catalog key (weekday
        // abbreviations like "Qua", button titles…) typed by the user stays exactly as written.
        if DefaultChoreCatalog.defaultTexts.contains(self) {
            let translated = L10n.tr(key: self)
            if translated != self { return translated }
        }
        
        // "Quarto 2" -> "Bedroom 2"
        guard let space = lastIndex(of: " "),
              Int(self[index(after: space)...]) != nil
        else { return self }
        
        let base = String(self[..<space])
        guard DefaultChoreCatalog.defaultTexts.contains(base) else { return self }
        let translatedBase = L10n.tr(key: base)
        return translatedBase == base ? self : "\(translatedBase)\(self[space...])"
    }
}
