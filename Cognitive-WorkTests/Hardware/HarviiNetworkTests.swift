//
//  HarviiNetworkTests.swift
//  Cognitive-WorkTests
//
//  Created by Isabela Hissa Pinto on 03/11/26.
//

import Testing
import Foundation
@testable import Cognitive_Work

extension HarviiPairingStateTests {
    
    /// Checks what the app sends to the Harvii and what it keeps from the answers, with
    /// ``FakeHarviiProtocol`` answering instead of the device.
    ///
    /// Nested in ``HarviiPairingStateTests`` so it runs serialized with it: both use the real
    /// `UserDefaults` keys (and put them back).
    @Suite struct Network {
        
        private let pairedPhone = [
            "hardware.hash": "abc123",
            "hardware.host": "harvi-ab12.local",
            "hardware.name": "Casa da Bela",
        ]
        
        // MARK: - Wi-Fi (Harvii network)
        
        @Test func sendsTheWifiToTheFixedAddress() async throws {
            try await withSavedHardware {
                try await withFakeHarvii({ _ in .ok("Data processed successfully", ["name": "harvi-ab12"]) }) {
                    let manager = HardwareNetworkManager()
                    let host = try await manager.sendWifiCredentials(ssid: "Casa da Bela", password: "segredo123")
                    
                    let request = try #require(FakeHarviiProtocol.received.first)
                    #expect(request.request.httpMethod == "POST")
                    #expect(request.host == "192.168.4.1")
                    #expect(request.path == "/save_wifi")
                    #expect(request.json["ssid"] as? String == "Casa da Bela")
                    #expect(request.json["password"] as? String == "segredo123")
                    
                    #expect(host == "harvi-ab12.local")
                    #expect(manager.host == "harvi-ab12.local")
                    #expect(manager.wifiName == "Casa da Bela")
                }
            }
        }
        
        @Test func keepsTheHostAndWifiNameOnThePhone() async throws {
            try await withSavedHardware {
                try await withFakeHarvii({ _ in .ok("ok", ["name": "harvi-ab12"]) }) {
                    _ = try await HardwareNetworkManager().sendWifiCredentials(ssid: "Casa da Bela", password: "segredo123")
                    
                    #expect(UserDefaults.standard.string(forKey: "hardware.host") == "harvi-ab12.local")
                    #expect(UserDefaults.standard.string(forKey: "hardware.name") == "Casa da Bela")
                    // Sent the Wi-Fi, but not paired yet.
                    #expect(!HardwareNetworkManager().isConnected)
                }
            }
        }
        
        @Test func answerWithoutNameIsAnError() async throws {
            await withSavedHardware {
                await withFakeHarvii({ _ in .ok() }) {
                    await #expect(throws: APIErrors.invalidData) {
                        _ = try await HardwareNetworkManager().sendWifiCredentials(ssid: "Casa", password: "123")
                    }
                }
            }
        }
        
