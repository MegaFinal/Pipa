//
//  CycleSettlementService.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 16/10/26.
//

import Foundation
import CloudKit

/// Pays each user coins for every closed cycle, according to their rank, and starts the rank over.
///
/// Two steps, both idempotent:
/// - ``prepareClosedCycles(_:members:houseID:today:)`` runs automatically (when the rewards tab
///   or the notifications screen opens). For every closed cycle and every member it creates a
///   pending ``CoinPayoutModel`` and the matching ``RankHistoryModel`` and resets the member's
///   points to 0, in one atomic save. The records have deterministic names, so when two devices
///   do it at once the second save fails and is ignored.
/// - ``confirmPendingPayouts(for:cycles:houseID:legacyCoins:)`` runs from the retrospective's
///   button. It marks the user's pending payouts as confirmed and credits their wallet in one
///   atomic save; a confirmed payout is never credited again.
@MainActor
final class CycleSettlementService {

    /// Where records are read and saved (CloudKit in the app, in memory in tests).
    private let store: AtomicRecordStore
    /// How many times a save is retried when another device changed the records at the same time.
    private let maxAttempts: Int

    /// - Parameters:
    ///   - store: Defaults to ``CloudKitAtomicRecordStore``.
    ///
    /// The default is resolved in the body: default argument expressions are evaluated outside
    /// the main actor, where that main-actor value can't be created.
    init(
        store: AtomicRecordStore? = nil,
        maxAttempts: Int = 5
    ) {
        self.store = store ?? CloudKitAtomicRecordStore()
        self.maxAttempts = maxAttempts
    }

    // MARK: - Preparing

    /// Creates the missing payouts and history entries of every closed cycle, and starts each
    /// member's rank over.
    ///
    /// For each member and closed cycle (oldest first), one atomic save writes:
    /// - the pending ``CoinPayoutModel``, paid by the member's rank;
    /// - the ``RankHistoryModel`` with that rank and the member's points;
    /// - the member's ``UserScoreModel`` with `points` back to 0 (so the rank back to Bronze 1).
    ///
    /// The three go together, so a cycle is never recorded without the reset, nor reset twice:
    /// once a cycle's entries exist, it is skipped. The rank and points are read from the
    /// server's copy of the score, at the moment this runs (the first time any device of the house
    /// notices the cycle ended); points of past days aren't recorded anywhere.
    ///
    /// - Returns: How many payouts this call created.
    @discardableResult
    func prepareClosedCycles(
        _ cycles: [HouseCycleModel],
        members: [UserModel],
        houseID: CKRecord.ID,
        today: Date = .now
    ) async -> Int {
        let closed = recentClosedCycles(cycles, today: today)
        let memberIDs = members.compactMap { member in member.recordID.map { ($0, member) } }
        guard !closed.isEmpty, !memberIDs.isEmpty else { return 0 }

        // One read tells which cycles are still unsettled; usually none, and nothing else runs.
        var allIDs: [CKRecord.ID] = []
        for cycle in closed {
            for (userID, _) in memberIDs {
                allIDs.append(CoinPayoutModel.recordID(cycleKey: cycle.key, userID: userID))
                allIDs.append(RankHistoryModel.recordID(cycleKey: cycle.key, userID: userID))
            }
        }
        guard let existing = try? await store.fetch(allIDs) else { return 0 }

        let houseReference = CKRecord.Reference(recordID: houseID, action: .none)

        var created = 0
        for (userID, member) in memberIDs {
            // Oldest first: each cycle starts from the reset of the previous one.
            for cycle in closed {
                let payoutID = CoinPayoutModel.recordID(cycleKey: cycle.key, userID: userID)
                let historyID = RankHistoryModel.recordID(cycleKey: cycle.key, userID: userID)
                guard existing[payoutID] == nil || existing[historyID] == nil else { continue }

                if await settle(cycle, userID: userID, member: member, houseReference: houseReference) {
                    created += 1
                }
            }
        }
        return created
    }

