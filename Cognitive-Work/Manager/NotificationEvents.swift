//
//  NotificationEvents.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 27/10/26.
//

import CloudKit
import Foundation

/// The notifications caused by something one person did in the house.
///
/// Each one is saved in CloudKit for the people it concerns (see ``NotificationManager/send(_:)``).
/// The text travels as keys and values, so every device writes it in its own user's language.
extension NotificationManager {

    /// The admin generated a new division: tells the other members.
    /// - Parameter members: The house members. The current user is left out by ``send(_:)``.
    func notifyNewDivision(to members: [UserModel]) async {
        await sendEvent(
            kind: .newDivision,
            titleKey: Notifications.newDivision.rawValue,
            bodyKey: Notifications.newDivision.subTitle,
            recipientIDs: members.map(\.ownerRecordName)
        )
    }

    /// A member joined the house: tells the admin, who can redo the automatic division.
    /// - Parameters:
    ///   - name: The new member's name.
    ///   - houseID: The house's record ID. The owner of its zone is the admin.
    func notifyNewMember(named name: String, houseID: CKRecord.ID) async {
        let adminID = houseID.zoneID.ownerName
        // The zone is the current user's own: they created the house, nobody to tell.
        guard adminID != CKCurrentUserDefaultName else { return }
        
        await sendEvent(
            kind: .newUser,
            titleKey: "%@ entrou na casa",
            titleArgs: [name],
            bodyKey: "Refaça a divisão automática para incluir esse morador",
            recipientIDs: [adminID]
        )
    }

    /// The current user did a chore that was assigned to other people: tells them.
    /// - Parameters:
    ///   - chore: The chore that was done.
    ///   - assignment: Its occurrence, for recurring chores.
    ///   - doerName: The current user's name.
    ///   - owners: The members the chore was assigned to.
    func notifyChoreDone(
        _ chore: ChoreModel,
        assignment: RecurrentAssignmentModel?,
        by doerName: String,
        for owners: [UserModel]
    ) async {
        var extra: [AnyHashable: Any] = [:]
        if let name = chore.recordID?.recordName { extra[UserInfoKey.choreRecordName] = name }
        if let name = assignment?.recordID?.recordName { extra[UserInfoKey.assignmentRecordName] = name }
        
        await sendEvent(
            kind: .choreDoneForYou,
            titleKey: Notifications.choreDoneForYou.rawValue,
            titleArgs: [doerName, chore.name],
            bodyKey: Notifications.choreDoneForYou.subTitle,
            recipientIDs: owners.map(\.ownerRecordName),
            extra: extra
        )
    }

    /// The current user bought an item somebody else added to the shopping list: tells them.
    /// - Parameters:
    ///   - item: The item that was bought.
    ///   - buyerName: The current user's name.
    ///   - owner: The member who added the item.
    func notifyItemBought(_ item: ShopListItem, by buyerName: String, to owner: UserModel) async {
        await sendEvent(
            kind: .itemBought,
            titleKey: Notifications.itemBought.rawValue,
            titleArgs: [buyerName, item.name],
            bodyKey: Notifications.itemBought.subTitle,
            recipientIDs: [owner.ownerRecordName]
        )
    }

    // MARK: - Building

    /// Builds the notification and sends it. Does nothing without recipients.
    private func sendEvent(
        kind: Notifications,
        titleKey: String,
        titleArgs: [String] = [],
        bodyKey: String = "",
        bodyArgs: [String] = [],
        recipientIDs: [String],
        extra: [AnyHashable: Any] = [:]
    ) async {
        guard !recipientIDs.isEmpty else { return }
        
        var info = extra
        info[UserInfoKey.kind] = kind.rawValue
        info[UserInfoKey.titleKey] = titleKey
        info[UserInfoKey.titleArgs] = titleArgs
        info[UserInfoKey.bodyKey] = bodyKey
        info[UserInfoKey.bodyArgs] = bodyArgs
        
        // The title and body are only a fallback, in the sender's language.
        let dto = NotificationCloudDTO(
            title: Self.localized(titleKey, titleArgs),
            body: bodyKey.isEmpty ? "" : Self.localized(bodyKey, bodyArgs),
            threadIdentifier: "house",
            recipientIDs: recipientIDs,
            userInfo: info
        )
        _ = await send(dto)
    }
}
