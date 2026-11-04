//
//  HarviiPairingErrorTests.swift
//  Cognitive-WorkTests
//
//  Created by Isabela Hissa Pinto on 03/11/26.
//

import Testing
import Foundation
@testable import Cognitive_Work

/// Checks the specific reason shown on ``ConnectionHarvii`` when pairing with the Harvii fails
/// (``HardwareViewModel/pairingErrorMessage(for:)``).
///
/// Serialized: every test switches the app-wide language and puts the original one back.
@MainActor
@Suite(.serialized)
struct HarviiPairingErrorTests {

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

    private func message(_ error: Error) -> String {
        HardwareViewModel.pairingErrorMessage(for: error)
    }

    // MARK: - Network errors

    @Test(arguments: [URLError.Code.timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed])
    func harviiDidNotAnswer(_ code: URLError.Code) {
        withLanguage(.portuguese) {
            #expect(message(URLError(code)) == "O Harvii não respondeu na rede da sua casa. Confira se o celular voltou para essa rede e se o Harvii está ligado e mostrando que se conectou ao Wi-Fi.")
        }
    }

    @Test(arguments: [URLError.Code.notConnectedToInternet, .networkConnectionLost])
    func phoneHasNoNetwork(_ code: URLError.Code) {
        withLanguage(.portuguese) {
            #expect(message(URLError(code)) == "O celular está sem conexão com a rede. Conecte-se ao Wi-Fi da sua casa e confira se o Pipa tem permissão de Rede Local nos Ajustes.")
        }
    }

    @Test func otherNetworkErrorsShowTheirCode() {
        let error = URLError(.badServerResponse)
        withLanguage(.portuguese) {
            #expect(message(error) == "Não foi possível falar com o Harvii (código \(error.errorCode)).")
        }
    }

    // MARK: - Device errors

    @Test func missingHostMeansTheWifiNeverArrived() {
        withLanguage(.portuguese) {
            #expect(message(APIErrors.invalidURL) == "O Harvii ainda não recebeu o Wi-Fi da sua casa. Volte e envie o Wi-Fi de novo.")
        }
    }

    @Test(arguments: [APIErrors.invalidResponse, .invalidData])
    func harviiRefusedThePairing(_ error: APIErrors) {
        withLanguage(.portuguese) {
            #expect(message(error) == "O Harvii respondeu, mas não aceitou o pareamento. Tente de novo; se continuar, segure o botão BOOT por 5 segundos para resetar o Harvii.")
        }
    }

    @Test func otherDeviceErrorsUseTheirOwnDescription() {
        withLanguage(.portuguese) {
            #expect(message(APIErrors.unableToEncode) == APIErrors.unableToEncode.errorDescription)
        }
    }

    @Test func unknownErrorsUseTheSystemDescription() {
        let error = NSError(domain: "Test", code: 7, userInfo: [NSLocalizedDescriptionKey: "Falhou"])
        #expect(message(error) == "Falhou")
    }

    // MARK: - Translation

    @Test func translatesTheReasonToEnglish() {
        withLanguage(.english) {
            #expect(message(URLError(.timedOut)) == "Harvii didn't answer on your home network. Check that your phone is back on that network and that Harvii is on and shows it joined the Wi-Fi.")
            #expect(message(URLError(.badServerResponse)) == "Couldn't talk to Harvii (code \(URLError(.badServerResponse).errorCode)).")
        }
    }
}
