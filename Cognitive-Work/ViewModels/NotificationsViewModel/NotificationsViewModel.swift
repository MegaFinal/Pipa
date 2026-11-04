//
//  NotificationsViewMode.swift
//  Cognitive-Work
//
//  Created by Isabela Hissa Pinto on 30/09/26.
//

import SwiftUI
import CloudKit

/// Where the app takes the user when a notification is tapped.
/// Cases carry the data they need (which user, which chore).
enum NotificationDestination {
    /// The list of unassigned chores, to pick some.
    case pickChores
    /// The retrospective.
    case retrospective
    /// The progress tab (Dashboard).
    case dashboard
    /// Someone joined the house: offers to redo the division (the pop-up only opens for the admin).
    case newMember
    /// A chore (and, for a recurring chore, the occurrence) to open.
    case chore(ChoreModel, RecurrentAssignmentModel?)
    /// The shopping list tab.
    case shopList
    /// The screen with the debts between housemates.
    case pendingPayments
    /// The Apple Calendar sync switch, in the general settings.
    case calendarSync
}

/// One notification on the notifications screen.
struct NotificationModel: Identifiable {
    /// Stable identifier, so the same notification isn't counted twice.
    let id: String
    /// The kind of notification (icon and color).
    let kind: Notifications
    /// The first line, translated.
    let title: String
    /// The second line, translated. May be empty.
    let subtitle: String
    /// When it happened; notifications are grouped by this day.
    let date: Date
    /// Where tapping it takes the user.
    let destination: NotificationDestination
}

/// A "hoje" / "ontem" / "23 de setembro" group.
struct NotificationSection: Identifiable {
    /// The day of the group.
    let day: Date
    /// The day's notifications, newest first.
    let items: [NotificationModel]
    /// Identifier for SwiftUI lists (the day).
    var id: Date { day }
}

/// Builds the notifications screen from the house's data: chores to pick, late chores, new
/// members, new divisions and the retrospective, plus payments, the calendar suggestion and the
/// notifications other members caused (a chore done for you, an item bought), which are read from
/// the records ``NotificationManager`` keeps in CloudKit for 14 days. Nothing else is stored;
/// everything is derived.
///
/// A notification is "new" when it happened after the screen was last opened.
@Observable
class NotificationsViewModel {

    /// How many days back notifications are shown.
    static let lifetimeInDays = 14
    /// `UserDefaults` key of the last time the user opened the screen.
    private static let lastSeenKey = "notifications.lastSeenDate"

    /// The notifications, grouped by day, newest day first.
    private(set) var sections: [NotificationSection] = []
    /// How many notifications are new.
    private(set) var newCount = 0
    /// `true` while loading.
    private(set) var isLoading = false

    /// The calendar used to group by day.
    private let calendar = Calendar.current
    /// Where the last-seen date is saved.
    private let defaults = UserDefaults.standard

    /// The snapshot and day the current `sections` were built for.
    @ObservationIgnored private var builtSnapshotID: UUID?
    @ObservationIgnored private var builtDay: Date?
    /// The notifications derived from that snapshot (before the 14-day window).
    @ObservationIgnored private var derivedItems: [NotificationModel] = []
    /// The notifications that come from CloudKit records and shop items, reloaded on every ``load(force:now:)``.
    @ObservationIgnored private var extraItems: [NotificationModel] = []

    // MARK: - Cache

    /// What the last ``load(force:now:)`` built, kept for the whole app session so the screen
    /// opens with it right away while a fresh load runs (stale-while-revalidate). Every
    /// instance shares it, including the one the bell uses to count unseen notifications.
    private final class Cache: @unchecked Sendable {
        struct Entry {
            var derivedItems: [NotificationModel]
            var extraItems: [NotificationModel]
            var snapshotID: UUID?
            var day: Date?
        }
        private let lock = NSLock()
        private var entry: Entry?
        
        var value: Entry? {
            get { lock.lock(); defer { lock.unlock() }; return entry }
            set { lock.lock(); entry = newValue; lock.unlock() }
        }
    }
    private static let cache = Cache()
    
    /// Forgets the cached notifications (leaving the house, logging out).
    static func clearCache() {
        cache.value = nil
    }
    
