//
//  WifiCredentials.swift
//  Cognitive-Work
//
//  Created by Isabela Hissa Pinto on 25/08/26.
//

/// The home Wi-Fi name and password, sent to the Harvii device so it can join the network.
struct WifiCredentials: Codable {
    /// The Wi-Fi network name.
    let ssid: String
    /// The Wi-Fi password.
    let password: String
}
