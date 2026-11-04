//
//  GenericExtension.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 13/08/26.
//

import CloudKit

/// Generic CRUD operations shared by every ``CloudKitSyncable`` model.
///
/// Each method picks the private or shared database automatically from the owner of the
/// record's zone. Failures return `nil`, `false`, or an empty array and set
/// ``CloudKitManager/errorMessage``.
extension CloudKitManager {
    
    // MARK: - Create
    
    /// Creates a new record for any `CloudKitSyncable` model.
    ///
    /// - Parameters:
    ///   - item: The model to persist.
    ///   - zoneID: Zone to save into. Defaults to the current user's private house zone. Pass a
    ///     shared zone's ID (e.g. `room.recordID.zoneID`) to create the record directly inside a
    ///     house you don't own.
    ///   - parent: Optional parent reference for nested records (e.g. a chore whose parent is
    ///     its room).
    /// - Returns: A copy of `item` with `recordID` set, or `nil` on failure.
    @discardableResult
    func create<T: CloudKitSyncable>(
        _ item: T,
        id: CKRecord.ID? = nil,
        zoneID: CKRecordZone.ID? = nil,
        parent: CKRecord.Reference? = nil
    ) async -> T? {
        await createZoneIfNeeded()
        let zone = zoneID ?? houseZoneID
        let recordID = id ?? CKRecord.ID(recordName: UUID().uuidString, zoneID: zone)
        
        let record = CKRecord(
            recordType: T.recordType,
            recordID: recordID
        )
        
        item.populate(record: record)
        if let parent {
            record.parent = parent
        }
        
        let database = recordID.zoneID.ownerName == CKCurrentUserDefaultName ? privateDB : sharedDB
        
        do {
            _ = try await database.save(record)
            var saved = item
            saved.recordID = recordID
            invalidateSessionCacheIfNeeded(for: T.self)
            
            await HardwareViewModel.notifyDataChanged()
            markDataChanged()
            return saved
        } catch {
            errorMessage = UserFacingError.message(for: error, doing: .create)
            return nil
        }
    }
    
    // MARK: - Fetch
    
    /// Fetches every record of `type` visible to the current user: private records first, then
    /// everything in shared zones.
    ///
    /// - Parameters:
    ///   - type: The model type to fetch.
    ///   - predicate: Filter applied to the query. Defaults to matching every record.
    /// - Returns: Owned items followed by shared items. Empty when nothing matches or the query
    ///   fails.
    func fetchAll<T: CloudKitSyncable>(
        _ type: T.Type,
        predicate: NSPredicate = NSPredicate(value: true)
    ) async -> [T] {
        async let owned = fetchPrivate(type, predicate: predicate)
        async let shared = fetchShared(type, predicate: predicate)
        let (ownedItems, sharedItems) = await (owned, shared)
        return ownedItems + sharedItems
    }
    
    /// Fetches the raw `CKRecord` backing a model, needed for sharing operations.
    ///
    /// - Parameter item: The model whose record should be fetched. Must already have a
    ///   `recordID`.
    /// - Returns: The matching `CKRecord`, or `nil` if the item was never saved or the fetch
    ///   fails.
    func fetchRecord<T: CloudKitSyncable>(for item: T) async -> CKRecord? {
        guard let recordID = item.recordID else {
            errorMessage = UserFacingError.friendly(technical: "Failed to fetch \(T.recordType): missing recordID")
            return nil
        }
        
        let database = recordID.zoneID.ownerName == CKCurrentUserDefaultName ? privateDB : sharedDB
        
        do {
            return try await database.record(for: recordID)
        } catch {
            errorMessage = UserFacingError.message(for: error, doing: .load)
            return nil
        }
    }
    
