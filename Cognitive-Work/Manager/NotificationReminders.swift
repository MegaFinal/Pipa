//
//  NotificationReminders.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 27/10/26.
//

import CloudKit
import Foundation
import UserNotifications

/// The notifications that depend on time, not on something a housemate did: the retrospective,
/// chores to pick up, weekly payment reminders and the calendar suggestion.
///
/// They are planned from the house's data on this device and scheduled locally, so they need no
/// push. ``refreshReminders(force:)`` replaces the whole plan each time it runs.
extension NotificationManager {

    /// Identifier prefix of every reminder replaced by ``refreshReminders(force:)``.
    private static let reminderPrefix = "reminder-"
    /// Identifier of the calendar suggestion. It has no `reminder-` prefix because it is scheduled
    /// once, not rebuilt.
    private static let calendarSuggestionID = "suggestion-calendar"
    /// `UserDefaults` key of the last time the reminders were rebuilt.
    private static let lastRefreshKey = "notifications.lastReminderRefresh"
    /// `UserDefaults` key set once the calendar suggestion was scheduled.
    private static let calendarSuggestedKey = "notifications.calendarSuggested"
    /// The shortest time between two refreshes that aren't forced.
    private static let refreshInterval: TimeInterval = 10 * 60
    /// How many weekly reminders are scheduled ahead for each debt.
    private static let debtRemindersAhead = 4

    /// One notification planned for a future date.
    private struct Reminder {
        let id: String
        let kind: Notifications
        let title: String
        let body: String
        let date: Date
    }

    // MARK: - Refreshing

    /// Rebuilds the scheduled reminders from the house's data.
    ///
    /// Does nothing (and removes the reminders) while the settings switch is off. Calls closer
    /// than ten minutes apart are skipped, unless `force` is `true`.
    /// - Parameter force: Pass `true` right after the data changed (for example a new division),
    ///   to bypass the pause and the cache.
    func refreshReminders(force: Bool = false) async {
        guard isEnabledByUser, await canSchedule() else {
            await removeReminders()
            return
        }
        
        let defaults = UserDefaults.standard
        let now = Date()
        if !force, let last = defaults.object(forKey: Self.lastRefreshKey) as? Date,
           now.timeIntervalSince(last) < Self.refreshInterval {
            return
        }
        defaults.set(now, forKey: Self.lastRefreshKey)
        
        let snapshot = await HouseDataStore.shared.load(force: force)
        guard snapshot.houseUser != nil else { return }
        
        let items = await CloudKitManager.shared.fetchAll(ShopListItem.self)
        let ledger = DebtCalculator.ledger(
            items: items,
            users: snapshot.users,
            userRecords: snapshot.userRecords,
            me: snapshot.houseUser
        )
        
        var reminders: [Reminder] = []
        reminders += retrospectiveReminders(snapshot, now: now)
        reminders += grabChoreReminders(snapshot, now: now)
        reminders += debtReminders(ledger, now: now)
        
        await removeReminders()
        for reminder in reminders {
            await add(reminder)
        }
        await updateCalendarSuggestion(snapshot, now: now)
    }

    /// Removes every reminder that ``refreshReminders(force:)`` scheduled.
    private func removeReminders() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(Self.reminderPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removePendingNotificationRequests(withIdentifiers: [Self.calendarSuggestionID])
    }

    /// Whether the system lets the app show notifications.
    private func canSchedule() async -> Bool {
        switch await authorizationStatus() {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    // MARK: - Planning

    /// "Sua retrospectiva chegou", on the day after the last division's last day (the day the
    /// retrospective is offered, see ``RetroTriggerPolicy``).
    private func retrospectiveReminders(_ snapshot: HouseSnapshot, now: Date) -> [Reminder] {
        let calendar = Calendar.current
        guard let lastDay = snapshot.assignments.map({ calendar.startOfDay(for: $0.day) }).max(),
              let nextDay = calendar.date(byAdding: .day, value: 1, to: lastDay),
              let fire = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: nextDay),
              fire > now
        else { return [] }
        
        return [Reminder(
            id: Self.reminderPrefix + "retro",
            kind: .retrospective,
            title: L10n.tr(key: Notifications.retrospective.rawValue),
            body: L10n.tr(key: Notifications.retrospective.subTitle),
            date: fire
        )]
    }

    /// "N tarefas a pegar hoje", at 9h of each of the next seven days that still has chores
    /// nobody took (same rule as the notifications screen).
    private func grabChoreReminders(_ snapshot: HouseSnapshot, now: Date) -> [Reminder] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 7, to: today) else { return [] }
        
        let choreIDs = Set(snapshot.chores.compactMap(\.recordID))
        var countByDay: [Date: Int] = [:]
        
        // Recurring chores: occurrences nobody took.
        for assignment in snapshot.assignments {
            let day = calendar.startOfDay(for: assignment.day)
            guard day >= today, day < end, !assignment.isCompleted,
                  (assignment.userReferences ?? []).isEmpty,
                  let choreID = assignment.choreReference?.recordID, choreIDs.contains(choreID)
            else { continue }
            countByDay[day, default: 0] += 1
        }
        
        // One-off chores with a date and nobody responsible.
        for chore in snapshot.chores where (chore.dailyAssignmentsReference ?? []).isEmpty {
            guard let dueDate = chore.dueDate, !chore.isDone else { continue }
            let day = calendar.startOfDay(for: dueDate)
            let hasOwner = chore.currentResponsibleReference != nil
                || !(chore.allResponsibleUsersReference ?? []).isEmpty
            guard day >= today, day < end, !hasOwner else { continue }
            countByDay[day, default: 0] += 1
        }
        
