//
//  HarviiPairingStateTests.swift
//  Cognitive-WorkTests
//
//  Created by Isabela Hissa Pinto on 03/11/26.
//

import Testing
import Foundation
@testable import Cognitive_Work

/// Checks that the pairing with the Harvii is kept on the phone (``PairedView`` reads it from
/// ``HardwareViewModel/isPaired``) and that the setup starts clean every time it opens.
///
/// Serialized: the tests use the real `UserDefaults` keys and put the original values back.
@Suite(.serialized)
struct HarviiPairingStateTests {

    /// The keys ``HardwareNetworkManager`` saves on the phone.
    private static let keys = ["hardware.hash", "hardware.host", "hardware.name"]

    /// Runs `body` with `values` saved under the hardware keys, restoring the originals afterwards.
    private func withSaved(_ values: [String: String?], _ body: () -> Void) {
        let defaults = UserDefaults.standard
        let previous = Self.keys.map { ($0, defaults.object(forKey: $0)) }
        for key in Self.keys {
            if let value = values[key] ?? nil {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        defer {
            for (key, value) in previous { defaults.set(value, forKey: key) }
        }
        body()
    }

    // MARK: - Pairing kept on the phone

    @Test func savedPairingIsRestored() {
        withSaved(["hardware.hash": "abc123", "hardware.host": "harvi-ab12.local", "hardware.name": "Casa da Bela"]) {
            let viewModel = HardwareViewModel()
            #expect(viewModel.isPaired)
            #expect(viewModel.hostName == "harvi-ab12.local")
            #expect(viewModel.wifiName == "Casa da Bela")
        }
    }

    @Test func nothingSavedMeansNotPaired() {
        withSaved([:]) {
            let viewModel = HardwareViewModel()
            #expect(!viewModel.isPaired)
            #expect(viewModel.hostName.isEmpty)
            #expect(viewModel.wifiName.isEmpty)
        }
    }

    @Test func hashWithoutHostIsNotAPairing() {
        withSaved(["hardware.hash": "abc123"]) {
            #expect(!HardwareViewModel().isPaired)
        }
    }

    @Test func hostWithoutHashIsSetUpButNotPaired() {
        // The Wi-Fi was sent, but this phone didn't pair: PairedView shows "despareado".
        withSaved(["hardware.host": "harvi-ab12.local"]) {
            let viewModel = HardwareViewModel()
            #expect(!viewModel.isPaired)
            #expect(viewModel.hostName == "harvi-ab12.local")
        }
    }

    @Test func unpairingIsKeptAfterReopening() {
        withSaved(["hardware.hash": "abc123", "hardware.host": "harvi-ab12.local"]) {
            let viewModel = HardwareViewModel()
            viewModel.disconnectThisPhone()
            #expect(!viewModel.isPaired)

            // A new view model reads the phone again, like the app reopening.
            #expect(!HardwareViewModel().isPaired)
            #expect(UserDefaults.standard.string(forKey: "hardware.hash") == nil)
        }
    }

    // MARK: - Setup starts clean

    @Test func resetNavigationClearsTheSetup() {
        let viewModel = HardwareViewModel()
        viewModel.navigateToEnterHarviiNetworkView = true
        viewModel.navigateToWifiCredentialsView = true
        viewModel.navigateToReturnHouseNetworkView = true
        viewModel.navigateToConnectionHarviiView = true
        viewModel.conectionResult = .failureParing
        viewModel.pairingErrorDetail = "Erro"
        viewModel.wifiResult = .failureWiFi

        viewModel.resetNavigation()

        #expect(!viewModel.navigateToEnterHarviiNetworkView)
        #expect(!viewModel.navigateToWifiCredentialsView)
        #expect(!viewModel.navigateToReturnHouseNetworkView)
        #expect(!viewModel.navigateToConnectionHarviiView)
        #expect(viewModel.conectionResult == nil)
        #expect(viewModel.pairingErrorDetail == nil)
        #expect(viewModel.wifiResult == nil)
    }
}
