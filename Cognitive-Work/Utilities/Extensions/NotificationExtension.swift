//
//  NotificationExtension.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 01/09/26.
//

import Foundation

/// Names of the app's internal notifications (`NotificationCenter`).
extension Notification.Name {
    /// The user opened an invite while already in a house. The object is the invite's `CKShare.Metadata`.
    static let notAcceptShare = Notification.Name("notAcceptShare")
    /// An invite was accepted; screens reload the new house.
    static let didAcceptShare = Notification.Name("didAcceptShare")
    /// Posted as soon as the user opens an invite link, before the (slow) share acceptance.
    static let willAcceptShare = Notification.Name("willAcceptShare")
    /// Posted when accepting an invite fails, so screens can drop their loading state.
    static let shareAcceptFailed = Notification.Name("shareAcceptFailed")
    /// Data in CloudKit changed (a push from another device, or a change made here); screens reload.
    static let cloudKitDidChange = Notification.Name("cloudKitDidChange")
}