    /// Fetches multiple records by their references using batch requests.
    ///
    /// - Parameters:
    ///   - type: The `CloudKitSyncable` model type to instantiate (e.g., `UserModel.self`).
    ///   - recordReferences: An array of references pointing to the records to fetch.
    /// - Returns: An array of populated models.
    func fetchRecordsByRecordReference<T: CloudKitSyncable>(for type: T.Type, recordReferences: [CKRecord.Reference]) async -> [T]? {
        guard !recordReferences.isEmpty else { return [] }
        
        var privateIDs: [CKRecord.ID] = []
        var sharedIDs: [CKRecord.ID] = []
        
        // Group IDs by their target database
        // CloudKit rejects batch operations that mix private and shared zone IDs.
        for reference in recordReferences {
            if reference.recordID.zoneID.ownerName == CKCurrentUserDefaultName {
                privateIDs.append(reference.recordID)
            } else {
                sharedIDs.append(reference.recordID)
            }
        }
        
        var fetchedRecords: [CKRecord] = []
        
        do {
            // Batch fetch from the Private Database
            if !privateIDs.isEmpty {
                let result = try await privateDB.records(for: privateIDs)
                fetchedRecords.append(contentsOf: result.values.compactMap { try? $0.get() })
            }
            // Batch fetch from the Shared Database
            if !sharedIDs.isEmpty {
                let result = try await sharedDB.records(for: sharedIDs)
                fetchedRecords.append(contentsOf: result.values.compactMap { try? $0.get() })
            }
        } catch {
            errorMessage = UserFacingError.message(for: error, doing: .load)
            return nil
        }
        
        return fetchedRecords.compactMap { T.init(record: $0) }
    }
    
    /// Fetches the first available record of `type`, searching private records before shared
    /// ones.
    ///
    /// - Parameter type: The model type to fetch.
    /// - Returns: The first matching model.
    /// - Throws: ``CloudKitErrors/notFound(_:)`` when no record of that type exists.
    func fetchFirst<T: CloudKitSyncable>(_ type: T.Type) async throws -> T {
        if let first = await fetchPrivate(type, predicate: NSPredicate(value: true)).first {
            return first
        }
        
        if let first = await fetchShared(type, predicate: NSPredicate(value: true)).first {
            return first
        }
        
        throw CloudKitErrors.notFound(T.recordType)
    }
    
    /// Fetches every ``UserModel`` record that belongs to a house, instead of every user
    /// record visible to the current account.
    ///
    /// Onboarding can leave more than one `UserModel` record behind for the same person (the
    /// profile record created before a house exists, plus the copy saved as a child of the
    /// house once one is). An unfiltered ``fetchAll(_:predicate:)`` returns both, so any screen
    /// listing members should go through this instead.
    ///
    /// - Parameter house: The house whose members to fetch. Defaults to the current house
    ///   (via ``fetchFirst(_:)``) when omitted.
    /// - Returns: The users whose `house` reference points at that house. Empty when no house
    ///   is resolved or none match.
    func fetchHouseUsers(of house: HouseModel? = nil) async -> [UserModel] {
        let resolvedHouse: HouseModel?
        if let house {
            resolvedHouse = house
        } else {
            resolvedHouse = try? await currentHouse()
        }
        
        guard let houseID = resolvedHouse?.recordID else { return [] }
        
        let reference = CKRecord.Reference(recordID: houseID, action: .none)
        let predicate = NSPredicate(format: "house == %@", reference)
        let users = await fetchAll(UserModel.self, predicate: predicate)
        
        return deduplicatedByOwner(users)
    }
    
    /// Every `UserModel` record of the house, without merging the ones of the same person
    /// (``fetchHouseUsers(of:)`` keeps one per `ownerRecordName`). Shopping items may reference
    /// any of them, so ``DebtCalculator`` needs all of them to know who each reference is.
    func fetchHouseUserRecords() async -> [UserModel] {
        guard let houseID = (try? await currentHouse())?.recordID else { return [] }
        
        let reference = CKRecord.Reference(recordID: houseID, action: .none)
        let predicate = NSPredicate(format: "house == %@", reference)
        return await fetchAll(UserModel.self, predicate: predicate)
    }
    
    /// Deduplicates users who might have more than one `UserModel` record sharing the same
    /// `ownerRecordName`.
    func deduplicatedByOwner(_ users: [UserModel]) -> [UserModel] {
        var bestByOwner: [String: UserModel] = [:]
        
        for user in users {
            let key = user.ownerRecordName
            guard let existing = bestByOwner[key] else {
                bestByOwner[key] = user
                continue
            }
            if preferredUser(user, over: existing) {
                bestByOwner[key] = user
            }
        }
        
        // Stable output order too: `Dictionary.values` has no defined order, and callers such as
        // the scheduler iterate it.
        return bestByOwner.values.sorted {
            ($0.recordID?.recordName ?? "") < ($1.recordID?.recordName ?? "")
        }
    }
    
