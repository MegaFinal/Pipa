//
//  SceneDelegate.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 14/08/26.
//

import UIKit
import CloudKit

/// Handles house invites opened while the app is running.
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    
    /// The scene's window.
    var window: UIWindow?
    
    /// Accepts a house invite.
    ///
    /// If the user is already in a house, posts `.notAcceptShare` instead, so the app asks whether
    /// they want to switch houses. Houses the account is linked to without a member record are
    /// cleaned up first, so they don't block the invite.
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task {
            NotificationCenter.default.post(name: .willAcceptShare, object: nil)
            
            // A house this account is still attached to without being a member of it must not
            // block a new invitation.
            await CloudKitManager.shared.pruneOrphanedSharedMemberships()
            
            do {
                let _ = try await CloudKitManager.shared.fetchFirst(HouseModel.self)
                NotificationCenter.default.post(name: .notAcceptShare, object: cloudKitShareMetadata)
            }
            catch {
                let success = await CloudKitManager.shared.acceptShare(metadata: cloudKitShareMetadata)
                if success {
                    NotificationCenter.default.post(name: .didAcceptShare, object: nil)
                } else {
                    NotificationCenter.default.post(name: .shareAcceptFailed, object: nil)
                }
            }
        }
    }
}
