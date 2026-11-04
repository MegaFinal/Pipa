//
//  UserModel.swift
//  Cognitive-Work
//

import Foundation
import CloudKit

/// A member of a house, including their gamification progress.
class UserModel: CloudKitSyncable, Identifiable, Hashable {
    /// Identifier used before the user is saved (when it has no `recordID`).
    private let localID = UUID().uuidString
    
    /// Identifier for SwiftUI lists: the record name once saved, a local ID before that.
    var id: String {
        recordID?.recordName ?? localID
    }
    
    /// CloudKit record type backing this model.
    static var recordType: String = "UserModel"
    
    /// Every field except ``profilePicture``.
    ///
    /// The avatar is a `CKAsset`, so including it made CloudKit download the full image for
    /// every member of the house on every user query — and there are several of those per
    /// refresh, across both the chores and the shopping list screens. ``UserProfileCache`` fetches
    /// the asset on demand instead, once per user per session, off the main thread.
    ///
    /// A user fetched by record ID (``CloudKitManager/fetchMyHouseUser()``,
    /// ``CloudKitManager/fetchRecordsByRecordReference(for:recordReferences:)``) is unaffected
    /// and still carries the asset. See ``CloudKitSyncable/listDesiredKeys``.
    static let listDesiredKeys: [CKRecord.FieldKey]? = [
        "name", "ownerRecordName", "tier", "coins", "points", "couponLimit",
        "badges", "chores", "availableTime", "coupons", "house",
        "bannerColor", "bannerPattern", "pixKey"
    ]
    
    /// Identifier of the stored record, or `nil` before the user is saved.
    var recordID: CKRecord.ID?
    
    /// The record name of the person's iCloud account. The same person can have more than one
    /// `UserModel` record (a private profile and one inside the house); this value ties them together.
    var ownerRecordName: String
    
    /// Display name shown to other members.
    var name: String
    
    /// Optional avatar image.
    var profilePicture: CKAsset?
    
    /// Color and texture of the banner behind the profile picture.
    var banner: ProfileBanner = .default
    
    /// The user's Pix key, so housemates can pay what they owe. `nil` until it is set.
    var pixKey: String?
    
    /// Rank in the current cycle. Always derived from ``points``; not saved.
    var tier: Tier
    
    /// Legacy coin balance.
    ///
    /// > Important: no longer the source of truth — coins live in ``CoinWalletModel``, which only
    /// > the purchase and payout flows write. This field is still written by every
    /// > ``populate(record:)`` (e.g. each profile edit), so a value read here can be stale.
    /// > It only seeds a wallet the first time one is created.
    var coins: Int
    
    /// Points in the current cycle — an in-memory copy of the person's ``UserScoreModel``.
    ///
    /// > Important: not saved by ``populate(record:)``. Points change only through
    /// > ``ScoreManager`` and ``CycleSettlementService``, which write the ``UserScoreModel``;
    /// > ``HouseDataStore`` copies it here on every load. Decoding a record reads its old `points`
    /// > field (the legacy value, which seeds the score the first time one is created).
    ///
    /// ``tier`` follows it: every change recomputes the rank (see ``Tier/init(points:)``).
    var points: Int {
        didSet { tier = Tier(points: points) }
    }
    
    /// References to the badges the user has earned.
    var badgesReference: [CKRecord.Reference]?
    
    /// References to the chores assigned to the user.
    var choresReference: [CKRecord.Reference]?
    
    /// References to the user's declared availability slots.
    var availableTimeReference: [CKRecord.Reference]?
    
    /// The house the user belongs to.
    var houseReference: CKRecord.Reference?
    
    /// References to the coupons the user currently holds.
    var couponsReference: [CKRecord.Reference]?
    
    /// Maximum number of coupons the user may hold at once.
    var couponLimit: Int
    
    // [newUser] Disabled until we define what tapping it should do.
    // /// When this user's record was created. Used as the "joined the house" date.
    // var joinedAt: Date?
    
    /// Whether this record's name is the same as ``ownerRecordName``. Not used by the app.
    var isTheHouseOwner: Bool {
        return ownerRecordName == id
    }
    /// When this member joined the house. Used for the "entrou na casa" notification.
    /// To verifies when new user joins the house
    var joinedAt: Date?
    
    /// The member's chores, fetched from CloudKit.
    var chores: [ChoreModel] {
        get async {
            if let choresReference {
                return await CloudKitManager.shared.fetchRecordsByRecordReference(for: ChoreModel.self, recordReferences: choresReference) ?? []
            }
            return []
        }
    }
    
