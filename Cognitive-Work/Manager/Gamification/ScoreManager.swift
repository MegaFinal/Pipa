//
//  ScoreManager.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 28/09/26.
//

import SwiftUI
import CloudKit

/// Adds and removes points, and pays the coins they are worth.
///
/// Coins follow the points as they change, not only when the rank changes: every point added
/// credits the member's ``CoinWalletModel`` with what it's worth (``ScoreValues/coins(forPoints:)``)
/// right away, and taking points back takes those coins back (never below zero; see
/// ``UserScoreModel/cycleCoins``). The score and the wallet are saved together, so the coins
/// always match the points.
///
/// Points live in ``UserScoreModel``, never in ``UserModel``. Every change is applied to the
/// **server's** value: the score is fetched, the points are added to what it holds and it is saved
/// only if nobody changed it in between (``AtomicRecordStore``); otherwise it is fetched again. So
/// a device whose copy is out of date (it missed another device's points, or the reset at the end
/// of a cycle) can't overwrite them, and two devices scoring at once both count.
///
/// Points never go below 0.
@Observable
class ScoreManager {
    
    /// The single instance used by the app.
    static let shared = ScoreManager()

    /// Where scores are read and saved (CloudKit in the app, in memory in tests).
    @ObservationIgnored private let store: AtomicRecordStore
    /// How many times a save is retried when another device changed the score at the same time.
    @ObservationIgnored private let maxAttempts = 5
    /// Settles the member's closed cycles before their points change
    /// (``CycleSettlementService/settleClosedCycles(of:today:)``). `nil` in tests.
    @ObservationIgnored private let settleClosedCycles: ((UserModel) async -> Void)?

    /// Creates the shared instance, backed by CloudKit.
    private convenience init() {
        self.init(store: CloudKitAtomicRecordStore()) { user in
            await CycleSettlementService.settleClosedCycles(of: user)
        }
    }

    /// - Parameters:
    ///   - store: Where the user records are read and saved; tests pass an in-memory one.
    ///   - settleClosedCycles: Run before every change, so points of a new cycle never land on a
    ///     cycle still waiting to be settled (and get reset with it).
    init(store: AtomicRecordStore, settleClosedCycles: ((UserModel) async -> Void)? = nil) {
        self.store = store
        self.settleClosedCycles = settleClosedCycles
    }
    
