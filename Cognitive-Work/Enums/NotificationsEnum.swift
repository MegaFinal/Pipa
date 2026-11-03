//
//  NotificationsEnum.swift
//  Cognitive-Work
//
//  Created by Isabela Hissa Pinto on 30/09/26.
//

import SwiftUI

/// The kinds of in-app notifications shown on the notifications screen.
///
/// The raw value is the notification's title (or part of it: titles that start or end with a
/// space are completed with a name or a number, such as "3 tarefas a pegar hoje").
enum Notifications: String {
    /// There are unassigned chores the user can pick up today.
    case grabChore = " tarefas a pegar hoje"
    /// The retrospective of the cycle that ended is ready.
    case retrospective = "Sua retrospectiva chegou"
    /// A new member joined the house (the member's name goes before the title).
    case newUser = " entrou na casa"
    /// A new division of chores was generated.
    case newDivision = "Nova divisão pronta"
    /// One of the user's chores is late (the chore's name goes before the title).
    case yourDelayedChore = " está atrasado"
    /// A chore nobody picked up is late (the chore's name goes after the title).
    case noUserDelayedChore = "Ninguém pegou "
    
    /// The second line of the notification, explaining what to do. Empty when the title is enough.
    var subTitle: String {
        switch self {
        case .grabChore: return "Escolha as que couberem no seu tempo"
        case .retrospective: return "Veja como foram os seus últimos 15 dias da casa"
        case .newUser: return "Agora a casa tem mais um morador"
        case .newDivision: return "Suas tarefas dos próximos 15 dias já estão na escala"
        case .yourDelayedChore: return ""
        case .noUserDelayedChore: return ""
        }
    }
    
    /// Background color of the notification's icon.
    var color: Color {
        switch self {
        case .grabChore: return .lowOpacityBlue
        case .retrospective: return .lowOpacityYellow
        case .newUser: return .lowOpacityPurple
        case .newDivision: return .lowOpacityGreen
        case .yourDelayedChore: return .lowOpacityOrange
        case .noUserDelayedChore: return .lowOpacityOrange
        }
    }
    
    /// SF Symbol name of the notification's icon.
    var symbol: String {
        switch self {
        case .grabChore: return "hand.rays"
        case .retrospective: return "chart.bar.xaxis"
        case .newUser: return "person"
        case .newDivision: return "chart.bar.horizontal.page"
        case .yourDelayedChore: return "exclamationmark.triangle"
        case .noUserDelayedChore: return "exclamationmark.triangle"
        }
    }
}
