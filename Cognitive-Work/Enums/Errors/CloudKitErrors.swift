//
//  CloudKitErrors.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 12/08/26.
//

import Foundation
import CloudKit

/// Errors that can occur while retrieving houses and interacting with CloudKit.
///
/// Each case has a translated message (``errorDescription``) ready to show to the user.
/// `T` is the type of the value the failed operation was about (for example, a house ID).
enum CloudKitErrors<T>: Error, LocalizedError {
    
    /// The record does not exist (it may have been deleted). Carries what was looked for.
    case notFound(T)
    /// The user is not allowed to do this (for example, a guest editing the house). Carries what was asked.
    case notAuthorized(T)
    /// The share link of the house could not be created.
    case missingShareURL
    /// The device is offline.
    case networkUnavailable
    /// The user's iCloud storage is full.
    case quotaExceeded
    /// The record was changed on another device while saving, twice in a row, so the save gave up.
    case recordChangedTwice
    /// The house's record zone does not exist (it may have been deleted).
    case zoneNotFound
    /// Too many requests were sent to CloudKit; try again later.
    case limitExceeded
    /// Any other error, kept as it came.
    case underlying(Error)
    /// The person who created the house tried to leave it, which is not allowed.
    case currentHouseOwnerCannotLeaveTheHouse

    /// A short, user-facing message for the error, already translated.
    var errorDescription: String? {
        switch self {
        case .notFound:
            return L10n.tr("Não encontramos esses dados. Eles podem ter sido removidos.")
            
        case .notAuthorized:
            return L10n.tr("Você não tem permissão para fazer isso.")
            
        case .missingShareURL:
            return L10n.tr("Missing share URL. Não foi possível gerar o link de compartilhamento.")
            
        case .networkUnavailable:
            return L10n.tr("Sem conexão com a internet.")
            
        case .quotaExceeded:
            return L10n.tr("O armazenamento do iCloud do usuário está cheio. Libere espaço para continuar.")
            
        case .recordChangedTwice:
            return L10n.tr("Conflito: Este registro foi modificado recentemente em outro dispositivo. A operação foi cancelada para evitar perda de dados.")
            
        case .zoneNotFound:
            return L10n.tr("A zona de registros não foi encontrada. Ela pode ter sido apagada ou não sincronizada.")
            
        case .limitExceeded:
            return L10n.tr("O limite de requisições da Apple foi excedido. Tente novamente mais tarde.")
            
        case .underlying(let error):
            return UserFacingError.message(for: error)
        case .currentHouseOwnerCannotLeaveTheHouse:
            return L10n.tr("Quem criou a casa não pode sair dela.")
        }
    }
}