    /// Starts with the cached notifications, if there are any, so the screen isn't empty
    /// while ``load(force:now:)`` runs.
    init() {
        guard let cached = Self.cache.value else { return }
        derivedItems = cached.derivedItems
        extraItems = cached.extraItems
        builtSnapshotID = cached.snapshotID
        builtDay = cached.day
        publish(now: Date())
    }

    // MARK: - Loading

    /// Reads the house data from `HouseDataStore`, which only hits CloudKit when its data is
    /// missing or stale, and reloads the notification records and the shopping list (for the
    /// payments), which can change without the house data changing.
    /// - Parameter force: `true` for pull-to-refresh, to bypass the store's cache.
    func load(force: Bool = false, now: Date = Date()) async {
        let store = HouseDataStore.shared
        if sections.isEmpty && !store.isUpToDate { isLoading = true }
        defer { isLoading = false }

        let snapshot = await store.load(force: force)
        guard !Task.isCancelled else { return }

        // Same data and same day: the notifications derived from the snapshot are still correct.
        let isSnapshotCurrent = snapshot.id == builtSnapshotID
            && builtDay.map { calendar.isDate($0, inSameDayAs: now) } == true
        if !isSnapshotCurrent {
            derivedItems = derivedNotifications(from: snapshot, now: now)
            builtSnapshotID = snapshot.id
            builtDay = now
            // Shows the new derived items right away, with the cached extras, while the
            // CloudKit records are fetched.
            publish(now: now)
        }

        extraItems = await loadExtraNotifications(snapshot: snapshot, now: now)
        guard !Task.isCancelled else { return }
        publish(now: now)
        
        Self.cache.value = Cache.Entry(
            derivedItems: derivedItems,
            extraItems: extraItems,
            snapshotID: builtSnapshotID,
            day: builtDay
        )
    }

    /// Builds every notification that comes from the house's data already in memory. No CloudKit calls.
    private func derivedNotifications(from snapshot: HouseSnapshot, now: Date) -> [NotificationModel] {
        guard let me = snapshot.houseUser else { return [] }

        // Fast lookup tables: recordID → object.
        let choresByID = Dictionary(
            snapshot.chores.compactMap { chore in chore.recordID.map { ($0, chore) } },
            uniquingKeysWith: { first, _ in first }
        )
        let roomNameByID = Dictionary(
            snapshot.rooms.compactMap { room in room.recordID.map { ($0, room.name) } },
            uniquingKeysWith: { first, _ in first }
        )
        // The same person may have more than one UserModel (same ownerRecordName).
        let myIDs = Set(
            ([me] + snapshot.users.filter { $0.ownerRecordName == me.ownerRecordName })
                .compactMap{ $0.recordID }
        )

        let windowStart = calendar.date(
            byAdding: .day, value: -Self.lifetimeInDays, to: calendar.startOfDay(for: now)
        ) ?? now

        var all: [NotificationModel] = []
        // Recurring days and one-off chores, in a single shape (see `Occurrence`).
        let occurrences = makeOccurrences(chores: snapshot.chores, assignments: snapshot.assignments,
                                          choresByID: choresByID)

        all += grabChoreNotifications(occurrences, from: windowStart, now: now)
        all += lateChoreNotifications(occurrences, roomNameByID: roomNameByID, myIDs: myIDs, now: now)
        all += divisionNotifications(snapshot.assignments)
        all += newUserNotifications(snapshot.users, myIDs: myIDs)

        return all
    }

    /// Merges every source, keeps the last 14 days and groups by day.
    private func publish(now: Date) {
        let windowStart = calendar.date(
            byAdding: .day, value: -Self.lifetimeInDays, to: calendar.startOfDay(for: now)
        ) ?? now

        // The 14-day rule lives in a single place (and nothing from the future shows up).
        let all = (derivedItems + extraItems).filter { $0.date >= windowStart && $0.date <= now }

        sections = makeSections(from: all)
        newCount = all.filter { $0.date > lastSeenDate }.count
    }

    // MARK: - Notifications from CloudKit

