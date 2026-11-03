//
//  L10nTests.swift
//  Cognitive-WorkTests
//

import Testing
import Foundation
@testable import Cognitive_Work

/// Checks that ``L10n`` resolves texts in the language picked inside the app, fills in
/// interpolated values and applies the catalog's plural rules.
///
/// Serialized: every test switches the app-wide language and puts the original one back.
@MainActor
@Suite(.serialized)
struct L10nTests {

    /// Runs `body` with the app in `language`, restoring the previous language afterwards.
    private func withLanguage(_ language: AppLanguage, _ body: () -> Void) {
        let manager = LanguageManager.shared
        let previous = manager.current
        let previousAppleLanguages = UserDefaults.standard.object(forKey: "AppleLanguages")
        manager.setLanguage(language)
        defer {
            manager.setLanguage(previous)
            UserDefaults.standard.set(previousAppleLanguages, forKey: "AppleLanguages")
        }
        body()
    }

    @Test func translatesPlainTextToEnglish() {
        withLanguage(.english) {
            #expect(L10n.tr("Fechar") == "Close")
        }
    }

    @Test func keepsPortugueseSource() {
        withLanguage(.portuguese) {
            #expect(L10n.tr("Fechar") == "Fechar")
        }
    }

    @Test func fillsInterpolatedValues() {
        let name = "Ana"
        withLanguage(.english) {
            #expect(L10n.tr("Assinado por \(name). Todos os moradores aproveitam os recursos Premium.")
                    == "Subscribed by Ana. Every housemate gets the Premium features.")
        }
        withLanguage(.portuguese) {
            #expect(L10n.tr("Assinado por \(name). Todos os moradores aproveitam os recursos Premium.")
                    == "Assinado por Ana. Todos os moradores aproveitam os recursos Premium.")
        }
    }

    @Test func appliesPluralRules() {
        withLanguage(.english) {
            #expect(L10n.tr("\(1) moradores") == "1 housemate")
            #expect(L10n.tr("\(5) moradores") == "5 housemates")
        }
        withLanguage(.portuguese) {
            #expect(L10n.tr("\(1) moradores") == "1 morador")
            #expect(L10n.tr("\(5) moradores") == "5 moradores")
        }
    }

    @Test func translatesToSpanish() {
        let name = "Ana"
        withLanguage(.spanish) {
            #expect(L10n.tr("Fechar") == "Cerrar")
            #expect(L10n.tr("Assinado por \(name). Todos os moradores aproveitam os recursos Premium.")
                    == "Suscrito por Ana. Todos los integrantes disfrutan de las funciones Premium.")
            #expect(L10n.tr("\(1) moradores") == "1 integrante")
            #expect(L10n.tr("\(5) moradores") == "5 integrantes")
        }
    }

    @Test func translatesToFrench() {
        let name = "Ana"
        withLanguage(.french) {
            #expect(L10n.tr("Fechar") == "Fermer")
            #expect(L10n.tr("Assinado por \(name). Todos os moradores aproveitam os recursos Premium.")
                    == "Abonnement de Ana. Tous les colocataires profitent des fonctionnalités Premium.")
            #expect(L10n.tr("\(1) moradores") == "1 colocataire")
            #expect(L10n.tr("\(5) moradores") == "5 colocataires")
        }
    }

    @Test func fallsBackToPortugueseWhenThereIsNoTranslation() {
        let value = 7
        withLanguage(.english) {
            #expect(L10n.tr("Texto que não existe no catálogo \(value)") == "Texto que não existe no catálogo 7")
        }
    }

    @Test func resolvesKeysKnownOnlyAtRunTime() {
        let key = "Fechar"
        withLanguage(.english) {
            #expect(L10n.tr(key: key) == "Close")
        }
    }
}