        return countByDay.compactMap { day, count -> Reminder? in
            guard let fire = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day),
                  fire > now else { return nil }
            return Reminder(
                id: Self.reminderPrefix + "grab-\(Int(day.timeIntervalSince1970))",
                kind: .grabChore,
                title: L10n.tr("\(count) tarefas a pegar hoje"),
                body: L10n.tr(key: Notifications.grabChore.subTitle),
                date: fire
            )
        }
    }

    /// Weekly reminders, while a debt stays unpaid, counted from the oldest unpaid purchase.
    /// Scheduled a few weeks ahead; each refresh drops the ones for debts that were paid.
    private func debtReminders(_ ledger: DebtLedger, now: Date) -> [Reminder] {
        DebtReminders.summaries(from: ledger).flatMap { summary in
            DebtReminders.fireDates(since: summary.since, after: now, count: Self.debtRemindersAhead)
                .enumerated()
                .map { index, date in
                    Reminder(
                        id: Self.reminderPrefix + "debt-\(summary.key)-\(index)",
                        kind: summary.kind,
                        title: summary.title,
                        body: summary.body,
                        date: date
                    )
                }
        }
    }

    /// Once, a couple of hours after a new member's first visit: suggests the calendar sync.
    /// Cancelled if the user turns the sync on before it shows.
    private func updateCalendarSuggestion(_ snapshot: HouseSnapshot, now: Date) async {
        let defaults = UserDefaults.standard
        
        if defaults.bool(forKey: "isCalendarSyncEnabled") {
            center.removePendingNotificationRequests(withIdentifiers: [Self.calendarSuggestionID])
            return
        }
        
        guard !defaults.bool(forKey: Self.calendarSuggestedKey),
              let joined = snapshot.houseUser?.joinedAt,
              now.timeIntervalSince(joined) < 7 * 24 * 3600
        else { return }
        
        let reminder = Reminder(
            id: Self.calendarSuggestionID,
            kind: .calendarSync,
            title: L10n.tr(key: Notifications.calendarSync.rawValue),
            body: L10n.tr(key: Notifications.calendarSync.subTitle),
            date: DebtReminders.daytime(now.addingTimeInterval(2 * 3600))
        )
        if await add(reminder) {
            defaults.set(true, forKey: Self.calendarSuggestedKey)
        }
    }

    // MARK: - Scheduling

    /// Adds one reminder to the notification center, replacing the one with the same ID.
    @discardableResult
    private func add(_ reminder: Reminder) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.threadIdentifier = "reminders"
        content.userInfo = [UserInfoKey.kind: reminder.kind.rawValue]
        
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: reminder.date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
        
        do {
            try await center.add(request)
            return true
        } catch {
            print("Failed to schedule reminder \(reminder.id): \(error)")
            return false
        }
    }
}

// MARK: - Debts

/// What the debt notifications say and when, shared by the weekly reminders and the
/// notifications screen.
struct DebtSummary {
    /// "youOwe" or "owedToYou", to build identifiers.
    let key: String
    let kind: Notifications
    let title: String
    let body: String
    /// When the oldest unpaid purchase was made: the weekly reminders count from this day.
    let since: Date
}

enum DebtReminders {

    /// Hour of the day the weekly reminders show up.
    private static let hour = 10

    /// One summary for each side of the debts that has something to pay or receive.
    static func summaries(from ledger: DebtLedger) -> [DebtSummary] {
        DebtDirection.allCases.compactMap { direction -> DebtSummary? in
            let groups = ledger.groups(for: direction)
            let total = ledger.total(for: direction)
            guard !groups.isEmpty, total > 0,
                  let since = groups.flatMap(\.entries).map({ $0.item.boughtAt ?? $0.item.createdAt }).min()
            else { return nil }
            
            let money = total.formatted(.currency(code: "BRL").locale(L10n.locale))
            switch direction {
            case .youOwe:
                return DebtSummary(
                    key: "youOwe",
                    kind: .debtYouOwe,
                    title: L10n.tr(key: Notifications.debtYouOwe.rawValue),
                    body: groups.count == 1
                        ? L10n.tr("Você deve \(money) a \(groups[0].counterparty.name)")
                        : L10n.tr("Você deve \(money) a \(groups.count) pessoas"),
                    since: since
                )
            case .owedToYou:
                return DebtSummary(
                    key: "owedToYou",
                    kind: .debtOwedToYou,
                    title: L10n.tr(key: Notifications.debtOwedToYou.rawValue),
                    body: groups.count == 1
                        ? L10n.tr("\(groups[0].counterparty.name) te deve \(money)")
                        : L10n.tr("\(groups.count) pessoas te devem \(money)"),
                    since: since
                )
            }
        }
    }

    /// The next `count` weekly reminders after `now`: 7, 14, 21... days after `since`.
    static func fireDates(since: Date, after now: Date, count: Int) -> [Date] {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: since)
        var result: [Date] = []
        while result.count < count {
            guard let next = calendar.date(byAdding: .day, value: 7, to: day) else { break }
            day = next
            if let fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day), fire > now {
                result.append(fire)
            }
        }
        return result
    }

    /// The latest weekly reminder that should already have shown, or `nil` before the first week.
    static func lastFireDate(since: Date, now: Date) -> Date? {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: since)
        var last: Date?
        while let next = calendar.date(byAdding: .day, value: 7, to: day),
              let fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: next),
              fire <= now {
            last = fire
            day = next
        }
        return last
    }

    /// `date`, or 10h of the next morning when it falls during the night.
    static func daytime(_ date: Date) -> Date {
        let calendar = Calendar.current
        let current = calendar.component(.hour, from: date)
        if (9..<21).contains(current) { return date }
        let base = current < 9 ? date : (calendar.date(byAdding: .day, value: 1, to: date) ?? date)
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base) ?? date
    }
}
