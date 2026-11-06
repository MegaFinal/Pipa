//
//  AppNavigation.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 06/11/26.
//

import Foundation

/// The main tabs.
enum AppTab: Hashable {
    case chores
    case shopping
    case rewards
    case profile
}

/// One request to open a screen inside a tab. Each request is new (``id``), so asking for the
/// same screen twice opens it twice.
struct AppRoute<Destination>: Identifiable, Equatable {
    let id = UUID()
    let destination: Destination

    static func == (lhs: AppRoute, rhs: AppRoute) -> Bool { lhs.id == rhs.id }
}

/// A screen of the shopping tab.
enum ShopRoute {
    /// The list itself.
    case list
    /// "Pendências", the debts between housemates.
    case pendingPayments
}

/// A screen of the profile tab.
enum ProfileRoute {
    /// The general settings, where the Apple Calendar sync is.
    case generalSettings
    /// The Premium screen.
    case premium
}

/// Where the app goes when a notification is tapped (the system banner or the notifications
/// screen): which tab, and what that tab opens. ``ContentView`` owns it and hands it to the tabs
/// through the environment; each tab watches its own request and clears it once handled.
@MainActor
@Observable
final class AppNavigation {

    /// The tab on screen.
    var selectedTab: AppTab = .chores

    /// What the chores tab opens: a chore, the unassigned chores, the new member pop-up or the
    /// progress screen.
    var choresRoute: AppRoute<NotificationDestination>?
    /// What the shopping tab opens.
    var shopRoute: AppRoute<ShopRoute>?
    /// What the profile tab opens.
    var profileRoute: AppRoute<ProfileRoute>?

    /// Goes to the tab of `destination` and asks it to open the matching screen. The
    /// retrospective isn't in a tab: ``ContentView`` shows it over everything.
    func open(_ destination: NotificationDestination) {
        switch destination {
        case .chore, .pickChores, .newMember, .dashboard:
            selectedTab = .chores
            choresRoute = AppRoute(destination: destination)
        case .shopList:
            selectedTab = .shopping
            shopRoute = AppRoute(destination: .list)
        case .pendingPayments:
            selectedTab = .shopping
            shopRoute = AppRoute(destination: .pendingPayments)
        case .calendarSync:
            selectedTab = .profile
            profileRoute = AppRoute(destination: .generalSettings)
        case .premium:
            selectedTab = .profile
            profileRoute = AppRoute(destination: .premium)
        case .retrospective:
            break
        }
    }
}