        @Test func refusedWifiIsAnError() async throws {
            await withSavedHardware {
                await withFakeHarvii({ _ in .failure(400, "Campos ssid/password ausentes") }) {
                    await #expect(throws: APIErrors.invalidResponse) {
                        _ = try await HardwareNetworkManager().sendWifiCredentials(ssid: "Casa", password: "123")
                    }
                }
            }
        }
        
        // MARK: - Pairing (home network)
        
        @Test func pairingKeepsTheHash() async throws {
            try await withSavedHardware(["hardware.host": "harvi-ab12.local"]) {
                try await withFakeHarvii({ _ in .ok("abc123") }) {
                    let manager = HardwareNetworkManager()
                    try await manager.askForParingCode()
                    
                    let request = try #require(FakeHarviiProtocol.received.first)
                    #expect(request.request.httpMethod == "POST")
                    #expect(request.host == "harvi-ab12.local")
                    #expect(request.path == "/ask_code")
                    
                    #expect(manager.isConnected)
                    #expect(UserDefaults.standard.string(forKey: "hardware.hash") == "abc123")
                    // Like reopening the app.
                    #expect(HardwareNetworkManager().isConnected)
                }
            }
        }
        
        @Test func refusedPairingKeepsThePhoneUnpaired() async throws {
            await withSavedHardware(["hardware.host": "harvi-ab12.local"]) {
                await withFakeHarvii({ _ in .failure(500) }) {
                    let manager = HardwareNetworkManager()
                    await #expect(throws: APIErrors.invalidResponse) {
                        try await manager.askForParingCode()
                    }
                    #expect(!manager.isConnected)
                    #expect(UserDefaults.standard.string(forKey: "hardware.hash") == nil)
                }
            }
        }
        
        @Test func pairingWithoutHostDoesNotCallTheHarvii() async throws {
            await withSavedHardware {
                await withFakeHarvii({ _ in .ok("abc123") }) {
                    await #expect(throws: APIErrors.invalidURL) {
                        try await HardwareNetworkManager().askForParingCode()
                    }
                    #expect(FakeHarviiProtocol.received.isEmpty)
                }
            }
        }
        
        // MARK: - Status
        
        @Test(arguments: [true, false])
        func statusSendsTheHashAndReadsTheAnswer(_ needsRefresh: Bool) async throws {
            try await withSavedHardware(pairedPhone) {
                try await withFakeHarvii({ _ in .ok("ok", ["needsRefresh": needsRefresh]) }) {
                    let answer = try await HardwareNetworkManager().deviceNeedsRefresh()
                    
                    let request = try #require(FakeHarviiProtocol.received.first)
                    #expect(request.request.httpMethod == "GET")
                    #expect(request.path == "/status")
                    #expect(request.header("X-Auth-Hash") == "abc123")
                    #expect(answer == needsRefresh)
                }
            }
        }
        
        @Test func unauthorizedDropsThePairing() async throws {
            // The Harvii was reset (or its hash changed): this phone must pair again.
            await withSavedHardware(pairedPhone) {
                await withFakeHarvii({ _ in .failure(401, "Nao autorizado") }) {
                    let manager = HardwareNetworkManager()
                    await #expect(throws: APIErrors.invalidResponse) {
                        _ = try await manager.deviceNeedsRefresh()
                    }
                    #expect(!manager.isConnected)
                    #expect(UserDefaults.standard.string(forKey: "hardware.hash") == nil)
                    // The host stays: PairedView shows "despareado" with "Parear".
                    #expect(UserDefaults.standard.string(forKey: "hardware.host") == "harvi-ab12.local")
                }
            }
        }
        
        @Test func otherErrorsKeepThePairing() async throws {
            await withSavedHardware(pairedPhone) {
                await withFakeHarvii({ _ in .failure(500) }) {
                    let manager = HardwareNetworkManager()
                    await #expect(throws: APIErrors.invalidResponse) {
                        _ = try await manager.deviceNeedsRefresh()
                    }
                    #expect(manager.isConnected)
                }
            }
        }
        
        @Test func unreachableHarviiIsANetworkError() async throws {
            // What pairingErrorMessage(for:) turns into "O Harvii não respondeu…".
            await withSavedHardware(pairedPhone) {
                await withFakeHarvii({ _ in nil }) {
                    await #expect(throws: URLError.self) {
                        _ = try await HardwareNetworkManager().deviceNeedsRefresh()
                    }
                }
            }
        }
        
        // MARK: - Image
        
        @Test func sendsTheImageWithTheHash() async throws {
            try await withSavedHardware(pairedPhone) {
                try await withFakeHarvii({ _ in .ok("Imagem desenhada") }) {
                    let image = Data(repeating: 0b0001_1011, count: 800 * 480 / 4)
                    try await HardwareNetworkManager().sendImageToDevice(imageData: image)
                    
                    let request = try #require(FakeHarviiProtocol.received.first)
                    #expect(request.request.httpMethod == "POST")
                    #expect(request.host == "harvi-ab12.local")
                    #expect(request.path == "/send_image")
                    #expect(request.header("X-Auth-Hash") == "abc123")
                    #expect(request.header("Content-Type") == "application/octet-stream")
                }
            }
        }
        
        @Test func imageOfTheWrongSizeIsNotSent() async throws {
            await withSavedHardware(pairedPhone) {
                await withFakeHarvii({ _ in .ok() }) {
                    await #expect(throws: APIErrors.invalidData) {
                        try await HardwareNetworkManager().sendImageToDevice(imageData: Data(count: 10))
                    }
                    #expect(FakeHarviiProtocol.received.isEmpty)
                }
            }
        }
        
        @Test func refusedImageIsAnError() async throws {
            await withSavedHardware(pairedPhone) {
                await withFakeHarvii({ _ in .failure(400, "Imagem incompleta") }) {
                    await #expect(throws: APIErrors.invalidResponse) {
                        try await HardwareNetworkManager().sendImageToDevice(imageData: Data(count: 800 * 480 / 4))
                    }
                }
            }
        }
        
        // MARK: - Reset
        
        @Test func resetForgetsTheHarviiOnThePhone() async throws {
            try await withSavedHardware(pairedPhone) {
                try await withFakeHarvii({ _ in .ok("Resetando") }) {
                    let manager = HardwareNetworkManager()
                    try await manager.resetDevice()
                    
                    let request = try #require(FakeHarviiProtocol.received.first)
                    #expect(request.request.httpMethod == "POST")
                    #expect(request.path == "/reset")
                    #expect(request.header("X-Auth-Hash") == "abc123")
                    
                    #expect(!manager.isConnected)
                    #expect(manager.host.isEmpty)
                    #expect(UserDefaults.standard.string(forKey: "hardware.hash") == nil)
                    #expect(UserDefaults.standard.string(forKey: "hardware.host") == nil)
                }
            }
        }
        
        @Test func failedResetKeepsThePairing() async throws {
            await withSavedHardware(pairedPhone) {
                await withFakeHarvii({ _ in nil }) {
                    let manager = HardwareNetworkManager()
                    await #expect(throws: URLError.self) {
                        try await manager.resetDevice()
                    }
                    #expect(manager.isConnected)
                }
            }
        }
        
        // MARK: - View model: Wi-Fi step
        
        @Test func sentWifiMovesOnToTheHomeNetworkStep() async throws {
            await withSavedHardware {
                await withFakeHarvii({ _ in .ok("ok", ["name": "harvi-ab12"]) }) {
                    let viewModel = HardwareViewModel()
                    viewModel.userWifiName = "Casa da Bela"
                    viewModel.userWifiPassord = "segredo123"
                    
                    await viewModel.sendWifiCredentials()
                    
                    #expect(viewModel.hostName == "harvi-ab12.local")
                    #expect(viewModel.wifiName == "Casa da Bela")
                    #expect(viewModel.navigateToReturnHouseNetworkView)
                    #expect(viewModel.wifiResult == nil)
                    #expect(!viewModel.isSending)
                }
            }
        }
        
        @Test func failedWifiShowsTheAlertAndStays() async throws {
            await withSavedHardware {
                await withFakeHarvii({ _ in nil }) {
                    let viewModel = HardwareViewModel()
                    viewModel.userWifiName = "Casa da Bela"
                    viewModel.userWifiPassord = "segredo123"
                    
                    await viewModel.sendWifiCredentials()
                    
                    #expect(viewModel.wifiResult == .failureWiFi)
                    #expect(!viewModel.navigateToReturnHouseNetworkView)
                    #expect(viewModel.hostName.isEmpty)
                    #expect(!viewModel.isSending)
                }
            }
        }
        
        @Test func waitingForTheDrawingAsksForTheStatus() async throws {
            await withSavedHardware(pairedPhone) {
                await withFakeHarvii({ _ in .ok("ok", ["needsRefresh": false]) }) {
                    await HardwareViewModel().waitForDeviceToFinishDrawing()
                    #expect(FakeHarviiProtocol.received.map(\.path) == ["/status"])
                }
            }
        }
    }
}
