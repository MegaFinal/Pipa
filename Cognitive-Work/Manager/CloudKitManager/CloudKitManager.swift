//
//  CloudKitManager.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 11/08/26.
//

import CloudKit

/// Manages CloudKit operations for houses, users, and shared records.
///
/// Failing operations return `false` or `nil` and describe the reason in ``errorMessage``.
@Observable
class CloudKitManager {
    
    /// The shared instance of the CloudKit manager.
    static let shared = CloudKitManager()
    
    // MARK: - Properties
    
    /// The app's iCloud container.
    let container: CKContainer
    
    /// Database holding records owned by the current user.
    let privateDB: CKDatabase
    
    /// Database holding records shared with the current user by others.
    let sharedDB: CKDatabase
    
    /// Description of the most recent failure, or `nil` when none occurred.
    var errorMessage: String?
    
    /// Name of the custom zone that stores all house data.
    private let zoneName = "HomeEnvironment"
    
    /// Suffix appended to a private profile's `recordName` to derive the `recordName` of the
    /// copy that lives inside a house. See ``houseUserRecordID(for:inHouseZone:)``.
    private let houseUserSuffix = "-house"
    
    /// The custom zone owned by the current iCloud user.
    ///
    /// Use this zone only for operations that belong to the current user, such as creating the
    /// custom zone. For operations involving a specific house, use that house's
    /// `recordID.zoneID` instead.
    @ObservationIgnored
    lazy var houseZoneID = CKRecordZone.ID(
        zoneName: zoneName,
        ownerName: CKCurrentUserDefaultName
    )
    
    // MARK: - Session cache
    
    /// Whether ``createZoneIfNeeded()`` already confirmed the custom zone exists in this
    /// process. See that method for why this matters.
    @ObservationIgnored
    private var didEnsureZone = false
    
    /// The house resolved for this session, cached by ``currentHouse(forceRefresh:)``.
    @ObservationIgnored
    private var cachedHouse: HouseModel?
    
    /// This device's in-house profile, cached by ``currentHouseUser(forceRefresh:)``.
    @ObservationIgnored
    private var cachedHouseUser: UserModel?
    
    /// The zones of every house shared with this account, cached by ``sharedZones()``.
    @ObservationIgnored
    private var cachedSharedZones: [CKRecordZone]?
    
    /// In-flight house lookup, so concurrent callers share one request instead of racing.
    @ObservationIgnored
    private var houseLookup: Task<HouseModel?, Error>?
    
    /// In-flight in-house profile lookup, deduplicated the same way.
    @ObservationIgnored
    private var houseUserLookup: Task<UserModel?, Never>?
    
    /// In-flight shared-zone listing, deduplicated the same way. `nil` result means the
    /// listing failed and must not be cached.
    @ObservationIgnored
    private var sharedZonesLookup: Task<[CKRecordZone], Error>?
    
    // MARK: - Data revision
    
    /// Counter that changes whenever house data changes, locally or remotely.
    private(set) var dataRevision: Int = 0
    
    /// Records that house data changed, locally or remotely.
    ///
    /// Also invalidates ``HouseDataStore``, so the next tab that asks for the house data
    /// fetches it again. For changes pushed from another device the store is invalidated a
    /// second time by ``HouseDataStore/refreshAfterRemoteChange()``: this method runs a
    /// moment after the notification, so the second call is what guarantees that the screen
    /// reacting to the notification never gets the old snapshot.
    func markDataChanged() {
        Task { @MainActor in
            self.dataRevision &+= 1
            HouseDataStore.shared.invalidate()
        }
    }
    