    /// Whether `candidate` should replace `current` as the record representing their shared
    /// owner. See ``deduplicatedByOwner(_:)`` for the ordering and why it has to be total.
    private func preferredUser(_ candidate: UserModel, over current: UserModel) -> Bool {
        let candidateHasHouse = candidate.houseReference != nil
        let currentHasHouse = current.houseReference != nil
        if candidateHasHouse != currentHasHouse { return candidateHasHouse }
        
        let candidateChores = candidate.choresReference?.count ?? 0
        let currentChores = current.choresReference?.count ?? 0
        if candidateChores != currentChores { return candidateChores > currentChores }
        
        return (candidate.recordID?.recordName ?? "") < (current.recordID?.recordName ?? "")
    }
    
    /// Reads every record of `type` stored in one zone, without using `CKQuery`.
    ///
    /// - Parameters:
    ///   - type: The model type to decode.
    ///   - zoneID: The zone to scan. The database is picked from the zone's owner.
    /// - Returns: Every decodable record of that type, or `[]` when the scan fails.
    func fetchZoneRecords<T: CloudKitSyncable>(
        _ type: T.Type,
        inZone zoneID: CKRecordZone.ID
    ) async -> [T] {
        let database = zoneID.ownerName == CKCurrentUserDefaultName ? privateDB : sharedDB
        var items: [T] = []
        var token: CKServerChangeToken?
        
        repeat {
            do {
                let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
                
                for (_, result) in changes.modificationResultsByID {
                    guard let record = try? result.get().record,
                          record.recordType == T.recordType,
                          let item = T(record: record)
                    else { continue }
                    items.append(item)
                }
                
                token = changes.moreComing ? changes.changeToken : nil
            } catch {
                errorMessage = UserFacingError.message(for: error, doing: .load)
                return []
            }
        } while token != nil
        
        return items
    }
    
    /// Queries the current user's own house zone.
    func fetchPrivate<T: CloudKitSyncable>(
        _ type: T.Type,
        predicate: NSPredicate,
        desiredKeys: DesiredKeys = .list
    ) async -> [T] {
        do {
            return try await fetchPrivateOrThrow(type, predicate: predicate, desiredKeys: desiredKeys)
        } catch {
            errorMessage = UserFacingError.message(for: error, doing: .load)
            return []
        }
    }
    
    /// Queries every zone shared with the current user and merges the results.
    func fetchShared<T: CloudKitSyncable>(
        _ type: T.Type,
        predicate: NSPredicate,
        desiredKeys: DesiredKeys = .list
    ) async -> [T] {
        do {
            return try await fetchSharedOrThrow(type, predicate: predicate, desiredKeys: desiredKeys)
        } catch {
            errorMessage = UserFacingError.message(for: error, doing: .share)
            return []
        }
    }
    
    // MARK: - Strict fetches
    
    /// Like ``fetchAll(_:predicate:)``, but throws when CloudKit fails.
    func fetchAllOrThrow<T: CloudKitSyncable>(
        _ type: T.Type,
        predicate: NSPredicate = NSPredicate(value: true)
    ) async throws -> [T] {
        async let owned = fetchPrivateOrThrow(type, predicate: predicate, desiredKeys: .list)
        async let shared = fetchSharedOrThrow(type, predicate: predicate, desiredKeys: .list)
        return try await owned + shared
    }
    
    /// Like ``fetchHouseUserRecords()``, but throws when CloudKit fails.
    func fetchHouseUserRecordsOrThrow() async throws -> [UserModel] {
        guard let houseID = try await currentHouse()?.recordID else { return [] }
        
        let reference = CKRecord.Reference(recordID: houseID, action: .none)
        let predicate = NSPredicate(format: "house == %@", reference)
        return try await fetchAllOrThrow(UserModel.self, predicate: predicate)
    }
    
    /// Every `T` in the private database that matches `predicate`. Throws on failure.
    private func fetchPrivateOrThrow<T: CloudKitSyncable>(
        _ type: T.Type,
        predicate: NSPredicate,
        desiredKeys: DesiredKeys
    ) async throws -> [T] {
        let query = CKQuery(recordType: T.recordType, predicate: predicate)
        return try await allRecords(
            matching: query,
            in: privateDB,
            zoneID: houseZoneID,
            desiredKeys: desiredKeys.resolve(for: T.self)
        ).compactMap(T.init(record:))
    }
    
