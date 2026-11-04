//
//  ScoreAction.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 28/09/26.
//

/// In-app actions considered cognitive work, and how many points each one is worth.
enum ScoreValues {

    /// Creating a chore with room, priority, duration, frequency and description filled in (bonus).
    case choreCreatedWithFullDetails
    
    /// Adding a chore.
    case choreAdded
    
    /// Adding an item to the shopping list.
    case shoppingItemAdded
    
    /// Setting the beneficiary when creating a shopping list item (bonus).
    case shoppingItemBeneficiaryAssigned

    /// Buying (checking off) a shopping list item.
    case shoppingItemBought

    /// Opening the app on a given day (streak).
    case dailyAppOpen

    /// Linking with Apple Calendar.
    case appleCalendarLinked

    /// Assigning someone responsible for a chore.
    case responsibleAssigned(isSelf: Bool)

    /// Picking up an unassigned chore.
    case unassignedChorePicked
    
    /// Writing a chore's description/checklist.
    case descriptionWritten

    /// Scanning a receipt / assigning prices.
    case receiptScanned(itemCount: Int)

    /// How many points the action is worth.
    var points: Int {
        switch self {
        case .choreCreatedWithFullDetails:
            return 5
        case .choreAdded:
            return 7
        case .shoppingItemAdded:
            return 3
        case .shoppingItemBeneficiaryAssigned:
            return 3
        case .shoppingItemBought:
            return 4
        case .dailyAppOpen:
            return 2
        case .appleCalendarLinked:
            return 10
        case .responsibleAssigned(let isSelf):
            return isSelf ? 5 : 3
        case .unassignedChorePicked:
            return 7
        case .descriptionWritten:
            return 3
        case .receiptScanned(let itemCount):
            return max(itemCount, 0)
        }
    }
}