    /// Connects to the app's iCloud container. Use ``shared``.
    private init() {
        container = CKContainer(
            identifier: "iCloud.JonasMelo.Cognitive-Work"
        )
        privateDB = container.privateCloudDatabase
        sharedDB = container.sharedCloudDatabase
        
        NotificationCenter.default.addObserver(
            forName: .cloudKitDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.markDataChanged()
        }
        
        // Another iCloud account signed in: the cached account ID belongs to the old one.
        NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.userRecordIDLookup = nil }
        }
    }
    
    
    /// A copy of `asset` in a new temporary file, so the same image can be saved in another record.
    /// - Throws: When the file can't be copied.
    private func duplicateCKAsset(_ asset: CKAsset) throws -> CKAsset? {
        guard let origem = asset.fileURL else { return nil }
        
        let destino = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        
        try FileManager.default.copyItem(at: origem, to: destino)
        return CKAsset(fileURL: destino)
    }
    
    // MARK: - Zone Management
    
    /// Creates the custom house zone if it does not already exist.
    ///
    /// - Parameter force: Pass `true` to re-issue the save even when the zone was already
    ///   confirmed in this process. Only ``deleteAllPrivateRecords()`` needs this, since it
    ///   drops the zone and has to recreate it for real.
    /// - Returns: `true` when the zone exists on the server, otherwise `false`.
    ///
    /// If the operation fails, ``errorMessage`` is updated with the corresponding CloudKit error.
    @discardableResult
    func createZoneIfNeeded(force: Bool = false) async -> Bool {
        if didEnsureZone && !force { return true }
        
        let zone = CKRecordZone(zoneID: houseZoneID)
        
        do {
            _ = try await privateDB.save(zone)
            didEnsureZone = true
            return true
        } catch {
            ICloudStorageMonitor.shared.report(error, in: privateDB)
            errorMessage = UserFacingError.message(for: error, doing: .save)
            return false
        }
    }
    
    // MARK: - Session-cached lookups
    
    /// The house this device belongs to, resolved once per session.
    /// - Parameter forceRefresh: Pass `true` to bypass the cache and re-resolve.
    func currentHouse(forceRefresh: Bool = false) async throws -> HouseModel? {
        // The list of shared zones goes too: a member the admin removed keeps the house's zone
        // in that list for the whole session otherwise, and every lookup keeps asking it.
        if forceRefresh {
            cachedHouse = nil
            cachedSharedZones = nil
        }

        if let cachedHouse { return cachedHouse }
        // A fetch already in flight is fresh enough — share it instead of cancelling it.
        if let houseLookup { return try await houseLookup.value }

        let lookup = Task<HouseModel?, Error> { [weak self] in
            guard let self else { return nil }
            do {
                return try await self.fetchFirst(HouseModel.self)
            } catch let error as CloudKitErrors<String> {
                // `fetchFirst` signals "no record" by throwing — for us that just means "no house".
                if case .notFound = error { return nil }
                throw error
            }
        }
        houseLookup = lookup
        defer { houseLookup = nil }

        let house = try await lookup.value
        cachedHouse = house
        return house
    }
    
    /// This device's in-house profile, resolved once per session.
    /// - Parameter forceRefresh: Pass `true` to bypass the cache and re-resolve.
    func currentHouseUser(forceRefresh: Bool = false) async -> UserModel? {
        if forceRefresh {
            cachedHouseUser = nil
            houseUserLookup?.cancel()
            houseUserLookup = nil
        }
        
        if let cachedHouseUser { return cachedHouseUser }
        if let houseUserLookup { return await houseUserLookup.value }
        
        let lookup = Task<UserModel?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.fetchMyHouseUser()
        }
        houseUserLookup = lookup
        
        let user = await lookup.value
        houseUserLookup = nil
        cachedHouseUser = user
        return user
    }
    
    /// Like ``sharedZones()``, but throws when CloudKit fails instead of returning `[]`
    /// (which would read as "this account has no shared house"). Resolved once per session;
    /// simultaneous callers share the same request.
    func sharedZonesOrThrow() async throws -> [CKRecordZone] {
        if let cachedSharedZones { return cachedSharedZones }
        if let sharedZonesLookup { return try await sharedZonesLookup.value }
        
        let lookup = Task<[CKRecordZone], Error> { [weak self] in
            guard let self else { return [] }
            return try await self.sharedDB.allRecordZones()
        }
        sharedZonesLookup = lookup
        defer { sharedZonesLookup = nil }
        
        let zones = try await lookup.value
        cachedSharedZones = zones
        return zones
    }
    
    /// Every record zone shared with this account, resolved once per session.
    func sharedZones() async -> [CKRecordZone] {
        do {
            return try await sharedZonesOrThrow()
        } catch {
            errorMessage = UserFacingError.message(for: error, doing: .share)
            return []
        }
    }
    
    /// Drops every session-cached lookup.
    ///
    /// Called automatically whenever something that could change the answers happens: a
    /// `HouseModel` or `UserModel` is created or deleted, a share is accepted, the current
    /// house is left or switched, or the local records are wiped. Onboarding creates its house
    /// and profile through ``create(_:id:zoneID:parent:)``, so it is covered without any change
    /// at its call sites.
    func invalidateSessionCache() {
        cachedHouse = nil
        cachedHouseUser = nil
        cachedSharedZones = nil
        houseLookup?.cancel()
        houseLookup = nil
        houseUserLookup?.cancel()
        houseUserLookup = nil
        sharedZonesLookup?.cancel()
        sharedZonesLookup = nil
    }
    
    // MARK: - Current User
    
    /// UserDefaults key used to remember which `UserModel` record belongs to whoever is
    /// using this device.
    private let currentUserRecordNameKey = "currentUserRecordName"
    
    /// Fetches the `UserModel` that belongs to this device, using the `recordID` persisted by
    /// ``setCurrentUser(_:)``.
    ///
    /// A user's own profile always lives in their own private zone (see ``create(_:zoneID:parent:)``),
    /// so this always reads from ``privateDB``.
    ///
    /// - Returns: The current user's profile, or `nil` when nothing was ever persisted or the
    ///   fetch fails.
    ///
    /// ## Session-restore fix
    /// This used to rely *only* on a `CKQuery` over `ownerRecordName`. When that field isn't
    /// indexed (or the query fails for any other reason) the error was swallowed and the method
    /// returned `nil`, so after closing the app mid-onboarding every screen lost the profile
    /// ("Seu perfil ainda não foi salvo", "Não foi possível salvar seus horários"). The lookup
    /// now tries, in order:
    /// 1. a direct read by the `recordName` saved with ``setCurrentUser(_:)`` (no index needed);
    /// 2. the original query;
    /// 3. an index-free scan of the private house zone.
    /// Whatever succeeds is remembered for the next launch.
    func fetchMyUser() async -> UserModel? {
        // Session-restore fix, step 1: direct read by the remembered record name.
        if let recordName = UserDefaults.standard.string(forKey: currentUserRecordNameKey) {
            let storedID = CKRecord.ID(recordName: recordName, zoneID: houseZoneID)
            if let record = try? await privateDB.record(for: storedID),
               let user = UserModel(record: record) {
                return user
            }
        }
        
        guard let recordID = await fetchCurrentUserRecordID()
        else { return nil }
        
        
        let predicate = NSPredicate(
            format: "ownerRecordName == %@",
            recordID.recordName
        )
        // Sync fix: for a house owner, the private zone holds *both* the private profile and
        // the in-house copy (see `houseUserRecordID(for:inHouseZone:)`), and both carry the same
        // `ownerRecordName`. Taking `.first` returned either one depending on server ordering,
        // so the "private profile" was sometimes the house copy. Prefer the real profile and
        // only fall back to whatever matched.
        let matches = await fetchPrivate(UserModel.self, predicate: predicate, desiredKeys: .all)
        if let user = matches.first(where: { !isHouseUser($0) }) ?? matches.first {
            setCurrentUser(user)
            return user
        }
        
        // Session-restore fix, step 3: index-free fallback over the private house zone.
        let scanned = await fetchZoneRecords(UserModel.self, inZone: houseZoneID)
            .filter { $0.ownerRecordName == recordID.recordName }
        if let user = scanned.first(where: { !isHouseUser($0) }) ?? scanned.first {
            setCurrentUser(user)
            return user
        }
        
        return nil
    }
    
    /// Remembers which private profile belongs to this device.
    ///
    /// Session-restore fix: ``isCurrentUser(_:)`` and ``clearCurrentUser()`` already used this
    /// key, but nothing ever wrote it, so the profile could only be recovered through a query.
    /// House copies are ignored: the stored name must always point at the private profile, from
    /// which the house copy is derived (see ``houseUserRecordID(for:inHouseZone:)``).
    func setCurrentUser(_ user: UserModel) {
        guard let recordID = user.recordID, !isHouseUser(user) else { return }
        UserDefaults.standard.set(recordID.recordName, forKey: currentUserRecordNameKey)
    }
    
    /// The `recordID` a user's in-house copy must be created with.
    ///
    /// A person ends up with two `UserModel` records: the private profile created by
    /// `OnboardingViewModel.createUser()`, and a copy inside the house's zone (created by
    /// `createHouseAndLinkUser()` for the owner, `joinHouse()` for an invited member). Nothing
    /// on the records themselves links the two, so the copy's name is *derived* from the
    /// private one instead — that is the only thing that makes ``fetchMyHouseUser()`` possible
    /// without a query.
    ///
    /// The suffix is what allows the house owner to have both records: their house lives in
    /// their own private zone, so an identical `recordName` in the same zone would simply be
    /// the same record.
    ///
    /// - Parameters:
    ///   - privateRecordID: `recordID` of the private profile.
    ///   - zoneID: Zone the house lives in (`house.recordID.zoneID`).
    func houseUserRecordID(
        for privateRecordID: CKRecord.ID,
        inHouseZone zoneID: CKRecordZone.ID
    ) -> CKRecord.ID {
        // Sync fix: the derivation is now idempotent. Callers such as
        // `OnboardingViewModel.joinHouse()` pass whatever `currentUser` holds, which after a
        // resumed session can already be the house copy. Appending the suffix again produced
        // `"…-house-house"`: the guest's public record (and therefore their free time) was
        // written under a name nobody ever reads, so the admin kept seeing them as pending.
        let baseName = recordNameStrippingHouseSuffix(privateRecordID.recordName)
        return CKRecord.ID(
            recordName: baseName + houseUserSuffix,
            zoneID: zoneID
        )
    }
    
    /// Removes the in-house suffix from a `recordName`, if present.
    ///
    /// Sync fix helper: inverse of ``houseUserRecordID(for:inHouseZone:)``, so a house copy can
    /// always be traced back to the private profile it was derived from.
    private func recordNameStrippingHouseSuffix(_ recordName: String) -> String {
        guard recordName.hasSuffix(houseUserSuffix) else { return recordName }
        return String(recordName.dropLast(houseUserSuffix.count))
    }
    
    /// Whether `user` is an in-house copy (visible to housemates) rather than the private profile.
    ///
    /// Sync fix helper: lets callers make sure free time and chores are written to the record
    /// the other device actually reads.
    func isHouseUser(_ user: UserModel) -> Bool {
        guard let recordName = user.recordID?.recordName else { return false }
        return recordName.hasSuffix(houseUserSuffix)
    }
    
    /// The signed-in iCloud account's record ID, read once and reused.
    ///
    /// It used to be a network round trip on every call, and opening the app called it several
    /// times in a row (leaving orphaned houses, checking the membership, notifications), each one
    /// waiting for the previous. It only changes when the iCloud account does
    /// (`CKAccountChanged`, which clears it); a failed read isn't kept, so the next call tries again.
    @ObservationIgnored
    private var userRecordIDLookup: Task<CKRecord.ID?, Never>?

    /// The record ID of the signed-in iCloud account, or `nil` when it can't be read.
    func fetchCurrentUserRecordID() async -> CKRecord.ID? {
        if let running = userRecordIDLookup {
            let cached = await running.value
            if let cached { return cached }
        }
        let container = self.container
        let lookup: Task<CKRecord.ID?, Never> = Task {
            try? await container.userRecordID()
        }
        userRecordIDLookup = lookup
        let recordID = await lookup.value
        if recordID == nil { userRecordIDLookup = nil }
        return recordID
    }
    
    /// Fetches this device's own `UserModel` record *inside the current house* — the one
    /// housemates can see, as opposed to the private profile returned by ``fetchMyUser()``.
    ///
    /// Reads the record directly by ID, derived via ``houseUserRecordID(for:inHouseZone:)``,
    /// so it needs no `CKQuery` and works the same whether the house is owned (private
    /// database) or joined through a share (shared database).
    ///
    /// - Returns: The in-house copy, or `nil` when there is no house yet, the house was
    ///   deleted, or the copy predates this naming convention.
    func fetchMyHouseUser() async -> UserModel? {
        guard let privateRecordID = await fetchMyUser()?.recordID,
              let houseZoneID = try? await currentHouse()?.recordID?.zoneID
        else {
            return nil
        }
        
        let recordID = houseUserRecordID(
            for: privateRecordID,
            inHouseZone: houseZoneID
        )
        let database = houseZoneID.ownerName == CKCurrentUserDefaultName ? privateDB : sharedDB
        
        do {
            return UserModel(record: try await database.record(for: recordID))
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        } catch {
            errorMessage = UserFacingError.message(for: error, doing: .load)
            return nil
        }
    }
    
    /// Whether `user` is the profile that belongs to this device, as opposed to a housemate
    /// fetched alongside it (e.g. via ``fetchAll(_:predicate:)``).
    func isCurrentUser(_ user: UserModel) -> Bool {
        guard let recordID = user.recordID else { return false }
        return recordID.recordName
        == UserDefaults.standard.string(forKey: currentUserRecordNameKey)
    }
    
    /// Clears the persisted current-user record, e.g. after the account is deleted.
    func clearCurrentUser() {
        UserDefaults.standard.removeObject(forKey: currentUserRecordNameKey)
        invalidateSessionCache()
    }
    
    // MARK: - Sharing
    
    /// Returns the share for a house, creating one when it does not exist yet.
    ///
    /// - Parameter house: The house record whose share should be retrieved or created.
    /// - Returns: The existing or newly created `CKShare`, or `nil` if the operation fails.
    ///
    /// > Important: New shares are created with `publicPermission == .readWrite`, so anyone
    /// > holding the link can join and edit the house.
    func resolveShare(for house: CKRecord) async -> CKShare? {
        if let existing = await fetchShare(for: house) {
            return existing
        }
        
        let share = CKShare(rootRecord: house)
        share[CKShare.SystemFieldKey.title] = house["name"] as? String
        share.publicPermission = .readWrite
        
        do {
            _ = try await privateDB
                .modifyRecords(saving: [house, share], deleting: [])
            return share
        } catch {
            self.errorMessage = UserFacingError.message(for: error, doing: .share)
            return nil
        }
    }
    
    /// The share (invite link) of `houseModel`, creating it the first time.
    ///
    /// The share lets anyone with the link join and edit the house.
    /// - Returns: `nil` when the house can't be read or the share can't be saved (see ``errorMessage``).
    func resolveShare(for houseModel: HouseModel) async -> CKShare? {
        guard let house = await fetchRecord(for: houseModel)
        else {
            return nil
        }
        
        if let existing = await fetchShare(for: house) {
            return existing
        }
        
        let share = CKShare(rootRecord: house)
        share[CKShare.SystemFieldKey.title] = house["name"] as? String
        share.publicPermission = .readWrite
        
        do {
            _ = try await privateDB
                .modifyRecords(saving: [house, share], deleting: [])
            return share
        } catch {
            self.errorMessage = UserFacingError.message(for: error, doing: .share)
            return nil
        }
    }
    
    /// Fetches the share associated with a house.
    ///
    /// The database is selected automatically based on the owner of the house's record zone.
    ///
    /// - Parameter house: The house record whose share should be fetched.
    /// - Returns: The associated `CKShare`, or `nil` if the house has no share or the operation
    ///   fails.
    func fetchShare(for house: CKRecord) async -> CKShare? {
        guard let shareReference = house.share else {
            return nil
        }
        
        let database = house.recordID.zoneID.ownerName == CKCurrentUserDefaultName
        ? privateDB // dono
        : sharedDB // convidado
        
        do {
            return try await database.record(
                for: shareReference.recordID
            ) as? CKShare
        } catch {
            errorMessage = UserFacingError.message(for: error, doing: .share)
            return nil
        }
    }
    
    /// Accepts a CloudKit share invitation.
    ///
    /// - Parameter metadata: The metadata received from the CloudKit share invitation.
    /// - Returns: `true` if the invitation was accepted successfully; otherwise `false`.
    ///
    /// If the operation fails, ``errorMessage`` contains the failure reason.
    @discardableResult
    func acceptShare(metadata: CKShare.Metadata) async -> Bool {
        let operation = CKAcceptSharesOperation(
            shareMetadatas: [metadata]
        )
        
        let accepted: Bool = await withCheckedContinuation { continuation in
            operation.acceptSharesResultBlock = { result in
                switch result {
                case .success:
                    self.invalidateSessionCache()
                    continuation.resume(returning: true)
                    
                case .failure(let error):
                    self.errorMessage = UserFacingError.message(for: error, doing: .share)
                    continuation.resume(returning: false)
                }
            }
            
            container.add(operation)
        }
        
        if accepted {
            rememberPendingJoin(zoneID: metadata.share.recordID.zoneID)
        }
        return accepted
    }
    
    /// Creates the signed-in user's member record inside the current house, copying their profile.
    /// - Returns: `false` when the house or the profile can't be found, or the save fails.
    private func addMyselfToCurrentHouse() async -> Bool {
        var found: HouseModel?
        for _ in 0..<3 where found == nil {
            found = try? await fetchFirst(HouseModel.self)
            if found == nil { try? await Task.sleep(for: .seconds(1)) }
        }
        
        guard let house = found,
              let houseID = house.recordID,
              let profile = await fetchMyUser(),
              let profileID = profile.recordID,
              let ownerName = await fetchCurrentUserRecordID()?.recordName
        else { return false }
        
        // The profile picture is optional: a profile without one must still become a member.
        let profilePictureDuplicate = profile.profilePicture.flatMap { try? duplicateCKAsset($0) }
        
        let member = UserModel(
            name: profile.name,
            profilePicture: profilePictureDuplicate,
            banner: profile.banner,
            tier: .tradicionalI,
            coins: 0,
            house: CKRecord.Reference(recordID: houseID, action: .none),
            couponLimit: profile.couponLimit,
            ownerRecordName: ownerName
        )
        
        guard let saved = await create(
            member,
            id: houseUserRecordID(for: profileID, inHouseZone: houseID.zoneID),
            parent: house.reference(action: .none)
        ) else { return false }
        
        guard await house.appendUsers([saved]) else { return false }
        clearPendingJoin(ifMatching: houseID.zoneID)
        
        // Tells the admin, who can redo the automatic division.
        let memberName = profile.name
        Task { await NotificationManager.shared.notifyNewMember(named: memberName, houseID: houseID) }
        return true
    }
    
    /// Leaves the shared house the user is in, removing their member record first.
    /// - Returns: `false` when there is no shared house to leave.
    /// - Throws: ``CloudKitErrors/currentHouseOwnerCannotLeaveTheHouse`` when the user created the house.
    @discardableResult
    func leaveCurrentHouse() async throws -> Bool {
        guard let house = try? await fetchFirst(HouseModel.self),
              let record = await fetchRecord(for: house),
              let share = await fetchShare(for: record)
        else {
            return false
        }
        
        // O dono não "sai": ele deleta ou para de compartilhar.
        guard share.recordID.zoneID.ownerName != CKCurrentUserDefaultName else {
            errorMessage = UserFacingError.friendly(technical: "Failed to leave house: current user is the owner")
            throw CloudKitErrors<Any>.currentHouseOwnerCannotLeaveTheHouse
        }
        
        // If this user pays for the house's Premium, clear it and tell the others first: after
        // leaving the house can't be written to anymore.
        await PremiumManager.shared.releaseHouseBeforeLeaving(house)
        
        // Removes this user's member record from the house *before* leaving the share, so no
        // ghost member is left behind
        let left = await leaveSharedHouse(in: share.recordID.zoneID)
        if !left { await PremiumManager.shared.leavingFailed() }
        return left
    }
    
    /// Leaves the current house and accepts the invitation to another one.
    /// - Parameter metadata: The invitation of the new house.
    /// - Returns: `false` when leaving or accepting fails.
    @discardableResult
    func switchHouse(to metadata: CKShare.Metadata) async -> Bool {
        do {
            guard try await leaveCurrentHouse() else { return false }
            guard await acceptShare(metadata: metadata) else { return false }
            // Accepting the share only grants access to the house: the member record still has
            // to be created, or the user is in the house without showing up as a member.
            return await addMyselfToCurrentHouse()
        }
        catch {
            print("\(String(describing: errorMessage))")
            return false
        }
    }
    
    /// Creates database subscriptions for private and shared database changes.
    ///
    /// The subscriptions request silent push notifications by enabling
    /// `shouldSendContentAvailable`.
    ///
    /// - Throws: A CloudKit error if either subscription cannot be saved.
    ///
    /// ## Sync fix
    ///
    /// The two saves used to run back to back inside a single throwing body, so the first
    /// failure aborted the second one. That made delivery depend on the order of events:
    /// - The admin needs `private-changes` (guest writes land in the admin's own zone).
    /// - The guest needs `shared-changes` (the admin's division reaches them through the
    ///   shared database), but it was saved *second* and was skipped whenever the private
    ///   save failed first (offline moment, account hiccup, a concurrent call).
    /// - The only call sites were house creation and `joinHouse()`, both wrapped in `try?`,
    ///   so any failure was silent and never retried.
    ///
    /// Now each database is handled independently, subscriptions that already exist on the
    /// server are left alone (the call is idempotent), and the method is also invoked on every
    /// launch from `AppDelegate`, so a subscription that failed once is repaired next time.
    /// The first error is still rethrown after *both* databases were attempted, keeping the
    /// original contract for callers.
    func createSharedSubscription() async throws {
        let sharedSubscription = CKDatabaseSubscription(
            subscriptionID: "shared-changes"
        )
        
        let privateSubscription = CKDatabaseSubscription(
            subscriptionID: "private-changes"
        )
        
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        
        sharedSubscription.notificationInfo = notificationInfo
        privateSubscription.notificationInfo = notificationInfo
        
        // Sync fix: attempt both, independently, and remember only the first failure.
        var firstError: Error?
        
        for (database, subscription) in [
            (privateDB, privateSubscription),
            (sharedDB, sharedSubscription)
        ] {
            do {
                try await saveSubscriptionIfNeeded(subscription, in: database)
            } catch {
                errorMessage = UserFacingError.message(for: error, doing: .save)
                if firstError == nil { firstError = error }
            }
        }
        
        if let firstError { throw firstError }
    }
    
    /// Saves `subscription` only when the database doesn't already hold one with the same ID.
    ///
    /// Sync fix helper for ``createSharedSubscription()``: makes repeated calls (every launch,
    /// every join) cheap and free of "already exists" failures.
    private func saveSubscriptionIfNeeded(
        _ subscription: CKDatabaseSubscription,
        in database: CKDatabase
    ) async throws {
        let existing = try await database.allSubscriptions()
        guard !existing.contains(where: { $0.subscriptionID == subscription.subscriptionID }) else {
            return
        }
        _ = try await database.save(subscription)
    }
    
    /// Saves a share and returns the invitation link CloudKit assigned to it.
    ///
    /// - Parameter share: The share to save.
    /// - Returns: The invitation URL other users can open to join.
    /// - Throws: A CloudKit error if the share cannot be saved, or
    ///   ``CloudKitErrors/missingShareURL`` if CloudKit returns no URL.
    func generateShareLink(share: CKShare) async throws -> URL {
        _ = try await privateDB.modifyRecords(saving: [share], deleting: [])
        
        guard let url = share.url else {
            throw CloudKitErrors<Any>.missingShareURL
        }
        
        return url
    }
    
    /// A `CKAsset` for `data` (for example, a profile picture), written to a temporary file.
    /// - Returns: `nil` when the file can't be written.
    func createAsset(from data: Data) -> CKAsset? {
        //Create a temporary file URL
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let temporaryFileURL = temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        
        do {
            //Write the Data to the temporary URL
            try data.write(to: temporaryFileURL)
            
            //Initialize and return the CKAsset
            return CKAsset(fileURL: temporaryFileURL)
        } catch {
            print("Failed to write data to temporary file: \(error)")
            return nil
        }
    }
    
    /// Saves a collection of records to CloudKit in a single batch operation.
    ///
    /// This method determines the appropriate database (private or shared) based on the provided **zone ID** and executes a **batch save** using `modifyRecords(saving:deleting:)`.
    ///
    /// - Parameters:
    ///   - records: An array of **`CKRecord`** objects to be saved.
    ///   - zoneID: The **`CKRecordZone.ID`** indicating where the records reside.
    ///
    /// - Returns: A **Boolean** value indicating whether the batch operation succeeded (`true`) or failed (`false`).
    ///
    /// - Important: If the operation fails, the error message is stored in **`self.errorMessage`**.
    @discardableResult
    func batchSave(
        records: [CKRecord],
        zoneID: CKRecordZone.ID,
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy = .ifServerRecordUnchanged
    ) async -> Bool {
        let isPrivate = zoneID.ownerName == CKCurrentUserDefaultName
        let database = isPrivate ? privateDB : sharedDB
        do {
            let (saveResults, _) = try await database.modifyRecords(
                saving: records,
                deleting: [],
                savePolicy: savePolicy,
                atomically: true
            )
            // `modifyRecords` only throws for whole-request failures; per-record errors
            // (e.g. serverRecordChanged) come back in the results and used to be ignored.
            var saved: [CKRecord] = []
            var failure: Error?
            for (_, result) in saveResults {
                switch result {
                case .success(let record): saved.append(record)
                case .failure(let error):
                    // In an atomic batch the other records only say `batchRequestFailed`: keep
                    // the record that has the real cause (for example a full iCloud).
                    if failure == nil || failure?.isBatchRequestFailed == true {
                        failure = error
                    }
                }
            }
            if let failure { throw failure }
            RecentWrites.shared.saved(saved)
        
            await HardwareViewModel.notifyDataChanged()
            markDataChanged()
            return true
        } catch {
            ICloudStorageMonitor.shared.report(error, in: database)
            self.errorMessage = UserFacingError.message(for: error, doing: .save)
            return false
        }
    }
    
    /// Saves changes to several models at once, grouped by database (private or shared).
    /// - Returns: `true` when every group was saved.
    @discardableResult
    func batchUpdate<T: CloudKitSyncable>(_ items: [T]) async -> Bool {
        guard !items.isEmpty else { return true }

        let grouped = Dictionary(grouping: items) { item in
            item.recordID?.zoneID.ownerName == CKCurrentUserDefaultName
        }

        var allSucceeded = true

        for (isPrivate, group) in grouped {
            let database = isPrivate ? privateDB : sharedDB
            let recordIDs = group.compactMap { $0.recordID }
            guard !recordIDs.isEmpty else { continue }

            do {
                let fetchResults = try await database.records(for: recordIDs)

                var recordsToSave: [CKRecord] = []
                var savedIDs: Set<CKRecord.ID> = []
                for item in group {
                    guard let recordID = item.recordID,
                          savedIDs.insert(recordID).inserted,
                          let result = fetchResults[recordID],
                          case .success(let record) = result else { continue }
                    item.populate(record: record)
                    recordsToSave.append(record)
                }

                guard !recordsToSave.isEmpty else { continue }

                let (saveResults, _) = try await database.modifyRecords(saving: recordsToSave, deleting: [])
                // Per-record failures don't throw: look for a full iCloud among them.
                ICloudStorageMonitor.shared.report(saveResults: saveResults, in: database)
                RecentWrites.shared.saved(saveResults.values.compactMap { try? $0.get() })
                
                await HardwareViewModel.notifyDataChanged()
                markDataChanged()
            } catch {
                ICloudStorageMonitor.shared.report(error, in: database)
                errorMessage = UserFacingError.message(for: error, doing: .save)
                print("    batchUpdate FAILED (\(T.recordType)): \(error)")
                allSucceeded = false
            }
        }

        return allSucceeded
    }
    
    /// Like ``batchUpdate(_:)``, but tells which records failed and tries again when CloudKit asks
    /// to (busy zone, rate limit, a newer copy on the server).
    ///
    /// Many saves fired at once in the same zone (checking several chores off in a row) get
    /// `zoneBusy` / `requestRateLimited` back. ``batchUpdate(_:)`` and ``update(_:)`` gave up on
    /// the first error, and per-record failures were dropped without a word.
    ///
    /// - Parameters:
    ///   - items: The models to save. Each one is written over the latest server copy.
    ///   - maxAttempts: How many times a retryable failure is sent again.
    /// - Returns: The ids of the models that couldn't be saved (empty when all were). On failure
    ///   ``errorMessage`` says why.
    func batchUpdateRetrying<T: CloudKitSyncable>(_ items: [T], maxAttempts: Int = 4) async -> Set<CKRecord.ID> {
        var remaining = items.filter { $0.recordID != nil }
        var failed: Set<CKRecord.ID> = []
        var attempt = 0
        
        while !remaining.isEmpty, attempt < maxAttempts {
            attempt += 1
            var retry: [T] = []
            var wait: Double = 0
            
            func scheduleRetry(_ item: T, after error: Error) {
                if let delay = Self.retryDelay(for: error) {
                    retry.append(item)
                    wait = max(wait, delay)
                } else if let id = item.recordID {
                    failed.insert(id)
                    errorMessage = UserFacingError.message(for: error, doing: .save)
                }
            }
            
            // CloudKit rejects requests that mix the private and the shared database.
            let grouped = Dictionary(grouping: remaining) { item in
                item.recordID?.zoneID.ownerName == CKCurrentUserDefaultName
            }
            
            for (isPrivate, group) in grouped {
                let database = isPrivate ? privateDB : sharedDB
                var byID: [CKRecord.ID: T] = [:]
                for item in group { if let id = item.recordID { byID[id] = item } }
                
                do {
                    // Written over the latest server copy, so a retry after `serverRecordChanged`
                    // starts from the newer version.
                    let fetched = try await database.records(for: Array(byID.keys))
                    var records: [CKRecord] = []
                    for (id, item) in byID {
                        switch fetched[id] {
                        case .success(let record)?:
                            item.populate(record: record)
                            records.append(record)
                        case .failure(let error)?:
                            scheduleRetry(item, after: error)
                        case nil:
                            failed.insert(id)
                        }
                    }
                    guard !records.isEmpty else { continue }
                    
                    let (results, _) = try await database.modifyRecords(
                        saving: records,
                        deleting: [],
                        savePolicy: .ifServerRecordUnchanged,
                        atomically: false
                    )
                    var saved: [CKRecord] = []
                    for (id, result) in results {
                        switch result {
                        case .success(let record): saved.append(record)
                        case .failure(let error): if let item = byID[id] { scheduleRetry(item, after: error) }
                        }
                    }
                    if !saved.isEmpty {
                        RecentWrites.shared.saved(saved)
                        await HardwareViewModel.notifyDataChanged()
                        markDataChanged()
                    }
                } catch {
                    for item in byID.values { scheduleRetry(item, after: error) }
                }
            }
            
            remaining = retry
            if !remaining.isEmpty, attempt < maxAttempts {
                try? await Task.sleep(for: .seconds(wait))
            }
        }
        
        if !remaining.isEmpty {
            failed.formUnion(remaining.compactMap(\.recordID))
            errorMessage = L10n.tr("O serviço está ocupado agora. Tente novamente em instantes.")
        }
        return failed
    }
    
    // MARK: - Connection check
    
    /// How long ``connectionProblem()`` waits for iCloud before calling the connection too slow.
    static let connectionCheckDeadline: Duration = .seconds(20)
    
    /// Shown when iCloud doesn't answer in time.
    static var slowConnectionMessage: String {
        L10n.tr("Sua conexão está lenta e não conseguimos falar com o iCloud. Verifique sua internet e tente novamente.")
    }
    
    /// Asks CloudKit for something cheap that fails loudly, to tell "nothing there" apart from
    /// "couldn't ask".
    ///
    /// The lookups (``fetchFirst(_:)``, ``fetchAll(_:predicate:)``, ``fetchMyUser()``) turn any
    /// error into an empty result. Offline, that read as "no profile" in the onboarding and as
    /// "no house" (``HouseAccessLostView``) when opening the app.
    ///
    /// - Returns: The message to show, or `nil` when iCloud answered (or failed for a reason that
    ///   isn't the connection or the account).
    func connectionProblem() async -> String? {
        do {
            _ = try await withDeadline(Self.connectionCheckDeadline) { () async throws -> [CKRecordZone] in
                try await self.privateDB.allRecordZones()
            }
            return nil
        } catch is DeadlineExceededError {
            return Self.slowConnectionMessage
        } catch let error as CKError where Self.connectionBlockingCodes.contains(error.code) {
            return UserFacingError.message(for: error, doing: .load)
        } catch let error as URLError {
            return UserFacingError.message(for: error, doing: .load)
        } catch {
            return nil
        }
    }
    
    /// CloudKit failures that mean nothing else will work until the user fixes them.
    private static let connectionBlockingCodes: Set<CKError.Code> = [
        .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited,
        .serverResponseLost, .notAuthenticated, .accountTemporarilyUnavailable
    ]
    
    /// How long to wait before sending a save again, or `nil` when trying again won't help.
    static func retryDelay(for error: Error) -> Double? {
        guard let ckError = error as? CKError else { return nil }
        switch ckError.code {
        case .zoneBusy, .requestRateLimited, .serviceUnavailable, .networkFailure, .serverResponseLost:
            return ckError.retryAfterSeconds ?? 1
        case .serverRecordChanged:
            // Fetched again on the next attempt.
            return 0.2
        default:
            return nil
        }
    }
}

