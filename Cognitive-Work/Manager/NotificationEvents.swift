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

    /// The current user is a guest who chose their free time and is waiting for the division:
    /// tells the admin, who is the only one who can divide the chores.
    ///
    /// Sent from the waiting screen of the onboarding. ``notifyNewMember(named:houseID:)`` goes out
    /// earlier, when the guest joins, before their free time is known.
    /// - Parameters:
    ///   - name: The guest's name.
    ///   - houseID: The house's record ID. The owner of its zone is the admin.
    /// - Returns: Whether the notification was saved (also `true` when the user is the admin, who
    ///   has nobody to tell).
    @discardableResult
    func notifyGuestWaitingForDivision(named name: String, houseID: CKRecord.ID) async -> Bool {
        let adminID = houseID.zoneID.ownerName
        guard adminID != CKCurrentUserDefaultName else { return true }

        return await sendEvent(
            kind: .guestWaitingDivision,
            titleKey: Notifications.guestWaitingDivision.rawValue,
            titleArgs: [name],
            bodyKey: Notifications.guestWaitingDivision.subTitle,
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

    /// The current user bought items `member` pays a part of, checked off on the list (one
    /// shopping trip, see ``BoughtItemsNotifier``) or with a scanned receipt: tells them what
    /// was bought for them and their part. Only who has something to pay hears about it.
    ///
    /// - "Ana comprou Leite para você" / "Sua parte: R$ 4,50"
    /// - "Ana comprou Leite e Pão para você" / "Sua parte: R$ 9,00"
    /// - "Ana comprou 5 itens para você" / "Sua parte: R$ 32,40"
    ///
    /// - Parameters:
    ///   - itemNames: The items `member` shares, in the order they were bought.
    ///   - share: Their part, already formatted ("R$ 32,40").
    ///   - buyerName: The current user's name.
    ///   - member: Who pays the part.
    ///   - fromReceipt: Bought with a scanned receipt: the notification shows the receipt's icon
    ///     instead of the cart.
    func notifyBoughtForYou(
        _ itemNames: [String],
        share: String,
        by buyerName: String,
        to member: UserModel,
        fromReceipt: Bool
    ) async {
        let names = itemNames
        guard let first = names.first, !member.ownerRecordName.isEmpty else { return }

        let titleKey: String
        let titleArgs: [String]
        switch names.count {
        case 1:
            titleKey = Notifications.boughtForYou.rawValue
            titleArgs = [buyerName, first]
        case 2:
            titleKey = "%@ comprou %@ e %@ para você"
            titleArgs = [buyerName, names[0], names[1]]
        default:
            titleKey = "%@ comprou %@ itens para você"
            titleArgs = [buyerName, String(names.count)]
        }

        await sendEvent(
            kind: fromReceipt ? .receiptBoughtForYou : .boughtForYou,
            titleKey: titleKey,
            titleArgs: titleArgs,
            bodyKey: "Sua parte: %@",
            bodyArgs: [share],
            recipientIDs: [member.ownerRecordName]
        )
    }

    /// The member who paid for Premium is leaving: tells the others that the house is back on
    /// the free plan and someone else needs to subscribe. Sent before leaving, while the house
    /// can still be written to.
    /// - Parameters:
    ///   - payerName: The name of the person leaving.
    ///   - members: The house members. The current user is left out by ``send(_:)``.
    func notifyPremiumEnded(payerName: String, to members: [UserModel]) async {
        await sendEvent(
            kind: .premiumEnded,
            titleKey: Notifications.premiumEnded.rawValue,
            titleArgs: [payerName],
            bodyKey: Notifications.premiumEnded.subTitle,
            recipientIDs: members.map(\.ownerRecordName)
        )
    }

    // MARK: - Building

    /// Builds the notification and sends it. Does nothing without recipients.
    /// - Returns: Whether it was saved (`false` also without recipients).
    @discardableResult
    private func sendEvent(
        kind: Notifications,
        titleKey: String,
        titleArgs: [String] = [],
        bodyKey: String = "",
        bodyArgs: [String] = [],
        recipientIDs: [String],
        extra: [AnyHashable: Any] = [:]
    ) async -> Bool {
        guard !recipientIDs.isEmpty else { return false }
        
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
        return await send(dto)
    }
}
