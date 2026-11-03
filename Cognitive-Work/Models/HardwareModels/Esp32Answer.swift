//
//  Esp32Answer.swift
//  Cognitive-Work
//
//  Created by Isabela Hissa Pinto on 25/08/26.
//

/// What the Harvii device (an ESP32) answers to every request.
struct Esp32Answer: Decodable {
    /// Whether the device did what was asked.
    let success: Bool
    /// A short text from the device explaining the result.
    let message: String
    /// The device's network name, when the request was about it.
    let name: String?
    /// Whether the device's screen lost the chart and needs it again (after a reboot, for example).
    /// Only sent by the status request.
    let needsRefresh: Bool?
}