    /// The notifications that don't come from the house's chores: what other members caused
    /// (records saved by ``NotificationManager``), the payments and the calendar suggestion.
    private func loadExtraNotifications(snapshot: HouseSnapshot, now: Date) async -> [NotificationModel] {
        guard let me = snapshot.houseUser else { return [] }

        async let records = NotificationManager.shared.fetchChanges()
        async let shopItems = CloudKitManager.shared.fetchAll(ShopListItem.self)
        let (dtos, items) = await (records, shopItems)
        let myID = await CloudKitManager.shared.fetchCurrentUserRecordID()?.recordName ?? me.ownerRecordName

        var result = await recordNotifications(dtos, myID: myID)
        result += debtNotifications(items, snapshot: snapshot, now: now)
        result += calendarNotification(snapshot, now: now)
        return result
    }

    /// "X fez a tarefa Y por você" and "X comprou Y": the records addressed to `myID`. Other
    /// kinds of record (a new division, a new member) already show up from the house's data.
    private func recordNotifications(_ dtos: [NotificationCloudDTO], myID: String) async -> [NotificationModel] {
        typealias Keys = NotificationManager.UserInfoKey
        var result: [NotificationModel] = []

        for dto in dtos {
            guard let recordName = dto.recordID?.recordName,
                  dto.recipientIDs.contains(myID),
                  let createdAt = dto.userInfo[Keys.createdAt] as? Double,
                  let raw = dto.userInfo[Keys.kind] as? String,
                  let kind = Notifications(rawValue: raw),
                  kind == .choreDoneForYou || kind == .itemBought,
                  let titleKey = dto.userInfo[Keys.titleKey] as? String
            else { continue }

            let title = NotificationManager.localized(titleKey, dto.userInfo[Keys.titleArgs] as? [String] ?? [])
            var subtitle = ""
            if let bodyKey = dto.userInfo[Keys.bodyKey] as? String, !bodyKey.isEmpty {
                subtitle = NotificationManager.localized(bodyKey, dto.userInfo[Keys.bodyArgs] as? [String] ?? [])
            }
            // A chore that no longer exists has nowhere to go: falls back to the progress tab.
            let destination = await NotificationManager.shared.resolveDestination(from: dto.userInfo) ?? .dashboard

            result.append(
                NotificationModel(
                    id: "record-\(recordName)",
                    kind: kind,
                    title: title,
                    subtitle: subtitle,
                    date: Date(timeIntervalSince1970: createdAt),
                    destination: destination
                )
            )
        }
        return result
    }

    /// "Você tem pagamentos pendentes" and "...a receber", from the first weekly reminder on
    /// (the same dates the push is scheduled for). The date moves forward every week.
    private func debtNotifications(
        _ items: [ShopListItem], snapshot: HouseSnapshot, now: Date
    ) -> [NotificationModel] {
        let ledger = DebtCalculator.ledger(
            items: items,
            users: snapshot.users,
            userRecords: snapshot.userRecords,
            me: snapshot.houseUser
        )
        return DebtReminders.summaries(from: ledger).compactMap { summary -> NotificationModel? in
            guard let date = DebtReminders.lastFireDate(since: summary.since, now: now) else { return nil }
            return NotificationModel(
                id: "debt-\(summary.key)",
                kind: summary.kind,
                title: summary.title,
                subtitle: summary.body,
                date: date,
                destination: .pendingPayments
            )
        }
    }

    /// Suggests the Apple Calendar sync to a member who joined in the last week and hasn't turned it on.
    private func calendarNotification(_ snapshot: HouseSnapshot, now: Date) -> [NotificationModel] {
        guard !UserDefaults.standard.bool(forKey: "isCalendarSyncEnabled"),
              let joined = snapshot.houseUser?.joinedAt,
              now.timeIntervalSince(joined) < 7 * 24 * 3600 else { return [] }

        return [
            NotificationModel(
                id: "calendar-sync",
                kind: .calendarSync,
                title: L10n.tr(key: Notifications.calendarSync.rawValue),
                subtitle: L10n.tr(key: Notifications.calendarSync.subTitle),
                date: joined,
                destination: .calendarSync
            )
        ]
    }

    // MARK: - Occurrences

    /// One scheduled instance of a chore, whatever kind of chore it is:
    /// - a recurring chore → one per assignment (each day has its own users and done state);
    /// - a one-off chore → the chore itself (no assignments: it uses its own `dueDate`,
    ///   responsible users and `isDone`).
    /// The builders below only deal with this type, so they don't care which kind it is.
    private struct Occurrence {
        let chore: ChoreModel
        /// `nil` for one-off chores.
        let assignment: RecurrentAssignmentModel?
        /// Start of the day this instance is scheduled for.
        let day: Date
        let userIDs: [CKRecord.ID]
        let isDone: Bool