    /// The member's free time records, fetched from CloudKit.
    var availableTime: [AvailableTimeModel] {
        get async {
            if let availableTimeReference {
                return await CloudKitManager.shared.fetchRecordsByRecordReference(for: AvailableTimeModel.self, recordReferences: availableTimeReference) ?? []
            }
            return []
        }
    }
    
    /// The member's house, fetched from CloudKit. `nil` if not set or not found.
    var house: HouseModel? {
        get async {
            if let houseReference {
                return await CloudKitManager.shared.fetchRecordsByRecordReference(for: HouseModel.self, recordReferences: [houseReference])?.first
            }
            return nil
        }
    }
    // TODO: badges and coupon
    
    /// Creates a model from a CloudKit record.
    ///
    /// - Parameter record: The record to decode.
    /// - Returns: `nil` when `name`, `coins`, or `couponLimit` is missing.
    ///
    /// `points` is the legacy field (0 when absent, as on records created after scores moved to
    /// ``UserScoreModel``) and ``tier`` is derived from it; missing collections decode as empty or
    /// `nil` rather than failing.
    required init?(record: CKRecord) {
        guard
            let name = record["name"] as? String,
            let coins = record["coins"] as? Int,
            let couponLimit = record["couponLimit"] as? Int,
            let ownerRecordName = record["ownerRecordName"] as? String
        else {
            return nil
        }
        
        self.recordID = record.recordID
        self.name = name
        self.coins = coins
        let points = record["points"] as? Int ?? 0
        self.points = points
        self.couponLimit = couponLimit
        // The rank is derived from the points, not read from the record, so it is right even
        // for records saved before ranks followed the points.
        self.tier = Tier(points: points)
        self.profilePicture = record["profilePicture"] as? CKAsset
        self.banner = ProfileBanner(
            storedColor: record["bannerColor"] as? String,
            storedPattern: record["bannerPattern"] as? String
        )
        self.pixKey = record["pixKey"] as? String
        self.badgesReference = record["badges"] as? [CKRecord.Reference] ?? []
        self.choresReference = record["chores"] as? [CKRecord.Reference] ?? []
        self.availableTimeReference = record["availableTime"] as? [CKRecord.Reference]
        self.couponsReference = record["coupons"] as? [CKRecord.Reference]
        self.houseReference = record["house"] as? CKRecord.Reference
        self.ownerRecordName = ownerRecordName
        self.joinedAt = record.creationDate
    }
    
    /// Creates a new, unsaved user.
    ///
    /// Relationship parameters are usually filled in after the related records exist.
    init(
        name: String,
        profilePicture: CKAsset? = nil,
        banner: ProfileBanner = .default,
        pixKey: String? = nil,
        tier: Tier,
        coins: Int = 0,
        points: Int = 0,
        badges: [CKRecord.Reference]? = nil,
        tasks: [CKRecord.Reference]? = nil,
        availableTime: [CKRecord.Reference]? = nil,
        house: CKRecord.Reference? = nil,
        coupons: [CKRecord.Reference]? = nil,
        couponLimit: Int = 0,
        recordID: CKRecord.ID? = nil,
        ownerRecordName: String
    ) {
        self.recordID = recordID
        self.name = name
        self.profilePicture = profilePicture
        self.banner = banner
        self.pixKey = pixKey
        self.tier = tier
        self.coins = coins
        self.points = points
        self.badgesReference = badges
        self.choresReference = tasks
        self.availableTimeReference = availableTime
        self.houseReference = house
        self.couponsReference = coupons
        self.couponLimit = couponLimit
        self.ownerRecordName = ownerRecordName
    }
    
    /// Writes this model's values into a CloudKit record.
    ///
    /// - Parameter record: The record to populate.
    ///
    /// > Note: `nil` relationships are skipped rather than written, preserving whatever is
    /// > already on the server.
    func populate(record: CKRecord) {
        record["name"] = name
        if let profilePicture {
            record["profilePicture"] = profilePicture
        }
        record["bannerColor"] = banner.color.rawValue
        record["bannerPattern"] = banner.pattern.rawValue
        // Written even when `nil`, so removing the key clears it on the record too.
        record["pixKey"] = pixKey
        record["coins"] = coins
        // `points` and `tier` are deliberately not written: they live in `UserScoreModel`.
        if let badgesReference {
            record["badges"] = badgesReference
        }
        if let choresReference {
            record["chores"] = choresReference
        }
        if let houseReference {
            record["house"] = houseReference
        }
        if let availableTimeReference {
            record["availableTime"] = availableTimeReference
        }
        if let couponsReference {
            record["coupons"] = couponsReference
        }
        record["ownerRecordName"] = ownerRecordName
        record["couponLimit"] = couponLimit
        
    }
    
