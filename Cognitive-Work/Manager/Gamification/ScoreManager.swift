//
//  ScoreManager.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 28/09/26.
//

import SwiftUI
import CloudKit

/// Adds and removes points.
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

    /// Creates the shared instance, backed by CloudKit.
    private convenience init() {
        self.init(store: CloudKitAtomicRecordStore())
    }

    /// - Parameter store: Where the user records are read and saved; tests pass an in-memory one.
    init(store: AtomicRecordStore) {
        self.store = store
    }
    
    //MARK: private funcs
    //MARK: Score Calculate
    /// Points a member earns for completing `chore` on `date`.
    ///
    /// A chore without a due date is worth its full ``ChoreModel/score``. A chore done before its
    /// due date is worth half for each day early (done on the day or late: full points), so doing
    /// chores long before they are due doesn't pay off.
    ///
    /// - Parameters:
    ///   - chore: The completed chore.
    ///   - date: When it was completed.
    ///   - calendar: The calendar used to count days.
    /// - Returns: The points to add.
    private func choreScore(
        for chore: ChoreModel,
        completedAt date: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        guard let dueDate = chore.dueDate else { return chore.score }

        let daysUntilDue = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: dueDate)
        ).day ?? 0

        return chore.score >> max(daysUntilDue, 0)
    }
    
    //MARK: Applying a change

    /// Adds `delta` (negative to remove) to the points stored on the server for `user`, then
    /// updates `user` with the result.
    ///
    /// The first time, the score is created from the legacy `points` field of the user's record.
    ///
    /// - Returns: `false` when the user has no record or the score couldn't be saved.
    @discardableResult
    func applyPoints(_ delta: Int, to user: UserModel) async -> Bool {
        guard let userID = user.recordID else { return false }
        guard delta != 0 else { return true }
        let scoreID = UserScoreModel.recordID(for: user, userID: userID)

        for _ in 0..<maxAttempts {
            guard let fetched = try? await store.fetch([scoreID, userID]),
                  let userRecord = fetched[userID]
            else { return false }

            let (record, current) = UserScoreModel.record(
                scoreID,
                in: fetched,
                ownerRecordName: user.ownerRecordName,
                userRecord: userRecord,
                houseID: user.houseReference?.recordID
            )
            let updated = max(current + delta, 0)
            record["points"] = updated

            do {
                try await store.saveAtomically([record])
                user.points = updated
                HardwareViewModel.notifyDataChanged()
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

    /// Adds the points of completing `chore` to `user` (see ``choreScore(for:completedAt:calendar:)``).
    /// - Returns: `false` when the points couldn't be saved.
    @discardableResult
    func assignScore(chore: ChoreModel, for user: UserModel) async -> Bool {
        let earned = choreScore(for: chore)
        guard earned != 0 else { return true }

        return await applyPoints(earned, to: user)
    }
    
    /// Adds the points of completing one occurrence of a chore to `user`.
    /// - Returns: `false` when the chore couldn't be found or the points couldn't be saved.
    @discardableResult
    func assignScore(recurrentAssignmentModel: RecurrentAssignmentModel, for user: UserModel) async -> Bool {
        guard let chore = await recurrentAssignmentModel.chore
        else { return false }
        
        let earned = choreScore(for: chore)
        guard earned != 0 else { return true }

        return await applyPoints(earned, to: user)
    }
        
    //MARK: Assign Score to My User
    
    /// Adds the points of completing `chore` to the signed-in member.
    /// - Returns: `false` when the member couldn't be found or the points couldn't be saved.
    @discardableResult
    func assignScoreForMyUser(chore: ChoreModel) async -> Bool {
        if let myUser = await CloudKitManager.shared.fetchMyHouseUser() {
            let earned = choreScore(for: chore)
            guard earned != 0 else { return true }
            
            return await applyPoints(earned, to: myUser)
        }
        return false
    }
    
    /// Adds `score` points to the signed-in member.
    /// - Returns: `false` when the member couldn't be found or the points couldn't be saved.
    @discardableResult
    func assignScoreForMyUser(score: Int) async -> Bool {
        if let myUser = await CloudKitManager.shared.fetchMyHouseUser() {
            return await applyPoints(score, to: myUser)
        }
        return false
    }
    
    /// Adds the points of completing one occurrence of a chore to the signed-in member.
    /// - Returns: `false` when the member or the chore couldn't be found, or the points couldn't be saved.
    @discardableResult
    func assignScoreForMyUser(assignment: RecurrentAssignmentModel) async -> Bool {
        if let myUser = await CloudKitManager.shared.fetchMyHouseUser() {
            guard let chore = await assignment.chore
            else { return false }
            
            let earned = choreScore(for: chore)
            guard earned != 0 else { return true }
            
            return await applyPoints(earned, to: myUser)
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
    
    //MARK: from Chore
    
    /// Takes back the points of `chore` from `user` (when the chore is unchecked).
    /// - Returns: `false` when the change couldn't be saved.
    @discardableResult
    func removeScore(chore: ChoreModel, for user: UserModel) async -> Bool {
        await applyPoints(-choreScore(for: chore), to: user)
    }
    
    /// Takes back the points of `chore` from the signed-in member (when the chore is unchecked).
    /// - Returns: `false` when the member couldn't be found or the change couldn't be saved.
    @discardableResult
    func removeScoreForMyUser(chore: ChoreModel) async -> Bool {
        if let myUser = await CloudKitManager.shared.fetchMyHouseUser() {
            return await applyPoints(-choreScore(for: chore), to: myUser)
        }
        return false
    }
    
    //MARK: from Assignment
    
    /// Takes back the points of one occurrence from `user` (when it is unchecked).
    /// - Returns: `false` when the chore couldn't be found or the change couldn't be saved.
    @discardableResult
    func removeScore(assignment: RecurrentAssignmentModel, for user: UserModel) async -> Bool {
        guard let chore = await assignment.chore
        else { return false }
        
        return await applyPoints(-choreScore(for: chore), to: user)
    }
    
    /// Takes back the points of one occurrence from the signed-in member (when it is unchecked).
    /// - Returns: `false` when the member or the chore couldn't be found, or the change couldn't be saved.
    @discardableResult
    func removeScoreForMyUser(assignment: RecurrentAssignmentModel) async -> Bool {
        if let myUser = await CloudKitManager.shared.fetchMyHouseUser() {
            guard let chore = await assignment.chore
            else { return false }
            return await applyPoints(-choreScore(for: chore), to: myUser)
        }
        return false
    }
}
