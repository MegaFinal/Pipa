//
//  UserFacingError.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 09/10/26.
//

import Foundation
import CloudKit

/// Turns technical failures (CloudKit codes, schema messages, English log text) into short
/// sentences a person can understand. The technical detail is only printed, for debugging.
enum UserFacingError {

    /// What the app was doing when it failed; picks the sentence.
    enum Action {
        case create, load, save, delete, leave, share

        var message: String { fallback }

        fileprivate var fallback: String {
            switch self {
            case .create: return L10n.tr("Não foi possível criar. Tente novamente.")
            case .load: return L10n.tr("Não foi possível carregar os dados. Tente novamente.")
            case .save: return L10n.tr("Não foi possível salvar. Tente novamente.")
            case .delete: return L10n.tr("Não foi possível excluir. Tente novamente.")
            case .leave: return L10n.tr("Não foi possível sair da casa. Tente novamente.")
            case .share: return L10n.tr("Não foi possível compartilhar. Tente novamente.")
            }
        }
    }

    /// The message to show for `error` while doing `action`.
    static func message(for error: Error, doing action: Action = .save) -> String {
        print("[Error] \(action): \(error)")

        if let ckError = error as? CKError {
            switch ckError.code {
            case .networkUnavailable, .networkFailure:
                return L10n.tr("Sem conexão com a internet. Verifique sua rede e tente novamente.")
            case .notAuthenticated, .accountTemporarilyUnavailable:
                return L10n.tr("Entre na sua conta do iCloud para continuar.")
            case .quotaExceeded:
                return L10n.tr("O armazenamento do iCloud está cheio. Libere espaço para continuar.")
            case .requestRateLimited, .zoneBusy, .serviceUnavailable, .serverResponseLost:
                return L10n.tr("O serviço está ocupado agora. Tente novamente em instantes.")
            case .serverRecordChanged:
                return L10n.tr("Isso foi alterado em outro aparelho. Atualize a tela e tente novamente.")
            case .unknownItem, .zoneNotFound:
                return L10n.tr("Esse item não foi encontrado. Ele pode ter sido removido.")
            case .permissionFailure:
                return L10n.tr("Você não tem permissão para fazer isso.")
            default:
                return action.fallback
            }
        }

        if let urlError = error as? URLError,
           [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(urlError.code) {
            return L10n.tr("Sem conexão com a internet. Verifique sua rede e tente novamente.")
        }

        return action.fallback
    }

    /// For technical text that was already written as a string ("Failed to …").
    static func friendly(technical: String) -> String {
        print("[Error] \(technical)")
        let text = technical.lowercased()

        if text.contains("owner") {
            return L10n.tr("Quem criou a casa não pode sair dela.")
        }
        if text.contains("leave") { return Action.leave.fallback }
        if text.contains("share") { return Action.share.fallback }
        if text.contains("delete") { return Action.delete.fallback }
        if text.contains("fetch") || text.contains("load") || text.contains("list") { return Action.load.fallback }
        if text.contains("create") { return Action.create.fallback }
        return Action.save.fallback
    }
}