    /// Saves the member's weekly free time for the next weeks and replaces the old records.
    ///
    /// Each item of `times` is one weekday (Monday first). For every weekday with free time, one
    /// ``AvailableTimeModel`` is created per week, for `weeks` weeks.
    ///
    /// - Parameters:
    ///   - times: The free time of each weekday, Monday first.
    ///   - weeks: How many weeks ahead to create records for.
    /// - Returns: `false` if the member is not saved yet or CloudKit rejects the save.
    @discardableResult
    func setAvailableTimes(_ times: [AvailableTimeModel], forWeeks weeks: Int = 4) async -> Bool {
        guard let recordID else {
            CloudKitManager.shared.errorMessage = "Failed to add availableTime: user missing recordID"
            return false
        }
        
        let previousRefs = availableTimeReference ?? []
        
        let calendar: Calendar = .current
        let userRef = CKRecord.Reference(recordID: recordID, action: .deleteSelf)
        var newRefs: [CKRecord.Reference] = []
        
        var recordsToSave: [CKRecord] = []
        
        let parentReference = houseReference.map {
            CKRecord.Reference(recordID: $0.recordID, action: .none)
        }
        
        for (offset, time) in times.enumerated() {
            
            guard time.capacityMinutes > 0 else { continue }
            
            let baseDay = Date().weekdayInCurrentWeek(offset: offset, calendar: calendar)
            
            for weekOffset in 0..<weeks {
                guard let futureDay = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: baseDay) else {
                    continue
                }
                
                let newID = CKRecord.ID(recordName: UUID().uuidString, zoneID: recordID.zoneID)
                let record = CKRecord(recordType: AvailableTimeModel.recordType, recordID: newID)
                
                let linked = AvailableTimeModel(
                    capacityMinutes: time.capacityMinutes,
                    day: futureDay,
                    user: userRef
                )
                linked.populate(record: record)
                record.parent = parentReference
                
                recordsToSave.append(record)
                newRefs.append(CKRecord.Reference(recordID: newID, action: .none))
            }
        }
        
        // One batch instead of one `create` per slot (up to 7 days × 4 weeks = 28 sequential
        // round-trips), which kept the "Criar uma casa" spinner going for a long time.
        if !recordsToSave.isEmpty {
            await CloudKitManager.shared.createZoneIfNeeded()
            let saveSuccess = await CloudKitManager.shared.batchSave(records: recordsToSave, zoneID: recordID.zoneID)
            guard saveSuccess else { return false }
        }
        
        let originalRefs = availableTimeReference
        self.availableTimeReference = newRefs

        guard await CloudKitManager.shared.update(self) else {
            // Keep the in-memory model in line with the record that was not updated, so a retry
            // deletes the right "previous" slots. The slots saved above stay: unreferenced they
            // are harmless, whereas deleting them after an ambiguous failure could leave the
            // profile pointing at records that no longer exist.
            self.availableTimeReference = originalRefs
            return false
        }
        
        let previousIDs = previousRefs.map(\.recordID)
        if !previousIDs.isEmpty {
            await CloudKitManager.shared.delete(recordIDs: previousIDs, zoneID: recordID.zoneID)
        }
        
        return true
    }
    
    /// Saves one free time value as the member's free time (see ``setAvailableTimes(_:forWeeks:)``).
    @discardableResult
    func setAvailableTime(capacityMinutes: Int, day: Date) async -> Bool {
        await setAvailableTimes([
            AvailableTimeModel(capacityMinutes: capacityMinutes, day: day)
        ])
    }
    
    /// Two users are equal when they point to the same record (or are the same object, before saving).
    static func == (lhs: UserModel, rhs: UserModel) -> Bool {
        // compare both records
        if let l = lhs.recordID, let r = rhs.recordID { return l == r }
        // if they don't have records, compare memory space
        return lhs === rhs
    }
    
    /// Hashes the record ID (or the object itself, before saving).
    func hash(into hasher: inout Hasher) {
        if let recordID {
            hasher.combine(recordID)
        } else {
            hasher.combine(ObjectIdentifier(self))
        }
    }
}