    /// Every `T` in every shared zone that matches `predicate`. Throws on failure.
    private func fetchSharedOrThrow<T: CloudKitSyncable>(
        _ type: T.Type,
        predicate: NSPredicate,
        desiredKeys: DesiredKeys
    ) async throws -> [T] {
        let zones = try await sharedZonesOrThrow()
        guard !zones.isEmpty else { return [] }
        
        return try await withThrowingTaskGroup(of: [T].self) { group in
            for zone in zones {
                group.addTask {
                    let query = CKQuery(recordType: T.recordType, predicate: predicate)
                    return try await self.allRecords(
                        matching: query,
                        in: self.sharedDB,
                        zoneID: zone.zoneID,
                        desiredKeys: desiredKeys.resolve(for: T.self)
                    ).compactMap(T.init(record:))
                }
            }
            var all: [T] = []
            for try await items in group { all.append(contentsOf: items) }
            return all
        }
    }
    
    /// Every record that matches `query` in `zoneID`, reading all pages of results.
    private func allRecords(
        matching query: CKQuery,
        in database: CKDatabase,
        zoneID: CKRecordZone.ID,
        desiredKeys: [CKRecord.FieldKey]?
    ) async throws -> [CKRecord] {
        let firstPage = try await database.records(
            matching: query,
            inZoneWith: zoneID,
            desiredKeys: desiredKeys
        )
        var records = firstPage.matchResults.compactMap { try? $0.1.get() }
        var cursor = firstPage.queryCursor
        
        while let nextPage = cursor {
            let page = try await database.records(continuingMatchFrom: nextPage, desiredKeys: desiredKeys)
            records.append(contentsOf: page.matchResults.compactMap { try? $0.1.get() })
            cursor = page.queryCursor
        }
        
        return records
    }
    
    /// Clears the session cache when the record type that was just written is one the cache
    /// holds.
    func invalidateSessionCacheIfNeeded<T: CloudKitSyncable>(for type: T.Type) {
        guard T.recordType == HouseModel.recordType || T.recordType == UserModel.recordType
        else { return }
        invalidateSessionCache()
    }
    
    // MARK: - Update & Delete
    
    /// Re-saves every field of an existing model.
    ///
    /// Fetches the current `CKRecord` first, overwrites it with `item`'s current values, then
    /// saves.
    ///
    /// - Parameter item: The model to update. Must already have a `recordID`.
    /// - Returns: `true` on success, otherwise `false`.
    @discardableResult
    func update<T: CloudKitSyncable>(_ item: T) async -> Bool {
        guard let recordID = item.recordID else {
            errorMessage = UserFacingError.friendly(technical: "Failed to update \(T.recordType): missing recordID")
            return false
        }
        
        let database = recordID.zoneID.ownerName == CKCurrentUserDefaultName ? privateDB : sharedDB
        
        do {
            let record = try await database.record(for: recordID)
            item.populate(record: record)
            _ = try await database.save(record)
            
            await HardwareViewModel.notifyDataChanged()
            markDataChanged()
            return true
        } catch {
            errorMessage = UserFacingError.message(for: error, doing: .save)
            return false
        }
    }
    
    /// Saves a raw record, in the private or shared database depending on its zone.
    /// - Returns: `false` when the save fails (see ``errorMessage``).
    func update(record: CKRecord) async -> Bool {
        let database = record.recordID.zoneID.ownerName == CKCurrentUserDefaultName ? privateDB : sharedDB
        
        do {
            _ = try await database.save(record)
            
            await HardwareViewModel.notifyDataChanged()
            markDataChanged()
            return true
        } catch {
            errorMessage = UserFacingError.message(for: error, doing: .save)
            return false
        }
    }
    
    /// Deletes the record backing a model.
    ///
    /// - Parameter item: The model to delete. Must already have a `recordID`.
    /// - Returns: `true` on success, otherwise `false`.
    ///
    /// > Important: Child records are not removed unless CloudKit's parent hierarchy cascades
    /// > the deletion.
    @discardableResult
    func delete<T: CloudKitSyncable>(_ item: T) async -> Bool {
        guard let recordID = item.recordID else {
            errorMessage = UserFacingError.friendly(technical: "Failed to delete \(T.recordType): missing recordID")
            return false
        }
        
        let database = recordID.zoneID.ownerName == CKCurrentUserDefaultName ? privateDB : sharedDB
        
        do {
            _ = try await database.deleteRecord(withID: recordID)
            invalidateSessionCacheIfNeeded(for: T.self)
            
            await HardwareViewModel.notifyDataChanged()
            markDataChanged()
            return true
        } catch {
            errorMessage = UserFacingError.message(for: error, doing: .delete)
            return false
        }
    }
    
