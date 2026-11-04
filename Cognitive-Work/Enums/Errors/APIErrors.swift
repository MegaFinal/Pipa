//
//  APIErrors.swift
//  Cognitive-Work
//
//  Created by Isabela Hissa Pinto on 25/08/26.
//

/// Errors that can happen while the app talks to the external device (the ESP32 "Harvii") over the local network.
import Foundation
enum APIErrors: String, Error {
    /// The data to send could not be turned into JSON.
    case unableToEncode
    /// The device address (IP) could not be turned into a valid URL.
    case invalidURL
    /// The device answered, but not with a successful HTTP response.
    case invalidResponse
    /// The device answered with data in an unexpected format.
    case invalidData
    /// Something failed and the cause is not known.
    case unknownError
    
    /// A short, user-facing message for the error, already translated.
    var errorDescription: String? {
        switch self {
        case .invalidURL:      return L10n.tr("Não foi possível encontrar o dispositivo externo. Confira o IP.")
        case .unableToEncode:  return L10n.tr("Erro ao preparar os dados.")
        case .invalidResponse: return L10n.tr("O dispositivo externo não respondeu como esperado.")
        case .invalidData:     return L10n.tr("Resposta do dispositivo externo em formato inesperado.")
        case .unknownError: return L10n.tr("Erro desconhecido.")
        }
    }
}
