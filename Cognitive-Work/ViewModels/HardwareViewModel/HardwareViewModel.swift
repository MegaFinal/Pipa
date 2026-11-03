//
//  WifiConnectionViewModel.swift
//  Cognitive-Work
//
//  Created by Isabela Hissa Pinto on 25/08/26.
//

import SwiftUI
import UIKit
import CloudKit

/// A view model that manages hardware connectivity and data transmission for an ESP32 device.
@Observable
class HardwareViewModel {
    
    // MARK: - Device Connection & Pairing (IP & Wi-Fi)
    
    /// The host name  of the target hardware device.
    var hostName = ""
    
    /// The device's host name as saved in CloudKit for the house.
    var hardwareHostName: HardwareHostNameModel?
    
    /// The user's house.
    var house: HouseModel?
    
    /// The name (SSID) of the user's local Wi-Fi network.
    var userWifiName = ""
    
    /// The password for the user's local Wi-Fi network.
    var userWifiPassord = ""
    
    /// A boolean value indicating whether the Wi-Fi password is visible in the UI.
    var isPasswordVisible = false
    
    /// A flag indicating whether to navigate to the pairing view.
    var navigateToParingView: Bool = false
    
    /// An optional error message capturing the latest failure state.
    var errorMessage: String?
    
    /// `true` while pairing with the device.
    var isPairing = false
    /// Result of the last pairing attempt, shown on the pairing screen.
    var conectionResult: ConectionResult?
    /// `true` while sending data to the device.
    var isSending = false

    /// Result shown on the WiFi screen (failure only; success just moves on to pairing).
    var wifiResult: ConectionResult?

    /// Whether this phone already has a pairing hash for the device.
    var isPaired: Bool { hardwareNetworkManager.isConnected }
    
    /// Talks to the device over the local network.
    private var hardwareNetworkManager = HardwareNetworkManager()
    
    /// Loads the saved device address.
    init() {
        hostName = hardwareNetworkManager.host
    }
    
    //MARK: - Connection with Esp32
    
    /// Sends the WiFi credentials over the ESP32 network, keeps the returned host name and moves to pairing.
    func sendWifiCredentials() async {
        isSending = true
        defer { isSending = false }

        do {
            hostName = try await hardwareNetworkManager.sendWifiCredentials(
                ssid: userWifiName,
                password: userWifiPassord
            )
            navigateToParingView = true
        } catch {
            wifiResult = .failureWiFi
        }
    }

    /// Asks the device for its hash, saves the host name for the other users and shows the result alert.
    func pair() async {
        isPairing = true

        do {
            hardwareNetworkManager.host = hostName
            try await hardwareNetworkManager.askForParingCode()

            if !(await createHostName()) {
                print("Paired, but the host name was not saved to CloudKit")
            }
            conectionResult = .success
        } catch {
            conectionResult = .failureParing
        }
        isPairing = false

        if conectionResult == .success {
            await HardwareViewModel.deliverNow()
        }
    }
    
    /// Outcome of a pairing attempt, used to drive the result alert.
    enum ConectionResult {
        /// The phone paired with the device.
        case success
        /// The device couldn't join the Wi-Fi.
        case failureWiFi
        /// The device joined the Wi-Fi, but pairing failed.
        case failureParing

        /// The alert's title for this result, translated.
        var title: String {
            switch self {
            case .success: L10n.tr("Pareamento completo!")
            case .failureWiFi: L10n.tr("Falha na conexão")
            case .failureParing: L10n.tr("Falha no pareamento")
            }
        }

        var message: String {
            switch self {
            case .success: L10n.tr("Seu pareamento foi concluído com sucesso, agora seu celular está conectado ao Harvii!")
            case .failureWiFi: L10n.tr("Não conseguimos enviar os dados para o Harvii. Confira se o seu celular está conectado à rede HARVII e tente novamente.")
            case .failureParing: L10n.tr("Certifique-se que o Harvii está conectado no WiFi e tente novamente.")
            }
        }
    }
    
    // MARK: - Background delivery

    /// `UserDefaults` key of the "device is missing changes" flag.
    private static let pendingUpdateKey = "hardware.pendingUpdate"