extension CloudKitManager {
    
    // MARK: - Debug / Cleanup
    
    /// Deletes every record owned by the current user by dropping the custom zone that
    /// holds all of them, then recreates the (now empty) zone so the app keeps working.
    ///
    /// Every model created through `⁠ create(_:zoneID:parent:) ⁠` lives in `⁠ houseZoneID ⁠`
    /// by default, so removing that single zone wipes houses, rooms, chores, users and
    /// everything else in one atomic server-side operation — no need to enumerate record
    /// types or paginate queries.
    ///
    /// - Returns: ⁠ true ⁠ when the zone was deleted and recreated successfully.
    @discardableResult
    func deleteAllPrivateRecords() async -> Bool {
        do {
            _ = try await privateDB.deleteRecordZone(withID: houseZoneID)
            didEnsureZone = false
            clearCurrentUser()
            await UserProfileCache.shared.removeAll()
        } catch {
            errorMessage = UserFacingError.message(for: error, doing: .delete)
            return false
        }
        
        // `force` because the zone really is gone and has to be saved again for real.
        return await createZoneIfNeeded(force: true)
    }
    
    /// Leaves every house shared with the current user, across every shared zone.
    ///
    /// > Note: CloudKit doesn't let a participant delete another account's private zone —
    /// > only its owner can do that. Deleting the `⁠ CKShare ⁠` record is the correct
    /// > equivalent available to a participant: it removes every reference this account
    /// > holds into shared houses, without touching the owner's actual data.
    ///
    /// - Returns: ⁠ true ⁠ when every shared house was successfully left.
    @discardableResult
    func leaveAllSharedHouses() async -> Bool {
        let sharedHouses = await fetchAll(HouseModel.self).filter {
            guard let recordID = $0.recordID else { return false }
            return !isOwner(HouseModel.self, recordID: recordID)
        }
        
        var allSucceeded = true
        
        for house in sharedHouses {
            guard let record = await fetchRecord(for: house),
                  let share = await fetchShare(for: record)
            else {
                allSucceeded = false
                continue
            }
            
            do {
                _ = try await sharedDB.deleteRecord(withID: share.recordID)
            } catch {
                errorMessage = UserFacingError.message(for: error, doing: .leave)
                allSucceeded = false
            }
        }
        
        return allSucceeded
    }
    
    /// Deletes everything the current user can reach: every record they own, plus their
    /// participation in every house shared with them.
    ///
    /// > Warning: Destructive, irreversible debug utility. Nothing in the app calls it
    /// > automatically.
    ///
    /// - Returns: ⁠ true ⁠ when both steps succeeded.
    @discardableResult
    func deleteAllRecords() async -> Bool {
        let leftShared = await leaveAllSharedHouses()
        let deletedPrivate = await deleteAllPrivateRecords()
        return leftShared && deletedPrivate
    }
}