    /// Deletes the record `recordID` of type `T`.
    /// - Returns: `false` when the delete fails (see ``errorMessage``).
    @discardableResult
    func delete<T: CloudKitSyncable>(_ type: T.Type, recordID: CKRecord.ID) async -> Bool {
        let database = recordID.zoneID.ownerName == CKCurrentUserDefaultName ? privateDB : sharedDB
        
        do {
            _ = try await database.deleteRecord(withID: recordID)
            
            await HardwareViewModel.notifyDataChanged()
            markDataChanged()
            return true
        } catch {
            errorMessage = UserFacingError.message(for: error, doing: .delete)
            return false
        }
    }
    
    /// Deletes several records in a single atomic batch.
    ///
    /// > Warning: Batching a parent together with its children does **not** make the parent
    /// > deletable. CloudKit checks each delete against the records currently on the server,
    /// > not against the state the batch would leave behind, so a parent in the same batch as
    /// > its children is still rejected with "Record delete would violate validating reference".
    /// > Only pass records that are safe to remove at the same moment — see
    /// > ``deleteChildren(of:includingSelf:)``, which calls this once per hierarchy level.
    ///
    /// - Parameters:
    ///   - recordIDs: Every record to delete. Does nothing and returns `true` when empty.
    ///   - zoneID: Zone the records live in, used to pick the private or shared database.
    /// - Returns: `true` on success, otherwise `false` with ``errorMessage`` set.
    @discardableResult
    func delete(recordIDs: [CKRecord.ID], zoneID: CKRecordZone.ID) async -> Bool {
        guard !recordIDs.isEmpty else { return true }
        
        let database = zoneID.ownerName == CKCurrentUserDefaultName ? privateDB : sharedDB
        
        do {
            _ = try await database.modifyRecords(saving: [], deleting: recordIDs)
            
            await HardwareViewModel.notifyDataChanged()
            markDataChanged()
            return true
        } catch {
            errorMessage = UserFacingError.message(for: error, doing: .delete)
            return false
        }
    }
    
    // MARK: - Hierarchy Delete
    
    /// Deletes every record that hangs off `recordID` through CloudKit's `parent` hierarchy.
    ///
    /// Works at any depth and without knowing the record types involved: a house's rooms, those
    /// rooms' chores, and those chores' checklist items all go in one call.
    ///
    /// Deletion runs from the deepest level upwards, one operation per level. CloudKit treats
    /// `CKRecord/parent` as a *validating* reference: a record that is somebody's parent cannot
    /// be deleted while that child still exists on the server — and putting both in the same
    /// batch does not help, because each delete is checked against the server's current state.
    /// So the leaves have to actually be gone before their parent is attempted.
    ///
    /// - Parameters:
    ///   - recordID: The parent whose descendants should be removed.
    ///   - includingSelf: Pass `true` to delete `recordID` itself once its subtree is empty.
    /// - Returns: `true` on success, otherwise `false` with ``errorMessage`` set.
    ///
    /// > Important: Each level is one atomic batch, so a single level is limited to roughly 400
    /// > records — the CloudKit ceiling for one modify operation.
    @discardableResult
    func deleteChildren(of recordID: CKRecord.ID, includingSelf: Bool = false) async -> Bool {
        guard let levels = await fetchDescendantLevels(of: recordID) else { return false }
        
        // Deepest level first: a parent is only deletable once its children are actually gone.
        for level in levels.reversed() {
            guard await delete(recordIDs: level, zoneID: recordID.zoneID) else {
                return false
            }
        }
        
        guard includingSelf else { return true }
        
        return await delete(recordIDs: [recordID], zoneID: recordID.zoneID)
    }
    
    /// Deletes every descendant of a record, and optionally the record itself.
    ///
    /// See ``deleteChildren(of:includingSelf:)-(CKRecord.ID,_)``.
    @discardableResult
    func deleteChildren(of record: CKRecord, includingSelf: Bool = false) async -> Bool {
        await deleteChildren(of: record.recordID, includingSelf: includingSelf)
    }
    
