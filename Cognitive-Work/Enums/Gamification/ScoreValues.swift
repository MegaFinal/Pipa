//
//  ScoreValues.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 28/09/26.
//

import Foundation

/// The points table: what each action is worth. Every number of the balance lives here.
///
/// Points measure the work a member did for the house in the current cycle, and the rank follows
/// them (``Tier/thresholds``). The rules:
/// 1. **Doing is what counts.** Completing a chore is worth its effort, about a point per minute
///    (``choreCompletion(minutes:priority:)``). Chores done ahead of time are worth less (see
///    ``ScoreManager/points(forCompleting:dueOn:completedAt:calendar:)``).
/// 2. **Planning is a small bonus.** Creating a chore or putting an item on the list helps the
///    house, so it's worth a little, always less than the shortest chore, and limited
///    (``dailyChoreCreationBonusLimit``; a list item only pays once it is bought).
/// 3. **Undoing takes back exactly what was given.** The points of a completion, a purchase or a
///    chore's creation are saved with it, so unchecking, un-buying or deleting can't be repeated to
///    collect the difference.
/// 4. **Nothing pays for being passive.** No points for opening the app, changing a setting
///    (linking the calendar) or claiming a chore before doing it; the chore pays when it's done.
enum ScoreValues {

    /// Creating a chore with room, priority, duration, frequency and description filled in (bonus).
    case choreCreatedWithFullDetails

    /// Creating a chore.
    case choreAdded

    /// Putting an item on the shopping list, paid to whoever added it once the item is bought.
    case shoppingItemAdded

    /// Buying (checking off) a shopping list item.
    case shoppingItemBought

    /// Recording the price paid, so the house can split it.
    case receiptScanned(itemCount: Int)

    /// How many points the action is worth.
    var points: Int {
        switch self {
        case .choreCreatedWithFullDetails:
            return 1
        case .choreAdded:
            return 2
        case .shoppingItemAdded:
            return 1
        case .shoppingItemBought:
            return 3
        case .receiptScanned(let itemCount):
            return max(itemCount, 0)
        }
    }

    // MARK: - Chores

    /// Points every completed chore is worth on top of its minutes: remembering and starting it.
    static let choreCompletionBase = 2

    /// Longest duration that counts, in minutes. The form offers up to 120.
    static let maximumChoreMinutes: Double = 120

    /// How much more a minute of chore is worth by priority: urgent work relieves the house more.
    static func priorityMultiplier(_ priority: PriorityTag) -> Double {
        switch priority {
        case .undefined, .low: return 1.0
        case .medium: return 1.15
        case .high: return 1.3
        case .urgent: return 1.5
        }
    }

    /// Points for completing a chore on time: ``choreCompletionBase`` plus its minutes (up to
    /// ``maximumChoreMinutes``) times ``priorityMultiplier(_:)``.
    ///
    /// Effort is what sets the value. The old score added a fixed amount per priority (up to 21)
    /// and per frequency (up to 13) to a duration score of 3 to 24, so a 5-minute urgent chore was
    /// worth about the same as an hour-long one, and a 5-minute daily chore paid three times more
    /// per minute than a monthly one.
    ///
    /// - Parameters:
    ///   - minutes: The chore's duration.
    ///   - priority: The chore's priority.
    static func choreCompletion(minutes: Double, priority: PriorityTag) -> Int {
        let minutes = min(max(minutes, 0), maximumChoreMinutes)
        return choreCompletionBase + Int((minutes * priorityMultiplier(priority)).rounded())
    }

    /// How many chores a member can be paid for creating per day. Further ones are created
    /// normally but give no points, so creating chores can't replace doing them.
    static let dailyChoreCreationBonusLimit = 3

    /// Points for creating a chore.
    /// - Parameter hasFullDetails: Whether room, priority, duration, frequency and description
    ///   are all filled in (``choreCreatedWithFullDetails``).
    static func choreCreation(hasFullDetails: Bool) -> Int {
        choreAdded.points + (hasFullDetails ? choreCreatedWithFullDetails.points : 0)
    }

    // MARK: - Coins

    /// Points each coin takes. Coins follow the points as they are earned (see ``ScoreManager``):
    /// every ``pointsPerCoin`` points of the cycle is one more coin, and taking points back takes
    /// the coins back.
    ///
    /// With a point being about a minute of chores, the top of the ladder (``Tier/topThreshold``)
    /// is about 65 coins a cycle, and a coin is worth about 10 minutes of work, in line with
    /// ``CouponPricing`` (sparing a minute costs more than doing it).
    static let pointsPerCoin = 10

    /// Coins earned with `points` in a cycle.
    static func coins(forPoints points: Int) -> Int {
        max(points, 0) / pointsPerCoin
    }

    // MARK: - Shopping

    /// Points the buyer gets for buying an item.
    /// - Parameter hasPrice: Whether the price paid is recorded (``receiptScanned(itemCount:)``).
    static func shoppingPurchase(hasPrice: Bool) -> Int {
        shoppingItemBought.points + (hasPrice ? receiptScanned(itemCount: 1).points : 0)
    }
}
