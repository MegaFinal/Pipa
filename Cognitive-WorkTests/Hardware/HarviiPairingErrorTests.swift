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
            #expect(message(URLError(code)) == "O Harvii não respondeu na rede da sua casa. Confira se o celular voltou para essa rede e se o Harvii está ligado. Se a tela dele mostrar “Não consegui conectar ao WiFi”, a senha pode estar errada: volte, entre na rede HARVII e envie o Wi-Fi de novo.")
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

    /// The "didn't answer" reason, in every language of the app.
    nonisolated static let notAnsweredByLanguage: [(AppLanguage, String)] = [
        (.portuguese, "O Harvii não respondeu na rede da sua casa. Confira se o celular voltou para essa rede e se o Harvii está ligado. Se a tela dele mostrar “Não consegui conectar ao WiFi”, a senha pode estar errada: volte, entre na rede HARVII e envie o Wi-Fi de novo."),
        (.english, "Harvii didn't answer on your home network. Check that your phone is back on that network and that Harvii is on. If its screen shows “Couldn't connect to WiFi”, the password may be wrong: go back, join the HARVII network and send the Wi-Fi again."),
        (.spanish, "Harvii no respondió en la red de tu casa. Verifica que el celular haya vuelto a esa red y que Harvii esté encendido. Si su pantalla muestra “No pude conectarme al WiFi”, la contraseña puede estar mal: vuelve, conéctate a la red HARVII y envía el Wi-Fi de nuevo."),
        (.french, "Harvii n’a pas répondu sur le réseau de ton foyer. Vérifie que ton téléphone est revenu sur ce réseau et que Harvii est allumé. Si son écran affiche « Je n’ai pas pu me connecter au WiFi », le mot de passe est peut-être faux : reviens en arrière, rejoins le réseau HARVII et renvoie le Wi-Fi."),
        (.chinese, "Harvii 在你家的网络中没有响应。请确认手机已回到这个网络，并且 Harvii 已开机。如果它的屏幕显示“无法连接到 WiFi”，可能是密码错了：请返回，连接 HARVII 网络，然后重新发送 Wi-Fi。"),
        (.korean, "집 네트워크에서 Harvii가 응답하지 않았어요. 휴대폰이 그 네트워크로 돌아왔는지, Harvii가 켜져 있는지 확인하세요. Harvii 화면에 “WiFi에 연결하지 못했어요”가 표시되면 비밀번호가 틀렸을 수 있어요. 돌아가서 HARVII 네트워크에 연결하고 Wi-Fi를 다시 보내세요."),
        (.japanese, "おうちのネットワークでHarviiから応答がありませんでした。携帯電話がそのネットワークに戻っているか、Harviiの電源が入っているか確認してください。Harviiの画面に「WiFiに接続できませんでした」と表示されている場合は、パスワードが間違っている可能性があります。戻ってHARVIIネットワークに接続し、もう一度Wi-Fiを送信してください。"),
    ]

    /// The reason with the error code, in every language of the app (`%lld` is the code).
    nonisolated static let codeByLanguage: [(AppLanguage, String)] = [
        (.portuguese, "Não foi possível falar com o Harvii (código %lld)."),
        (.english, "Couldn't talk to Harvii (code %lld)."),
        (.spanish, "No fue posible comunicarse con Harvii (código %lld)."),
        (.french, "Impossible de communiquer avec Harvii (code %lld)."),
        (.chinese, "无法与 Harvii 通信（代码 %lld）。"),
        (.korean, "Harvii와 통신하지 못했어요(코드 %lld)."),
        (.japanese, "Harviiと通信できませんでした（コード %lld）。"),
    ]

    @Test(arguments: notAnsweredByLanguage)
    func translatesTheReason(_ language: AppLanguage, _ expected: String) {
        withLanguage(language) {
            #expect(message(URLError(.timedOut)) == expected)
        }
    }

    @Test(arguments: codeByLanguage)
    func translatesTheReasonWithItsCode(_ language: AppLanguage, _ template: String) {
        let error = URLError(.badServerResponse)
        withLanguage(language) {
            #expect(message(error) == template.replacingOccurrences(of: "%lld", with: "\(error.errorCode)"))
        }
    }
}