    //MARK: Score Calculate
    /// Points a member earns for completing `chore` on `date`.
    ///
    /// On time (or late, or without a due date), a chore is worth its effort
    /// (``ScoreValues/choreCompletion(minutes:priority:)``). Done before the due date it is worth
    /// half for each day early, so checking off chores long before they are due, or the next
    /// occurrences of a recurring one, doesn't pay off. A recurring chore can be done a little early at no cost, within its
    /// period (``earlyGraceDays(for:)``): a weekly chore any day of its week, a daily one only on
    /// its day.
    ///
    /// The result is saved with the completion (``ChoreModel/awardedPoints``,
    /// ``RecurrentAssignmentModel/awardedPoints``), so unchecking takes back exactly what was given.
    ///
    /// - Parameters:
    ///   - chore: The completed chore.
    ///   - dueDate: When it was due: the chore's ``ChoreModel/dueDate`` for a one-off chore, the
    ///     occurrence's ``RecurrentAssignmentModel/day`` for a recurring one.
    ///   - date: When it was completed.
    ///   - calendar: The calendar used to count days.
    /// - Returns: The points to add.
    func points(
        forCompleting chore: ChoreModel,
        dueOn dueDate: Date?,
        completedAt date: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        let full = ScoreValues.choreCompletion(minutes: chore.duration, priority: chore.priorityTag)
        guard let dueDate else { return full }

        let daysUntilDue = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: dueDate)
        ).day ?? 0
        let daysEarly = daysUntilDue - earlyGraceDays(for: chore.frequency)

        return full >> max(daysEarly, 0)
    }
    
    /// Days before the due date a chore can be done without losing points: one period of the
    /// chore minus a day (a weekly chore, up to 6 days early). One-off and daily chores have none.
    private func earlyGraceDays(for frequency: Recurrence) -> Int {
        switch frequency {
        case .weekly: return 6
        case .fortnightly: return 13
        case .monthly: return 29
        case .daily, .none, .undefined: return 0
        }
    }
    
    //MARK: Applying a change

    /// Adds `delta` (negative to remove) to the points stored on the server for `user`, then
    /// updates `user` with the result. The coins the change is worth are credited (or taken back)
    /// in the same save.
    ///
    /// The first time, the score is created from the legacy `points` field of the user's record.
    ///
    /// - Returns: `false` when the user has no record or the score couldn't be saved.
    @discardableResult
    func applyPoints(_ delta: Int, to user: UserModel) async -> Bool {
        guard let userID = user.recordID else { return false }
        guard delta != 0 else { return true }
        await settleClosedCycles?(user)
        let scoreID = UserScoreModel.recordID(for: user, userID: userID)
        let walletID = CoinWalletModel.recordID(for: userID)
        let houseID = user.houseReference?.recordID

        for _ in 0..<maxAttempts {
            guard let fetched = try? await store.fetch([scoreID, userID, walletID]),
                  let userRecord = fetched[userID]
            else { return false }

            let (record, current) = UserScoreModel.record(
                scoreID,
                in: fetched,
                ownerRecordName: user.ownerRecordName,
                userRecord: userRecord,
                houseID: houseID
            )
            let updated = max(current + delta, 0)
            record["points"] = updated

            var records = [record]
            var coinsChanged = false
            // A wallet needs its house as parent; without one, only the points change.
            if let houseID {
                let credited = record["cycleCoins"] as? Int ?? 0
                let owed = ScoreValues.coins(forPoints: updated) - credited
                if owed != 0 {
                    let wallet = CoinWalletModel.record(
                        for: userID,
                        in: fetched,
                        houseID: houseID,
                        legacyCoins: userRecord["coins"] as? Int ?? 0
                    )
                    // Taking back stops at an empty wallet; the rest stays in `cycleCoins`.
                    let change = owed > 0 ? owed : -min(-owed, wallet.balance)
                    wallet.record["balance"] = wallet.balance + change
                    record["cycleCoins"] = credited + change
                    records.append(wallet.record)
                    coinsChanged = change != 0
                }
            }

            do {
                try await store.saveAtomically(records)
                user.points = updated
                HardwareViewModel.notifyDataChanged()
                if coinsChanged {
                    Task { @MainActor in
                        NotificationCenter.default.post(name: .coinsDidChange, object: nil)
                    }
                }
                return true
            } catch AtomicRecordStoreError.conflict {
                // Someone changed this score meanwhile (or created it): start again from the new value.
                continue
            } catch {
                return false
            }
        }
        return false
    }

    //MARK: Assign Score to any User
    
    /// Adds `score` points to `user`.
    /// - Returns: `false` when the points couldn't be saved.
    @discardableResult
    func assignScore(score: Int, for user: UserModel) async -> Bool {
        await applyPoints(score, to: user)
    }
        
    //MARK: Assign Score to My User
    
    /// Adds `score` points to the signed-in member.
    /// - Returns: `false` when the member couldn't be found or the points couldn't be saved.
    @discardableResult
    func assignScoreForMyUser(score: Int) async -> Bool {
        if let myUser = await CloudKitManager.shared.fetchMyHouseUser() {
            return await applyPoints(score, to: myUser)
        }
        return false
    }
    
    //MARK: Remove Score Funcions
    
    /// Removes `score` points from `user` (never below zero).
    /// - Returns: `false` when the change couldn't be saved.
    @discardableResult
    func removeScore(score: Int, for user: UserModel) async -> Bool {
        await applyPoints(-score, to: user)
    }
    
    /// Removes `score` points from the signed-in member (never below zero).
    /// - Returns: `false` when the member couldn't be found or the change couldn't be saved.
    @discardableResult
    func removeScoreForMyUser(score: Int) async -> Bool {
        if let myUser = await CloudKitManager.shared.fetchMyHouseUser() {
            return await applyPoints(-score, to: myUser)
        }
        return false
    }
}
