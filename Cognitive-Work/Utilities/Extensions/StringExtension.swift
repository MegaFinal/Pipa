//
//  StringExtension.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 06/11/26.
//

import Foundation

extension String {
    /// The text with its first letter in upper case and the rest as it is ("arroz integral" ->
    /// "Arroz integral", "iPhone" stays as typed after its first letter). Used for names the
    /// on-device model writes, which often come all in lower case, so they look like the ones
    /// people type. Scripts without case (Chinese, Japanese…) are left alone.
    func capitalizingFirstLetter(locale: Locale = L10n.locale) -> String {
        guard let first else { return self }
        return String(first).uppercased(with: locale) + dropFirst()
    }
}