    /// Marks that the device is missing the latest changes. Delivered on the next chance
    /// (app opening, silent push or background refresh), as soon as this phone is at home.
    static func markPendingUpdate() {
        UserDefaults.standard.set(true, forKey: pendingUpdateKey)
    }

    /// Sends the chart when this phone has pending changes or the device lost its screen.
    ///
    /// Asks iOS for extra time, so a send started right before the user leaves the app
    /// still finishes in the background.
    @MainActor
    func refreshDeviceIfNeeded() async {
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "HarviRefresh")
        defer { UIApplication.shared.endBackgroundTask(backgroundTask) }

        guard isPaired else { return }

        let hasPendingUpdate = UserDefaults.standard.bool(forKey: Self.pendingUpdateKey)

        do {
            let deviceLostChart = try await hardwareNetworkManager.deviceNeedsRefresh()
            guard hasPendingUpdate || deviceLostChart else { return }

            try await sendChartToESP32()
            UserDefaults.standard.set(false, forKey: Self.pendingUpdateKey)
        } catch {
            print("Device refresh failed: \(error)")
        }
    }
    
    // MARK: - Delivery queue

    /// Waits for changes to settle, so close changes (e.g. Chore + DailyAssignment) become one send.
    @MainActor private static var settleTask: Task<Void, Never>?

    /// The send in progress, if any. Only one at a time.
    @MainActor private static var deliveryTask: Task<Void, Never>?

    /// Set when something changed during a send: one more send runs at the end with the latest data.
    @MainActor private static var needsAnotherSend = false

    /// Call after any change saved to CloudKit (or received through a silent push).
    ///
    /// Marks the change as pending and delivers it 2 seconds after the last change.
    @MainActor
    static func notifyDataChanged() {
        markPendingUpdate()

        settleTask?.cancel()
        settleTask = Task {
            try? await Task.sleep(for: .nanoseconds(1))
            guard !Task.isCancelled else { return }
            startDelivery()
        }
    }

    /// Delivers right away (app opening, background refresh) through the same queue.
    @MainActor
    static func deliverNow() async {
        startDelivery()
        await deliveryTask?.value
    }

    /// Waits for any scheduled or running delivery. Used by the silent push,
    /// so iOS keeps the app awake until the chart is sent.
    @MainActor
    static func waitForPendingDelivery() async {
        await settleTask?.value
        await deliveryTask?.value
    }

    /// Starts a send, or, if one is already running, asks it to run once more at the end.
    @MainActor
    private static func startDelivery() {
        guard deliveryTask == nil else {
            needsAnotherSend = true
            return
        }

        deliveryTask = Task {
            repeat {
                needsAnotherSend = false
                await HardwareViewModel().refreshDeviceIfNeeded()
            } while needsAnotherSend

            deliveryTask = nil
        }
    }
    
    // MARK: - Image & Chart Transmission (ESP32 Display)
    
    /// Renders the daily chores dashboard (``HardwareDailyChoresView``) and streams it as an
    /// e-paper compatible image to the ESP32.
    ///
    /// - Throws: An error if rendering fails or if the network transmission is interrupted.
    @MainActor
    func sendChartToESP32() async throws {
        let choresViewModel = HardwareDailyChoresViewModel()
        await choresViewModel.setup()

        // ImageRenderer draws outside the app's view tree, so it doesn't inherit the
        // in-app language set at the root: pass it explicitly.
        let chartView = HardwareDailyChoresView(viewModel: choresViewModel)
            .frame(width: 800, height: 480)
            .environment(\.locale, L10n.locale)

        let renderer = ImageRenderer(content: chartView)
        renderer.scale = 1.0
        
        guard let image = renderer.uiImage else {
            throw NSError(domain: "HardwareViewModel", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Failed to render the chart view."])
        }
        // The dashboard uses the in-between tones to tell the rooms apart.
        guard let imageData = image.levelBitmap4Gray(halfTones: true) else {
            throw NSError(domain: "HardwareViewModel", code: 1002, userInfo: [NSLocalizedDescriptionKey: "Failed to convert the chart image into e-paper format."])
        }
        
        try await hardwareNetworkManager.sendImageToDevice(imageData: imageData)
    }
    
    /// Prepares and sends a static image (rendered from a SwiftUI View) to the ESP32.
    func prepareImageForESP32<Content: View>(view: Content) async throws {
        let renderer = ImageRenderer(content: view.environment(\.locale, L10n.locale))
        renderer.scale = 1.0
        
        guard let image = renderer.uiImage else {
            throw NSError(
                domain: "HardwareViewModel",
                code: 1003,
                userInfo: [NSLocalizedDescriptionKey: "Falha ao renderizar a view em imagem."]
            )
        }
        guard let imageData = image.levelBitmap4Gray() else {
            throw NSError(
                domain: "HardwareViewModel",
                code: 1004,
                userInfo: [NSLocalizedDescriptionKey: "Falha ao converter imagem para o formato do e-paper."]
            )
        }
        try await hardwareNetworkManager.sendImageToDevice(imageData: imageData)
    }
    //MARK: - Cloudkit
    
    /// Makes sure the house has the device's host name in CloudKit, so the other users can pair.
    ///
    /// Reuses the existing record when it already has this name, replaces it when the house
    /// switched devices, and only creates a new one when there is none.
    @MainActor
    func createHostName() async -> Bool {
        errorMessage = nil

        if let existing = try? await CloudKitManager.shared.fetchFirst(HardwareHostNameModel.self) {
            if existing.hostName == hostName {
                hardwareHostName = existing
                return true
            }
            await CloudKitManager.shared.delete(existing)
        }

        house = try? await CloudKitManager.shared.fetchFirst(HouseModel.self)

        guard let houseRecordID = house?.recordID else {
            errorMessage = L10n.tr("Casa não encontrada.")
            return false
        }

        let houseReference = CKRecord.Reference(recordID: houseRecordID, action: .none)
        let model = HardwareHostNameModel(hostName: hostName)

        guard let created = await CloudKitManager.shared.create(
            model,
            zoneID: houseRecordID.zoneID,
            parent: houseReference
        ) else {
            errorMessage = L10n.tr("Erro ao criar nome do host (Harvii).")
            return false
        }

        hardwareHostName = created
        return true
    }
    
    /// Loads the host name saved by whoever set up the device. Skipped when it is already known.
    func fetchHostName() async {
        guard hostName.isEmpty else { return }
        errorMessage = nil

        do {
            hardwareHostName = try await CloudKitManager.shared.fetchFirst(HardwareHostNameModel.self)
            hostName = hardwareHostName?.hostName ?? ""
        } catch {
            errorMessage = UserFacingError.message(for: error, doing: .load)
        }
    }
    
    /// Deletes the current IP record and clears local state so the UI reflects the change immediately.
    func deleteHostName() async {
        guard let hardwareHostName else { return }

        await CloudKitManager.shared.delete(hardwareHostName)
        
        self.hardwareHostName = nil
        self.hostName = ""
    }
    
    // MARK: - Disconnect & Reset

    /// Forgets the pairing on this phone only. The device and the other users are not affected,
    /// and the host name stays, so this phone can pair again later.
    func disconnectThisPhone() {
        hardwareNetworkManager.forgetDevice()
    }

    /// Wipes the device (WiFi and hash) and removes its host name from CloudKit for the whole house.
    ///
    /// Afterwards the ESP32 is back in access point mode and must be set up again.
    func resetHardware() async throws {
        try await hardwareNetworkManager.resetDevice()
        await deleteHostName()
    }
}

extension View {
    /// Shows the result alert of a hardware step. "Voltar" runs `onSuccess` only when it succeeded.
    func resultAlert(
        _ result: Binding<HardwareViewModel.ConectionResult?>,
        onSuccess: @escaping () -> Void = {}
    ) -> some View {
        alert(
            result.wrappedValue?.title ?? "",
            isPresented: Binding(
                get: { result.wrappedValue != nil },
                set: { if !$0 { result.wrappedValue = nil } }
            ),
            presenting: result.wrappedValue
        ) { value in
            Button("Voltar", role: .cancel) {
                if value == .success { onSuccess() }
            }
        } message: { value in
            Text(value.message)
        }
    }
}