        var isUnassigned: Bool { userIDs.isEmpty }
    }

    /// Turns assignments and one-off chores into ``Occurrence``s.
    /// Same rules as `CarouselViewModel.rebuildUnassignedItems` for one-off chores.
    private func makeOccurrences(
        chores: [ChoreModel],
        assignments: [RecurrentAssignmentModel],
        choresByID: [CKRecord.ID: ChoreModel]
    ) -> [Occurrence] {
        // Recurring chores: one occurrence per assignment whose chore still exists.
        var result: [Occurrence] = assignments.compactMap { assignment -> Occurrence? in
            guard let chore = assignment.choreReference.flatMap({ choresByID[$0.recordID] }) else { return nil }
            return Occurrence(
                chore: chore,
                assignment: assignment,
                day: calendar.startOfDay(for: assignment.day),
                userIDs: (assignment.userReferences ?? []).map(\.recordID),
                isDone: assignment.isCompleted
            )
        }

        // One-off chores: no assignments, so the chore is its own occurrence.
        for chore in chores where (chore.dailyAssignmentsReference ?? []).isEmpty {
            // Without a date it is never "today" nor "late", so it can't become a notification.
            guard let dueDate = chore.dueDate else { continue }

            var userIDs = (chore.allResponsibleUsersReference ?? []).map(\.recordID)
            if let current = chore.currentResponsibleReference?.recordID, !userIDs.contains(current) {
                userIDs.append(current)
            }

            result.append(
                Occurrence(
                    chore: chore,
                    assignment: nil,
                    day: calendar.startOfDay(for: dueDate),
                    userIDs: userIDs,
                    isDone: chore.isDone
                )
            )
        }
        return result
    }

    // MARK: - Notification builders

    /// "N tarefas a pegar hoje": one item per day that has unclaimed occurrences.
    private func grabChoreNotifications(
        _ occurrences: [Occurrence],
        from start: Date, now: Date
    ) -> [NotificationModel] {
        let today = calendar.startOfDay(for: now)

        let open = occurrences.filter { occurrence in
            occurrence.isUnassigned && !occurrence.isDone
                && occurrence.day >= start && occurrence.day <= today
        }

        let byDay = Dictionary(grouping: open) { $0.day }

        return byDay.map { day, list in
            NotificationModel(
                id: "grab-\(day.timeIntervalSince1970)",
                kind: .grabChore,
                // Plural rules ("1 tarefa" / "3 tarefas") live in Localizable.xcstrings.
                title: L10n.tr("\(list.count) tarefas a pegar hoje"),
                subtitle: L10n.tr(key: Notifications.grabChore.subTitle),
                date: day,
                destination: .pickChores
            )
        }
    }

    /// "X está atrasado" (mine) and "Ninguém pegou X" (unclaimed).
    private func lateChoreNotifications(
        _ occurrences: [Occurrence],
        roomNameByID: [CKRecord.ID: String],
        myIDs: Set<CKRecord.ID>,
        now: Date
    ) -> [NotificationModel] {
        let today = calendar.startOfDay(for: now)

        return occurrences.compactMap { occurrence -> NotificationModel? in
            guard !occurrence.isDone,
                  occurrence.day < today,
                  // A chore becomes late on the day AFTER its scheduled day.
                  let lateSince = calendar.date(byAdding: .day, value: 1, to: occurrence.day)
            else { return nil }

            let chore = occurrence.chore
            // Default chores are stored in Portuguese; `localizedDefault` translates them.
            let choreName = chore.name.localizedDefault
            let kind: Notifications
            let title: String

            if occurrence.isUnassigned {
                kind = .noUserDelayedChore
                // Lowercase first letter so it reads well mid-sentence ("Ninguém pegou limpar...").
                let midSentenceName: String = choreName.prefix(1).lowercased() + choreName.dropFirst()
                title = L10n.tr("Ninguém pegou \(midSentenceName)")
            } else if occurrence.userIDs.contains(where: { myIDs.contains($0) }) {
                kind = .yourDelayedChore
                title = L10n.tr("\(choreName) está atrasado")
            } else {
                return nil // someone else's late chore: don't notify me
            }

            let room = chore.roomReference.flatMap { roomNameByID[$0.recordID]?.localizedDefault }
                ?? L10n.tr("Sem Cômodo")
            // Assignment id for recurring days, chore id for one-off chores.
            let recordName = occurrence.assignment?.recordID?.recordName
                ?? chore.recordID?.recordName
                ?? "\(chore.name)-\(lateSince)"

            return NotificationModel(
                id: "late-\(recordName)",
                kind: kind,
                title: title,
                subtitle: L10n.tr("\(room) · cerca de \(Int(chore.duration.rounded())) min"),
                date: lateSince,
                destination: .chore(chore, occurrence.assignment)
            )
        }
    }

