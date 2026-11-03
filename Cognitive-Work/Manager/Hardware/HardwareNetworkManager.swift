//
//  HardwareNetworkManager.swift
//  Cognitive-Work
//
//  Created by Isabela Hissa Pinto on 25/08/26.
//

import Foundation

/// Handles every HTTP call to the ESP32 device.
///
/// The device is reached over the local network, so every endpoint is built as
/// "http://" + the device's IP + the route. There are three phases:
///
/// 1. Provisioning — the ESP32 is its own access point and receives the home WiFi credentials
/// 2. Pairing — the app asks for the hash the device generated at boot and keeps it
/// 3. Use — text and images are sent, authenticated by that hash
@Observable
class HardwareNetworkManager {
    /// Fixed address of the ESP32 while it is its own access point (the library default).
    let accessPointIP: String = "192.168.4.1"
    
    /// The device's IP. Typed by the user while the ESP32 is still an access point
    /// (usually 192.168.4.1), then replaced by the address it gets on the home network.
    var host: String = ""
    
    /// Sends the HTTP requests to the device.
    private var session = URLSession.shared
    /// Reads the device's JSON answers.
    private var decoder = JSONDecoder()
    
    /// Scheme prefix. Plain HTTP because the ESP32 has no certificate.
    private var base: String = "http://"
    
    /// Pairing token received from /ask_code. Proves to the device that requests
    /// come from this app and not from another machine on the same network.
    private var hash: String = ""
    
    private(set) var wifiName = ""
    
    /// Whether the phone is paired with the device (it has a pairing code).
    private(set) var isConnected: Bool = false
    
    // MARK: - Hash Persistence
    
    /// Where the device's address and pairing code are saved on the phone.
    private var localPersistence = UserDefaults.standard
    
    /// Keys used in ``localPersistence``.
    private enum StorageKey {
        static let hash = "hardware.hash"
        static let host = "hardware.host"
        static let wifiName = "hardware.name"
    }
    
    /// Restores the saved device address and pairing code, if any.
    init() {
        // The host is saved right after provisioning, even before pairing succeeds
        if let savedHost = localPersistence.string(forKey: StorageKey.host) {
            self.host = savedHost
        }
        if let savedHash = localPersistence.string(forKey: StorageKey.hash), !host.isEmpty {
            self.hash = savedHash
            self.isConnected = true
        }
        if let savedWifiName = localPersistence.string(forKey: StorageKey.wifiName) {
            self.wifiName = savedWifiName
        }
    }
    
    // MARK: - Provisioning
    