    /// Settles one member for one cycle. See ``prepareClosedCycles(_:members:houseID:today:)``.
    ///
    /// - Returns: Whether this call created the payout.
    private func settle(
        _ cycle: HouseCycleModel,
        userID: CKRecord.ID,
        member: UserModel,
        houseReference: CKRecord.Reference
    ) async -> Bool {
        let payoutID = CoinPayoutModel.recordID(cycleKey: cycle.key, userID: userID)
        let historyID = RankHistoryModel.recordID(cycleKey: cycle.key, userID: userID)
        let scoreID = UserScoreModel.recordID(for: member, userID: userID)
        let userReference = CKRecord.Reference(recordID: userID, action: .none)

        for _ in 0..<maxAttempts {
            guard let fetched = try? await store.fetch([payoutID, historyID, scoreID, userID]),
                  let userRecord = fetched[userID]
            else { return false }

            let hasPayout = fetched[payoutID] != nil
            let hasHistory = fetched[historyID] != nil
            // Another device settled it in the meantime.
            if hasPayout && hasHistory { return false }

            // The first time, the score is created from the user's legacy points.
            let (scoreRecord, points) = UserScoreModel.record(
                scoreID,
                in: fetched,
                ownerRecordName: member.ownerRecordName,
                userRecord: userRecord,
                houseID: houseReference.recordID
            )
            let tier = Tier(points: points)
            var records: [CKRecord] = []

            if !hasPayout {
                let record = CKRecord(recordType: CoinPayoutModel.recordType, recordID: payoutID)
                CoinPayoutModel(
                    user: userReference,
                    cycleKey: cycle.key,
                    tier: tier,
                    points: points,
                    amount: tier.cycleCoins
                ).populate(record: record)
                record.parent = houseReference
                records.append(record)
            }

            if !hasHistory {
                let record = CKRecord(recordType: RankHistoryModel.recordType, recordID: historyID)
                RankHistoryModel(
                    user: userReference,
                    cycleKey: cycle.key,
                    cycleStart: cycle.startDate,
                    cycleEnd: cycle.endDate,
                    tier: tier,
                    points: points
                ).populate(record: record)
                record.parent = houseReference
                records.append(record)
            }

            // The rank starts over. Only when the cycle had no entry at all: an entry that already
            // exists means the reset was already done (or the cycle predates the reset).
            let resets = !hasPayout && !hasHistory
            if resets {
                scoreRecord["points"] = 0 as Int
                records.append(scoreRecord)
            }

            do {
                try await store.saveAtomically(records)
                // Keeps this device's copy in line, so a later save of it doesn't bring the old
                // points back.
                if resets { member.points = 0 }
                return !hasPayout
            } catch AtomicRecordStoreError.conflict {
                // Another device wrote these first, or the score just changed: read again.
                continue
            } catch {
                // Retried the next time this runs.
                return false
            }
        }
        return false
    }

    /// How many of the most recent closed cycles are looked at. Older ones were settled long
    /// ago; this keeps every check to a single small read.
    static let settlementWindow = 6

    /// The last ``settlementWindow`` cycles that already ended, oldest first.
    private func recentClosedCycles(_ cycles: [HouseCycleModel], today: Date) -> [HouseCycleModel] {
        Array(HouseCycleModel.closed(cycles, asOf: today).suffix(Self.settlementWindow))
    }

    // MARK: - Reading

    /// `userID`'s payouts for the closed cycles, pending and confirmed.
    func payouts(
        for userID: CKRecord.ID,
        cycles: [HouseCycleModel],
        today: Date = .now
    ) async -> [CoinPayoutModel] {
        let ids = recentClosedCycles(cycles, today: today)
            .map { CoinPayoutModel.recordID(cycleKey: $0.key, userID: userID) }
        guard !ids.isEmpty, let fetched = try? await store.fetch(ids) else { return [] }
        return fetched.values.compactMap(CoinPayoutModel.init(record:))
            .sorted { $0.cycleKey < $1.cycleKey }
    }

    // MARK: - Confirming

    /// The result of ``confirmPendingPayouts(for:cycles:houseID:legacyCoins:today:)``.
    struct Confirmation: Equatable {
        /// Coins credited by this call; 0 when everything was already confirmed.
        let credited: Int
        /// The member's balance after the credit.
        let newBalance: Int
    }

    /// Why confirming payouts failed.
    enum SettlementError: Error, Equatable {
        /// The records kept changing between fetch and save.
        case tooManyConflicts
    }

    /// Confirms every pending payout of `userID` and credits the total to their wallet.
    ///
    /// Safe to call any number of times, from any number of devices: only payouts still pending
    /// on the server are credited, and the status change and the credit are saved together.
    func confirmPendingPayouts(
        for userID: CKRecord.ID,
        cycles: [HouseCycleModel],
        houseID: CKRecord.ID,
        legacyCoins: Int,
        today: Date = .now
    ) async throws -> Confirmation {
        let payoutIDs = recentClosedCycles(cycles, today: today)
            .map { CoinPayoutModel.recordID(cycleKey: $0.key, userID: userID) }
        let walletID = CoinWalletModel.recordID(for: userID)

        for _ in 0..<maxAttempts {
            let fetched = try await store.fetch(payoutIDs + [walletID])
            let wallet = CoinWalletModel.record(for: userID, in: fetched, houseID: houseID, legacyCoins: legacyCoins)

            var records: [CKRecord] = []
            var total = 0
            for id in payoutIDs {
                guard let record = fetched[id],
                      var payout = CoinPayoutModel(record: record),
                      payout.status == .pending
                else { continue }
                payout.status = .confirmed
                payout.confirmedAt = today
                payout.populate(record: record)
                records.append(record)
                total += payout.amount
            }

            guard !records.isEmpty else {
                return Confirmation(credited: 0, newBalance: wallet.balance)
            }

            let newBalance = wallet.balance + total
            wallet.record["balance"] = newBalance
            records.append(wallet.record)

            do {
                try await store.saveAtomically(records)
                return Confirmation(credited: total, newBalance: newBalance)
            } catch AtomicRecordStoreError.conflict {
                continue
            }
        }

        throw SettlementError.tooManyConflicts
    }
}