    /// "Nova divisão pronta" + "Sua retrospectiva chegou", on the current cycle's first day.
    private func divisionNotifications(_ assignments: [RecurrentAssignmentModel]) -> [NotificationModel] {
        // Same rule as CarouselViewModel.cycleWindow: first day = last day − 14.
        guard let lastDay = assignments.map({ calendar.startOfDay(for: $0.day) }).max(),
              let cycleStart = calendar.date(byAdding: .day, value: -14, to: lastDay)
        else { return [] }

        var result = [
            NotificationModel(
                id: "division-\(cycleStart.timeIntervalSince1970)",
                kind: .newDivision,
                title: L10n.tr(key: Notifications.newDivision.rawValue),
                subtitle: L10n.tr(key: Notifications.newDivision.subTitle),
                date: cycleStart,
                destination: .dashboard
            )
        ]

        // On the very first division there is nothing to look back on.
        let hadPreviousCycle = assignments.contains { $0.day < cycleStart }
        if hadPreviousCycle {
            result.append(
                NotificationModel(
                    id: "retro-\(cycleStart.timeIntervalSince1970)",
                    kind: .retrospective,
                    title: L10n.tr(key: Notifications.retrospective.rawValue),
                    subtitle: L10n.tr(key: Notifications.retrospective.subTitle),
                    date: cycleStart,
                    destination: .retrospective
                )
            )
        }
        return result
    }

    /// "Fulano entrou na casa": everyone except me. Tapping it offers to redo the division.
    private func newUserNotifications(_ members: [UserModel], myIDs: Set<CKRecord.ID>) -> [NotificationModel] {
        members.compactMap { user -> NotificationModel? in
            guard let id = user.recordID, !myIDs.contains(id),
                  let joined = user.joinedAt else { return nil }

            return NotificationModel(
                id: "user-\(id.recordName)",
                kind: .newUser,
                title: L10n.tr("\(user.name) entrou na casa"),
                subtitle: L10n.tr(key: Notifications.newUser.subTitle),
                date: joined,
                destination: .newMember
            )
        }
    }

    // MARK: - Grouping and "seen" state

    /// Groups `items` by day, newest first.
    private func makeSections(from items: [NotificationModel]) -> [NotificationSection] {
        Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }
            .map { NotificationSection(day: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    /// The section's title: "hoje", "ontem" or the date, translated.
    func title(for section: NotificationSection) -> String {
        if calendar.isDateInToday(section.day) { return L10n.tr("hoje") }
        if calendar.isDateInYesterday(section.day) { return L10n.tr("ontem") }
        // Follows the app language: "23 de setembro" / "September 23".
        return section.day.formatted(.dateTime.day().month(.wide).locale(L10n.locale))
    }

    /// "N novas notificações", or a "nothing new" message, translated.
    var newCountText: String {
        // Singular/plural ("1 nova notificação" / "3 novas notificações") come from Localizable.xcstrings.
        newCount == 0
            ? L10n.tr("Nenhuma notificação nova")
            : L10n.tr("\(newCount) novas notificações")
    }

    /// The last time the user opened the screen (or the distant past).
    private var lastSeenDate: Date {
        defaults.object(forKey: Self.lastSeenKey) as? Date ?? .distantPast
    }

    /// Marks every notification as seen (called when the screen closes).
    func markAllAsSeen(now: Date = Date()) {
        defaults.set(now, forKey: Self.lastSeenKey)
        Task { @MainActor in NotificationManager.shared.markNotificationsSeen() }
    }
}