    /// Sends the user's home WiFi credentials so the device can leave access point mode.
    ///
    /// After this call the ESP32 drops its own network and joins the one given here,
    /// which means its IP changes and this service must be pointed at the new address.
    ///
    /// - Parameters:
    ///   - ssid: Name of the network the device should join.
    ///   - password: Password of that network.
    /// - Throws: ``APIErrors/invalidURL`` if the IP produces a malformed endpoint,
    ///   ``APIErrors/unableToEncode`` if the credentials can't be turned into JSON,
    ///   ``APIErrors/invalidResponse`` if the device answers with anything other than 200,
    ///   ``APIErrors/invalidData`` if the body doesn't match ``Esp32Answer``.
    func sendWifiCredentials(ssid: String, password: String) async throws -> String {
        let route = "/save_wifi"
        let endpoint = base + self.accessPointIP + route
        let wifi = WifiCredentials(ssid: ssid, password: password)
        
        guard let url = URL(string: endpoint) else {
            throw APIErrors.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Encodes the credentials into the request body
        do {
            let jsonData = try JSONEncoder().encode(wifi)
            request.httpBody = jsonData
        } catch {
            throw APIErrors.unableToEncode
        }
        
        let (data, response) = try await session.data(for: request)
        
        // The ESP32 answers 200 before actually connecting, since connecting
        // tears down the access point and this response would never arrive
        let answer = try validate(data: data, response: response)
        
        // Saves the host (harvi) name
        guard let name = answer.name else { throw APIErrors.invalidData }
        self.host = name + ".local"
        localPersistence.set(host, forKey: StorageKey.host)
        localPersistence.set(wifiName, forKey: StorageKey.wifiName)
        
        return self.host
    }
    
    // MARK: - Pairing
    
    /// Finds the device by its network name and stores its pairing hash.
    ///
    /// Retries a few times: right after provisioning the device may still be joining the network.
    func askForParingCode() async throws {
        guard !host.isEmpty, let url = URL(string: base + host + "/ask_code") else {
            throw APIErrors.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data()
        request.timeoutInterval = 15
        
        for attempt in 1...6 {
            do {
                let (data, response) = try await session.data(for: request)
                let answer = try validate(data: data, response: response)
                
                hash = answer.message
                isConnected = true
                localPersistence.set(hash, forKey: StorageKey.hash)
                localPersistence.set(host, forKey: StorageKey.host)
                return
            } catch is URLError where attempt < 6 {
                try await Task.sleep(for: .seconds(3))
            }
        }
    }
    
    // MARK: - Status
    
    /// Asks the device whether its screen lost the chart (after a reboot or a reconnection).
    ///
    /// Also works as an "am I at home?" check: away from the home network it throws.
    func deviceNeedsRefresh() async throws -> Bool {
        guard !host.isEmpty, let url = URL(string: base + host + "/status") else {
            throw APIErrors.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(hash, forHTTPHeaderField: "X-Auth-Hash")
        request.timeoutInterval = 15
        
        let (data, response) = try await session.data(for: request)
        let answer = try validate(data: data, response: response)
        return answer.needsRefresh ?? false
    }
    
    // MARK: - Sending content
    
    /// Prints two lines of text on the e-paper: the first in black, the second in red.
    ///
    /// Unlike ``sendImageToDevice(imageData:)``, the hash goes inside the JSON body here
    /// rather than in a header.
    ///
    /// - Parameters:
    ///   - messageOne: Text of the first line (black).
    ///   - messageTwo: Text of the second line (red).
    /// - Throws: ``APIErrors/invalidURL``, ``APIErrors/unableToEncode``,
    ///   ``APIErrors/invalidResponse``, ``APIErrors/invalidData``.
    func printMessageOnDevice(messageOne: String, messageTwo: String) async throws {
        let route = "/send_text"
        let endpoint = self.base + self.host + route
        
        // The hash is part of the payload, alongside the two lines
        let message = MessageToSend(hash: hash, messageOne: messageOne, messageTwo: messageTwo)
        
        guard let url = URL(string: endpoint) else {
            throw APIErrors.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let jsonData = try JSONEncoder().encode(message)
            request.httpBody = jsonData
        } catch {
            throw APIErrors.unableToEncode
        }
        
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
    }
    
    /// Sends a 1 bit per pixel bitmap to be drawn on the e-paper.
    ///
    /// The body is base64 rather than raw binary: the ESP32's WebServer stores the request body
    /// in a C string, which stops at the first 0x00 byte — and a bitmap is full of zeroed bytes
    /// wherever the image is white. Base64 only uses printable characters, so it survives that.
    /// The 33% size increase is irrelevant over a local network.
    ///
    /// Because the body is entirely image data, there is no room for a JSON envelope, so the
    /// hash travels in the X-Auth-Hash header instead.
    ///
    /// - Parameters:
    ///   - imageData: The 4,736 bytes produced by `prepareForEPaper` or `ditheringBitmap`.
    /// - Throws: ``APIErrors/invalidURL``, ``APIErrors/invalidResponse``, ``APIErrors/invalidData``.
    func sendImageToDevice(imageData: Data) async throws {
        guard imageData.count == 800 * 480 / 4 else { throw APIErrors.invalidData }
        
        let endpoint = self.base + self.host + "/send_image"
        guard let url = URL(string: endpoint) else { throw APIErrors.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(self.hash, forHTTPHeaderField: "X-Auth-Hash")
        request.timeoutInterval = 60
        
        // The transfer can drop halfway on a weak signal: retry a couple of times before giving up
        for attempt in 1...3 {
            do {
                let (data, response) = try await session.upload(for: request, from: imageData)
                try validate(data: data, response: response)
                return
            } catch is URLError where attempt < 3 {
                print("Image upload failed (attempt \(attempt)), retrying...")
                try await Task.sleep(for: .seconds(2))
            }
        }
    }
    
    // MARK: - Reset
    
    /// Asks the device to wipe its WiFi credentials and hash, then forgets the local pairing.
    ///
    /// The ESP32 answers before restarting and comes back in access point mode,
    /// so provisioning and pairing must be done again.
    func resetDevice() async throws {
        let endpoint = base + host + "/reset"
        guard let url = URL(string: endpoint) else { throw APIErrors.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(hash, forHTTPHeaderField: "X-Auth-Hash")
        request.httpBody = Data()
        
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
        
        forgetDevice()
    }
    
    /// Clears the pairing on this iPhone only. Also useful when the device was reset
    /// by its button and can no longer be reached.
    func forgetDevice() {
        hash = ""
        host = ""
        isConnected = false
        localPersistence.removeObject(forKey: StorageKey.hash)
        localPersistence.removeObject(forKey: StorageKey.host)
    }
    
    // MARK: - Response handling
    
    /// Validates the device's answer and decodes the standard envelope.
    ///
    /// A 401 means the hash no longer matches — usually because the ESP32 rebooted and
    /// generated a new one — so the pairing is dropped and the app must pair again.
    ///
    /// - Parameters:
    ///   - data: Raw body returned by the request.
    ///   - response: The URLResponse to validate.
    /// - Returns: The decoded ``Esp32Answer``.
    /// - Throws: ``APIErrors/invalidResponse`` for any status other than 200,
    ///   ``APIErrors/invalidData`` if the body doesn't match ``Esp32Answer``.
    @discardableResult
    private func validate(data: Data, response: URLResponse) throws -> Esp32Answer {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIErrors.invalidResponse
        }
        
        if httpResponse.statusCode == 401 {
            isConnected = false
            hash = ""
            localPersistence.removeObject(forKey: StorageKey.hash)
            throw APIErrors.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIErrors.invalidResponse
        }
        
        do {
            return try decoder.decode(Esp32Answer.self, from: data)
        } catch {
            throw APIErrors.invalidData
        }
    }
}
