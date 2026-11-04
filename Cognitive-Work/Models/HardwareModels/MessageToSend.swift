//
//  MessageToSend.swift
//  Cognitive-Work
//
//  Created by Isabela Hissa Pinto on 25/08/26.
//

/// The body sent to the Harvii device to print two lines of text on its e-paper screen.
///
/// See ``HardwareNetworkManager/printMessageOnDevice(messageOne:messageTwo:)``.
struct MessageToSend: Codable {
    /// The pairing code that proves the message comes from a paired phone.
    let hash: String
    /// First line, printed in black.
    let messageOne: String
    /// Second line, printed in red.
    let messageTwo: String
}
