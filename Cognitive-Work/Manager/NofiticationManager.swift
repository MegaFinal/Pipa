//
//  NofiticationManager.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 26/10/26.
//

import CloudKit
import Foundation
import UserNotifications

/// Sends and receives the house's notifications.
///
/// Sending saves a ``NotificationCloudDTO`` record in CloudKit for each recipient. Receiving
/// happens when a silent push (or the app coming to the foreground) triggers
/// ``processIncoming()``, which pulls the new records and schedules them as local notifications.
///
/// ## The envelope
/// ``send(_:)`` stamps the record's `userInfo` with ``UserInfoKey/senderID`` and
/// ``UserInfoKey/createdAt``; who it is for travels in ``NotificationCloudDTO/recipientIDs``.
/// The caller only fills the keys that say where a tap goes: ``UserInfoKey/kind`` (a
/// `Notifications` raw value) and, for late chores, ``UserInfoKey/choreRecordName`` and
/// ``UserInfoKey/assignmentRecordName``.
@Observable
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {

    /// The single instance used by the app.
    static let shared = NotificationManager()
    
    let center = UNUserNotificationCenter.current()
    
    /// The keys the manager reads and writes in a notification's `userInfo`.
    /// Values must stay property-list types (`String`, `Double`, ...).
    enum UserInfoKey {
        /// A `Notifications` raw value. Decides where a tap goes. Set by the caller.
        static let kind = "kind"
        /// `recordName` of the late chore. Set by the caller for the two late-chore kinds.
        static let choreRecordName = "choreRecordName"
        /// `recordName` of the chore's occurrence, for recurring chores. Optional.
        static let assignmentRecordName = "assignmentRecordName"
        /// `ownerRecordName` of the person who sent it. Set by ``send(_:)``.
        static let senderID = "senderID"
        /// When it was sent, as seconds since 1970. Set by ``send(_:)``.
        static let createdAt = "createdAt"
        /// Title format (a `Localizable.xcstrings` key). Filled in on the receiving device, so
        /// each person reads it in their own language. Optional: without it the DTO's title is used.
        static let titleKey = "titleKey"
        /// The `%@` values of ``titleKey``, as `[String]`.
        static let titleArgs = "titleArgs"
        /// Body format, like ``titleKey``.
        static let bodyKey = "bodyKey"
        /// The `%@` values of ``bodyKey``, as `[String]`.
        static let bodyArgs = "bodyArgs"
    }

    /// `key` translated into the app's current language and filled with `arguments` (`%@`).
    /// Arguments that are default content (such as a default chore name) are translated too.
    static func localized(_ key: String, _ arguments: [String] = []) -> String {
        guard !arguments.isEmpty else { return L10n.tr(key: key) }
        let values = arguments.map { $0.localizedDefault as CVarArg }
        return String(format: L10n.tr(key: key), locale: L10n.locale, arguments: values)
    }
    
    /// How long a record stays relevant. Older records are deleted without being scheduled
    /// (same window as ``NotificationsViewModel/lifetimeInDays``).
    static let maxAge: TimeInterval = 14 * 24 * 60 * 60
    
    /// `UserDefaults` key of the "Permitir notificações" switch in the general settings.
    /// It is off until the user turns it on.
    static let enabledKey = "notificationsEnabled"
    
    /// `UserDefaults` key of the record names already handled, with the day each was handled.
    private static let processedKey = "notifications.processedRecords"
    
    /// Set when the user taps a notification. The UI observes it, navigates and sets it back
    /// to `nil`.
    var pendingDestination: NotificationDestination?
    
    /// Whether the notifications screen has something the user hasn't seen. Drives the red dot
    /// on the bell; see ``refreshUnseenNotifications(force:)``.
    var hasUnseenNotifications = false
    
    /// The last time ``hasUnseenNotifications`` was recalculated.
    @ObservationIgnored private var lastUnseenCheck: Date?
    
    /// Listens to ``Notification/Name/cloudKitDidChange``. Guarded by ``lock``.
    @ObservationIgnored private var changeObserver: NSObjectProtocol?
    /// The check waiting to run after a change. Guarded by ``lock``.
    @ObservationIgnored private var changeCheckTask: Task<Void, Never>?
    
    @ObservationIgnored private let defaults = UserDefaults.standard
    
    /// Whether the user allows notifications in the app's settings (separate from the system
    /// permission, which ``authorizationStatus()`` reports).
    var isEnabledByUser: Bool {
        return defaults.bool(forKey: Self.enabledKey)
    }
    /// Guards ``processingTask``.
    @ObservationIgnored private let lock = NSLock()
    /// The ``processIncoming()`` run in flight, so two triggers at once share one run.
    @ObservationIgnored private var processingTask: Task<Void, Never>?
    
    /// Use ``shared``.
    private override init() {
        super.init()
    }

    // MARK: - Setup and permission

    /// Sets this manager as the notification center's delegate. Call it from `didFinishLaunching`.
    func configure() {
        center.delegate = self
        observeCloudKitChanges()
    }
    
    /// Looks for new notifications whenever the house's data changes
    /// (``Notification/Name/cloudKitDidChange``), wherever that is posted. Safe to call twice.
    private func observeCloudKitChanges() {
        lock.lock()
        defer { lock.unlock() }
        guard changeObserver == nil else { return }
        
        changeObserver = NotificationCenter.default.addObserver(
            forName: .cloudKitDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.checkForNotificationsSoon()
        }
    }
    
    /// Waits a moment, because changes come in bursts, and then looks for new notifications.
    private func checkForNotificationsSoon() {
        lock.lock()
        defer { lock.unlock() }
        changeCheckTask?.cancel()
        changeCheckTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            await self.processIncoming()
            await self.refreshUnseenNotifications()
        }
    }

    /// Asks the user for permission to show notifications.
    /// - Returns: `true` if the user granted it.
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        }
        catch {
            return false
        }
    }

    /// The current permission status, which the user can change at any time in Settings.
    func authorizationStatus() async -> UNAuthorizationStatus {
        let status = await center.notificationSettings().authorizationStatus
        return status
    }

    // MARK: - Sending

    /// Saves one notification record, addressed to ``NotificationCloudDTO/recipientIDs``.
    ///
    /// The record lives in the house's zone with the house as parent, so all members see it.
    /// The current user is dropped from the recipients and people listed twice count once.
    /// - Parameter dto: The notification to send. Its `userInfo` should carry ``UserInfoKey/kind``.
    /// - Returns: `true` if the record was saved, or if there was nobody left to send it to.
    func send(_ dto: NotificationCloudDTO) async -> Bool {
        // The iCloud account's ID is the `ownerRecordName` of the person's member records.
        guard let house = try? await CloudKitManager.shared.currentHouse(),
              let houseID = house.recordID,
              let myID = await CloudKitManager.shared.fetchCurrentUserRecordID()?.recordName
        else { return false }
        
        var seen: Set<String> = [myID]
        let recipients = dto.recipientIDs.filter { seen.insert($0).inserted }
        guard !recipients.isEmpty else { return true }
        
        var info = dto.userInfo
        info[UserInfoKey.senderID] = myID
        info[UserInfoKey.createdAt] = Date().timeIntervalSince1970
        
        let stamped = NotificationCloudDTO(
            title: dto.title,
            body: dto.body,
            soundName: dto.soundName,
            threadIdentifier: dto.threadIdentifier,
            recipientIDs: recipients,
            userInfo: info,
            fireDate: dto.fireDate
        )
        // Starts with a letter: record names can't start with an underscore.
        let recordID = CKRecord.ID(recordName: "notif-\(UUID().uuidString)", zoneID: houseID.zoneID)
        
        let saved = await CloudKitManager.shared.create(
            stamped,
            id: recordID,
            zoneID: houseID.zoneID,
            parent: CKRecord.Reference(recordID: houseID, action: .none)
        )
        return saved != nil
    }

    // MARK: - Receiving

    /// Entry point of the receiving flow: fetches the records, schedules the ones that list the
    /// current user and haven't been scheduled yet, and deletes the expired ones. Called by a
    /// silent push and when the app returns to the foreground.
    ///
    /// Calls that arrive while a run is in flight wait for that run instead of starting another.
    func processIncoming() async {
        await joinOrStartProcessing().value
    }
    
    /// Returns the run in flight, or starts one.
    private func joinOrStartProcessing() -> Task<Void, Never> {
        lock.lock()
        defer { lock.unlock() }
        if let processingTask { return processingTask }
        
        let task = Task { [self] in
            await runProcessing()
            finishProcessing()
        }
        processingTask = task
        return task
    }
    
    private func finishProcessing() {
        lock.lock()
        processingTask = nil
        lock.unlock()
    }
    
    /// One pass over the records: schedule mine, then delete what expired.
    ///
    /// A record is shared by all its recipients, so one of them can't delete it after
    /// scheduling it. Each device remembers what it handled (``markProcessed(_:)``) and the
    /// record is deleted once it is older than ``maxAge``.
    private func runProcessing() async {
        guard let myID = await CloudKitManager.shared.fetchCurrentUserRecordID()?.recordName
        else { return }
        
        let cutoff = Date().addingTimeInterval(-Self.maxAge).timeIntervalSince1970
        var expired: [NotificationCloudDTO] = []
        
        for dto in await fetchChanges() {
            guard let recordName = dto.recordID?.recordName,
                  let createdAt = dto.userInfo[UserInfoKey.createdAt] as? Double
            else { continue } // not one of ours
            
            // Too old to matter, whoever it was for: clean it up.
            if createdAt < cutoff {
                expired.append(dto)
                continue
            }
            
            guard dto.recipientIDs.contains(myID),
                  !isProcessed(recordName) else { continue }
            
            // Switch off: skip it for good, so turning the switch on later doesn't dump
            // everything that piled up in the meantime.
            guard isEnabledByUser else {
                markProcessed(recordName)
                continue
            }
            
            // If this fails (e.g. no permission) it is tried again on the next run.
            if await schedule(dto) {
                markProcessed(recordName)
            }
        }
        
        await deleteConsumed(expired)
    }

    /// Fetches the notification records visible to the current user, in both the private and
    /// the shared database. Records are filtered by recipient and age in ``processIncoming()``.
    func fetchChanges() async -> [NotificationCloudDTO] {
        return await CloudKitManager.shared.fetchAll(NotificationCloudDTO.self)
    }

    /// Deletes records from CloudKit. Only expired records are passed in, since a record can
    /// still be waiting for other recipients.
    func deleteConsumed(_ items: [NotificationCloudDTO]) async {
        let idsByZone = Dictionary(grouping: items.compactMap(\.recordID), by: \.zoneID)
        for (zoneID, ids) in idsByZone {
            _ = await CloudKitManager.shared.delete(recordIDs: ids, zoneID: zoneID)
        }
    }

    // MARK: - Scheduling

    /// Builds the content, trigger and request of `dto` and adds it to the notification center.
    /// The request's identifier is the record name, so scheduling the same record twice
    /// replaces the notification instead of duplicating it.
    /// - Returns: `false` if the record has no ID, the switch in the settings is off, the user
    ///   hasn't allowed notifications in iOS or the system refused the request.
    @discardableResult
    func schedule(_ dto: NotificationCloudDTO) async -> Bool {
        guard let id = dto.recordID?.recordName, isEnabledByUser else { return false }
        
        // Without permission `add` succeeds and nothing ever shows.
        switch await authorizationStatus() {
        case .authorized, .provisional, .ephemeral: break
        default: return false
        }

        let content = buildContent(from: dto)
        
        let trigger: UNNotificationTrigger? = makeTrigger(from: dto)

        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        
        do {
            try await center.add(request)
            return true
        }
        catch {
            print("Failed to schedule notification \(id): \(error)")
            return false
        }
    }

    /// Builds the notification's content from `dto`.
    func buildContent(from dto: NotificationCloudDTO) -> UNMutableNotificationContent {
        let info = dto.userInfo
        let content = UNMutableNotificationContent()
        // Text built from keys is translated here, on the receiving device.
        if let key = info[UserInfoKey.titleKey] as? String, !key.isEmpty {
            content.title = Self.localized(key, info[UserInfoKey.titleArgs] as? [String] ?? [])
        } else {
            content.title = dto.title
        }
        if let key = info[UserInfoKey.bodyKey] as? String, !key.isEmpty {
            content.body = Self.localized(key, info[UserInfoKey.bodyArgs] as? [String] ?? [])
        } else {
            content.body = dto.body
        }
        content.sound = dto.sound
        content.userInfo = dto.userInfo
        content.threadIdentifier = dto.threadIdentifier
        
        return content
    }

    /// The trigger for `dto`'s fire date: `nil` (shows up immediately) when it has no date or
    /// the date is already in the past, because a calendar trigger in the past never fires.
    func makeTrigger(from dto: NotificationCloudDTO) -> UNNotificationTrigger? {
        guard let fireDate = dto.fireDate, fireDate > .now,
              let components = dto.dateComponent else { return nil }
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    /// Cancels a pending notification and removes it from the Notification Center if it was
    /// already delivered.
    /// - Parameter id: The identifier it was scheduled with (the record name).
    func cancel(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    /// Cancels every pending notification (leaving the house, logging out).
    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        NotificationsViewModel.clearCache()
    }

    // MARK: - Processed state

    /// Remembers that the record `id` was already handled. Entries older than twice
    /// ``maxAge`` are dropped, since such a record would be discarded as expired anyway.
    func markProcessed(_ id: String) {
        var processed = processedRecords()
        let now = Date().timeIntervalSince1970
        processed[id] = now
        processed = processed.filter { now - $0.value < Self.maxAge * 2 }
        defaults.set(processed, forKey: Self.processedKey)
    }

    /// Whether the record `id` was already handled.
    func isProcessed(_ id: String) -> Bool {
        return processedRecords()[id] != nil
    }
    
    /// Record name → when it was handled, in seconds since 1970.
    private func processedRecords() -> [String: Double] {
        return defaults.dictionary(forKey: Self.processedKey) as? [String: Double] ?? [:]
    }

    // MARK: - Unseen notifications (the bell's dot)

    /// Recalculates ``hasUnseenNotifications`` with the same rules as the notifications screen
    /// (anything newer than the last time the user opened it). Calls less than two minutes
    /// apart are skipped, because it reads CloudKit.
    /// - Parameter force: Pass `true` right after a notification arrived.
    @MainActor
    func refreshUnseenNotifications(force: Bool = false) async {
        if !force, let last = lastUnseenCheck, Date().timeIntervalSince(last) < 120 { return }
        lastUnseenCheck = Date()
        
        let viewModel = NotificationsViewModel()
        await viewModel.load()
        hasUnseenNotifications = viewModel.newCount > 0
    }

    /// The user saw the notifications screen: the dot goes away.
    @MainActor
    func markNotificationsSeen() {
        hasUnseenNotifications = false
    }

    // MARK: - Routing

    /// Hands the destination of a tapped notification to the UI through ``pendingDestination``.
    @MainActor
    func route(to destination: NotificationDestination) {
        pendingDestination = destination
    }
    
    /// Turns a notification's `userInfo` into the screen it should open, or `nil` when it
    /// doesn't say or the chore no longer exists.
    ///
    /// Only IDs travel in `userInfo`; the chore is looked up now, because it may have changed
    /// since the notification was scheduled.
    func resolveDestination(from userInfo: [AnyHashable: Any]) async -> NotificationDestination? {
        guard let raw = userInfo[UserInfoKey.kind] as? String,
              let kind = Notifications(rawValue: raw) else { return nil }
        
        switch kind {
        case .grabChore: return .pickChores
        case .retrospective: return .retrospective
        case .newDivision: return .dashboard
        case .newUser: return .newMember
        case .itemBought: return .shopList
        case .debtYouOwe, .debtOwedToYou: return .pendingPayments
        case .calendarSync: return .calendarSync
        case .yourDelayedChore, .noUserDelayedChore, .choreDoneForYou:
            guard let choreName = userInfo[UserInfoKey.choreRecordName] as? String else { return nil }
            let snapshot = await HouseDataStore.shared.load()
            guard let chore = snapshot.chores.first(where: { $0.recordID?.recordName == choreName })
            else { return nil }
            
            let assignment = (userInfo[UserInfoKey.assignmentRecordName] as? String).flatMap { name in
                snapshot.assignments.first { $0.recordID?.recordName == name }
            }
            return .chore(chore, assignment)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Decides how a notification shows up while the app is open.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .list, .sound]
    }

    /// Called when the user taps a notification; reads its `userInfo` and routes to the screen.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let destination = await resolveDestination(from: userInfo) else { return }
        await route(to: destination)
    }
}