    /// Finds every descendant of a record by rebuilding its zone's `parent` hierarchy locally.
    ///
    /// CloudKit has no "fetch my children" query — `CKQuery` needs one concrete record type per
    /// query, and children can be of any type — so this reads the zone once and walks the tree
    /// in memory instead.
    ///
    /// - Parameter recordID: The root whose descendants should be found.
    /// - Returns: One entry per level — index 0 holds the direct children, index 1 their own
    ///   children, and so on — or `nil` when the zone scan fails. Deleting has to walk this
    ///   back to front, see ``deleteChildren(of:includingSelf:)``.
    func fetchDescendantLevels(of recordID: CKRecord.ID) async -> [[CKRecord.ID]]? {
        let zoneID = recordID.zoneID
        let database = zoneID.ownerName == CKCurrentUserDefaultName ? privateDB : sharedDB
        
        var childrenByParent: [CKRecord.ID: [CKRecord.ID]] = [:]
        var token: CKServerChangeToken?
        
        repeat {
            do {
                let changes = try await database.recordZoneChanges(
                    inZoneWith: zoneID,
                    since: token
                )
                
                for (id, result) in changes.modificationResultsByID {
                    guard
                        let record = try? result.get().record,
                        let parentID = record.parent?.recordID
                    else {
                        continue
                    }
                    
                    childrenByParent[parentID, default: []].append(id)
                }
                
                token = changes.moreComing ? changes.changeToken : nil
            } catch {
                errorMessage = UserFacingError.message(for: error, doing: .load)
                return nil
            }
        } while token != nil
        
        var levels: [[CKRecord.ID]] = []
        var visited: Set<CKRecord.ID> = [recordID]
        var current = childrenByParent[recordID] ?? []
        
        while !current.isEmpty {
            let level = current.filter { visited.insert($0).inserted }
            guard !level.isEmpty else { break }
            
            levels.append(level)
            current = level.flatMap { childrenByParent[$0] ?? [] }
        }
        
        return levels
    }
    
    /// Lists every record in the zone that still points at `recordID`, and through which field.
    ///
    /// Diagnostic for "Record delete would violate validating reference": CloudKit names the
    /// blocking record's ID but not its type, nor which field holds the reference. Feed it the
    /// ID that refused to delete and print the result to find out what is holding it.
    ///
    /// - Parameter recordID: The record that CloudKit refuses to delete.
    /// - Returns: One line per reference found, or `nil` when the zone scan fails.
    func blockingReferences(to recordID: CKRecord.ID) async -> [String]? {
        let zoneID = recordID.zoneID
        let database = zoneID.ownerName == CKCurrentUserDefaultName ? privateDB : sharedDB
        
        var findings: [String] = []
        var token: CKServerChangeToken?
        
        repeat {
            do {
                let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
                
                for (id, result) in changes.modificationResultsByID {
                    guard let record = try? result.get().record, id != recordID else { continue }
                    
                    let origin = "\(record.recordType)/\(id.recordName)"
                    
                    if record.parent?.recordID == recordID {
                        findings.append("\(origin) — parent")
                    }
                    
                    for key in record.allKeys() {
                        switch record[key] {
                        case let reference as CKRecord.Reference where reference.recordID == recordID:
                            findings.append("\(origin) — field '\(key)' (\(describe(reference.action)))")
                            
                        case let references as [CKRecord.Reference]:
                            for reference in references where reference.recordID == recordID {
                                findings.append("\(origin) — field '\(key)' (\(describe(reference.action)))")
                            }
                            
                        default:
                            continue
                        }
                    }
                }
                
                token = changes.moreComing ? changes.changeToken : nil
            } catch {
                errorMessage = UserFacingError.message(for: error, doing: .load)
                return nil
            }
        } while token != nil
        
        return findings
    }
    
    /// A readable name of a reference action, for logs.
    private func describe(_ action: CKRecord.ReferenceAction) -> String {
        switch action {
        case .none: return "action: none"
        case .deleteSelf: return "action: deleteSelf"
        default: return "action: validate/unknown(\(action.rawValue))"
        }
    }
    
    /// Whether the signed-in user owns the zone of `recordID` (for a house: whether they are its admin).
    func isOwner<T: CloudKitSyncable>(_ type: T.Type, recordID: CKRecord.ID) -> Bool {
        return recordID.zoneID.ownerName == CKCurrentUserDefaultName ? true : false
    }
}

/// Which fields a query should transfer.
enum DesiredKeys {
    /// The model's ``CloudKitSyncable/listDesiredKeys``.
    case list
    /// Every field on the record.
    case all
    
    /// The field names to request for `type`, or `nil` for every field.
    func resolve<T: CloudKitSyncable>(for type: T.Type) -> [CKRecord.FieldKey]? {
        switch self {
        case .list: return T.listDesiredKeys
        case .all: return nil
        }
    }
}
