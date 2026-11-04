//
//  ShopDebt.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 08/10/26.
//

import Foundation
import CloudKit

/// Whose side of a debt the screen is showing.
enum DebtDirection: CaseIterable, Identifiable {
    /// Items bought by a housemate for the signed-in user (the user owes them).
    case youOwe

    /// Items bought by the signed-in user for a housemate (the housemate owes the user).
    case owedToYou

    /// Identifier for SwiftUI lists (the case itself).
    var id: Self { self }
}

/// One item's share of a debt.
struct DebtEntry: Identifiable {
    /// The bought item this share comes from.
    let item: ShopListItem

    /// Who owes this share: the one whose payment settles it.
    let debtor: CKRecord.ID

    /// The share of the item's price (split equally between everyone it was for), signed from the
    /// group's point of view: positive when it goes the group's ``DebtGroup/direction``, negative
    /// when it goes the other way and is discounted from the total.
    let amount: Double

    /// Identifier for SwiftUI lists (the item's ID).
    var id: String { item.id }
    /// The item's name.
    var name: String { item.name }
}

/// The net balance between the signed-in user and one housemate: what each owes the other is
/// netted, and the group lands on the side of whoever still owes.
struct DebtGroup: Identifiable {
    /// The side of the debt this group is on.
    let direction: DebtDirection

    /// The other housemate: the buyer when ``direction`` is ``DebtDirection/youOwe``, the debtor
    /// when it is ``DebtDirection/owedToYou``.
    let counterparty: UserModel

    /// Both ways: the shares in ``direction`` (positive) and the ones the other way (negative).
    let entries: [DebtEntry]

    /// Identifier for SwiftUI lists, unique per side and housemate.
    var id: String { "\(direction)-\(counterparty.id)" }

    /// The net amount, always positive.
    var total: Double { (entries.reduce(0) { $0 + $1.amount } * 100).rounded() / 100 }
}

/// The result of ``DebtCalculator``: debts grouped by housemate, plus the two totals.
struct DebtLedger {
    /// Housemates the signed-in user owes money to.
    var youOwe: [DebtGroup] = []
    /// Housemates who owe money to the signed-in user.
    var owedToYou: [DebtGroup] = []

    /// The groups on one side of the debt.
    func groups(for direction: DebtDirection) -> [DebtGroup] {
        switch direction {
        case .youOwe: return youOwe
        case .owedToYou: return owedToYou
        }
    }

    /// The total amount on one side of the debt.
    func total(for direction: DebtDirection) -> Double {
        groups(for: direction).reduce(0) { $0 + $1.total }
    }
}

/// Works out who owes whom from the shopping list. Pure, so it can be tested without CloudKit.
///
/// People are matched by `ownerRecordName` (their iCloud account), not by record id: the same
/// person may have more than one `UserModel` record, and items may point at any of them. So each
/// housemate ends up in a single group, on one side only.
enum DebtCalculator {

    /// Works out every open debt between the signed-in user and each housemate.
    ///
    /// - Parameters:
    ///   - items: Every item of the list.
    ///   - users: The house members, one per person, used for names and avatars.
    ///   - userRecords: Every user record of the house, to know whose a reference is.
    ///   - me: The signed-in user's house record. Without it the ledger is empty.
    ///   - settledOverrides: Shares the screen already marked as paid but that are not saved yet
    ///     (see ``settlementKey(item:debtor:)``). They are left out.
    /// - Returns: The debts grouped by housemate, on each side.
    static func ledger(
        items: [ShopListItem],
        users: [UserModel],
        userRecords: [UserModel] = [],
        me: UserModel?,
        settledOverrides: Set<String> = []
    ) -> DebtLedger {
        guard let me else { return DebtLedger() }

        // Record name -> person (ownerRecordName).
        var ownerByRecord: [String: String] = [:]
        for user in userRecords + users + [me] {
            if let name = user.recordID?.recordName { ownerByRecord[name] = personKey(user) }
        }
        func person(_ id: CKRecord.ID) -> String { ownerByRecord[id.recordName] ?? id.recordName }

        let myself = personKey(me)

        /// Per housemate, every open share between them and the user, signed from the user's side:
        /// positive when the housemate owes the user, negative when the user owes the housemate.
        var shares: [String: [DebtEntry]] = [:]

        for item in items.sorted(by: { $0.createdAt < $1.createdAt }) {
            guard
                item.isBought,
                item.hasPrice,
                let price = item.totalValue,
                let buyerID = item.buyerRecordID
            else { continue }

            let consumers = item.consumerRecordIDs
            guard !consumers.isEmpty else { continue }

            let share = (price / Double(consumers.count) * 100).rounded() / 100
            let settled = Set(item.settledUserIDs.map(\.recordName))
            let buyer = person(buyerID)

            for consumerID in consumers {
                let consumer = person(consumerID)
                guard
                    consumer != buyer,
                    !settled.contains(consumerID.recordName),
                    !settledOverrides.contains(settlementKey(item: item, debtor: consumerID))
                else { continue }

                if buyer == myself {
                    shares[consumer, default: []].append(DebtEntry(item: item, debtor: consumerID, amount: share))
                } else if consumer == myself {
                    shares[buyer, default: []].append(DebtEntry(item: item, debtor: consumerID, amount: -share))
                }
            }
        }

        var youOwe: [DebtGroup] = []
        var owedToYou: [DebtGroup] = []
        var seen: Set<String> = []

        for user in users + userRecords {
            let key = personKey(user)
            guard key != myself, seen.insert(key).inserted, let list = shares[key], !list.isEmpty else { continue }

            let net = (list.reduce(0) { $0 + $1.amount } * 100).rounded() / 100
            if net > 0 {
                owedToYou.append(DebtGroup(direction: .owedToYou, counterparty: user, entries: list))
            } else if net < 0 {
                // Flip the signs so the group's own shares read positive.
                let flipped = list.map { DebtEntry(item: $0.item, debtor: $0.debtor, amount: -$0.amount) }
                youOwe.append(DebtGroup(direction: .youOwe, counterparty: user, entries: flipped))
            }
            // Net zero: the two sides cancel out and nobody owes anything.
        }

        return DebtLedger(youOwe: youOwe, owedToYou: owedToYou)
    }

    /// Who a user record belongs to: their iCloud account, or the record itself when unknown.
    private static func personKey(_ user: UserModel) -> String {
        user.ownerRecordName.isEmpty ? (user.recordID?.recordName ?? user.id) : user.ownerRecordName
    }

    /// Identifies "`debtor` paid their share of `item`" for the screen's own bookkeeping.
    static func settlementKey(item: ShopListItem, debtor: CKRecord.ID) -> String {
        "\(item.id)|\(debtor.recordName)"
    }
}
