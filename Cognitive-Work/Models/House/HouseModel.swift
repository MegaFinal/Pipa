//
//  HouseModel.swift
//  Cognitive-Work
//

import Foundation
import CloudKit

/// A house stored in CloudKit, acting as the root record every other model hangs off.
///
/// The house is the record that gets shared, so its zone determines which database the
/// related chores, rooms, and users live in.
@Observable
class HouseModel: CloudKitSyncable {

    /// CloudKit record type backing this model.
    static var recordType: String = "HouseModel"

    /// Identifier of the stored record, or `nil` before the house is saved.
    var recordID: CKRecord.ID?

    /// Name shown to the user and used as the share invitation title.
    var name: String

    /// Free-form details about the house.
    var description: String

    /// References to the ``ChoreModel`` records belonging to this house.
    private var choresReference: [CKRecord.Reference]?

    /// References to the ``UserModel`` records that are members of this house.
    private var usersReference: [CKRecord.Reference]?

    /// Reference to this house's ``ShopListModel``. The house has exactly one
    /// shopping list, which is edited in place — this points at it, not at a collection.
    private var shopListReference: CKRecord.Reference?

    /// References to the ``RoomModel`` records belonging to this house.
    private var roomsReference: [CKRecord.Reference]?

    /// Until when the house has Premium, written by the device of the member who subscribed.
    /// See ``PremiumManager``.
    private(set) var premiumExpiresAt: Date? = nil

    /// iCloud record name of the member paying for Premium (``UserModel/ownerRecordName``).
    private(set) var premiumOwnerRecordName: String? = nil

    /// Product ID of the plan paying for Premium (see ``PremiumPlan``), so every member knows
    /// which house size it covers.
    private(set) var premiumProductID: String? = nil
    
    /// The house's chores, fetched from CloudKit.
    var chores: [ChoreModel] {
        get async {
            if let choresReference {
                return await CloudKitManager.shared.fetchRecordsByRecordReference(for: ChoreModel.self, recordReferences: choresReference) ?? []
            }
            return []
        }
    }
    
    /// The house's members, fetched from CloudKit.
    var users: [UserModel] {
        get async {
            if let usersReference {
                return await CloudKitManager.shared.fetchRecordsByRecordReference(for: UserModel.self, recordReferences: usersReference) ?? []
            }
            return []
        }
    }
    
    /// The house's shopping list, `nil` when the house has none, throwing when CloudKit fails
    /// (``shopList`` returns `nil` in both cases).
    func loadShopList() async throws -> ShopListModel? {
        guard let shopListReference else { return nil }
        guard let lists = await CloudKitManager.shared.fetchRecordsByRecordReference(
            for: ShopListModel.self,
            recordReferences: [shopListReference]
        ) else {
            throw CKError(.networkFailure)
        }
        return lists.first
    }
    
    /// The house's shopping list, or `nil` before one has been created.
    var shopList: ShopListModel? {
        get async {
            if let shopListReference {
                return await CloudKitManager.shared.fetchRecordsByRecordReference(for: ShopListModel.self, recordReferences: [shopListReference])?.first
            }
            return nil
        }
    }
    
    /// The house's rooms, fetched from CloudKit.
    var room: [RoomModel] {
        get async {
            if let roomsReference {
                return await CloudKitManager.shared.fetchRecordsByRecordReference(for: RoomModel.self, recordReferences: roomsReference) ?? []
            }
            return []
        }
    }
    
    /// Creates a model from a CloudKit record.
    ///
    /// - Parameter record: The record to decode.
    /// - Returns: `nil` when `name` or `description` is missing or has the wrong type.
    required init?(record: CKRecord) {
        guard
            let name = record["name"] as? String,
            let description = record["description"] as? String
        else {
            return nil
        }

        self.recordID = record.recordID
        self.name = name
        self.description = description
        self.choresReference = record["chores"] as? [CKRecord.Reference]
        self.usersReference = record["users"] as? [CKRecord.Reference]
        self.shopListReference = record["shopList"] as? CKRecord.Reference
        self.roomsReference = record["rooms"] as? [CKRecord.Reference]
        self.premiumExpiresAt = record["premiumExpiresAt"] as? Date
        self.premiumOwnerRecordName = record["premiumOwner"] as? String
        self.premiumProductID = record["premiumProductID"] as? String
    }

    /// Creates a new, unsaved house.
    ///
    /// Relationship parameters are usually filled in after the related records exist.
    ///
    /// - Parameters:
    ///   - name: Name shown to the user.
    ///   - description: Free-form details about the house.
    ///   - chores: Chores already known to belong to this house.
    ///   - users: Members of this house.
    ///   - shopList: The house's shopping list, if already known.
    ///   - rooms: Rooms already known to belong to this house.
    init(
        name: String,
        description: String,
        chores: [CKRecord.Reference]? = nil,
        users: [CKRecord.Reference]? = nil,
        shopList: CKRecord.Reference? = nil,
        rooms: [CKRecord.Reference]? = nil
    ) {
        self.recordID = nil
        self.name = name
        self.description = description
        self.choresReference = chores
        self.usersReference = users
        self.shopListReference = shopList
        self.roomsReference = rooms
    }

    /// Writes this model's values into a CloudKit record.
    ///
    /// - Parameter record: The record to populate.
    ///
    /// > Important: Relationships are always written, so a `nil` collection clears the field on
    /// > the server. This differs from ``ChoreModel``, ``RoomModel``, and ``UserModel``, which
    /// > skip `nil` values and preserve whatever is stored remotely.
    func populate(record: CKRecord) {
        record["name"] = name
        record["description"] = description
        record["chores"] = choresReference
        record["users"] = usersReference
        record["shopList"] = shopListReference
        record["rooms"] = roomsReference
        // The premium fields are left out on purpose: only
        // ``setPremium(expiresAt:ownerRecordName:productID:)`` writes them, so renaming the house with an
        // old copy in memory never erases a subscription another member just saved.
    }
    
    /// Adds `rooms` to the house's room list and saves the house.
    /// - Returns: `false` if CloudKit rejects the save. Rooms not saved yet (no `recordID`) are skipped.
    @discardableResult
    func appendRoom(rooms: [RoomModel]) async -> Bool {
        let newReferences = rooms.compactMap { room -> CKRecord.Reference? in
            guard let recordID = room.recordID else { return nil }
            return CKRecord.Reference(recordID: recordID, action: .none)
        }
        roomsReference = (roomsReference ?? []) + newReferences
        return await CloudKitManager.shared.update(self)
    }
    
    /// Removes the given room's record reference from this house's `rooms` list and saves it.
    ///
    /// - Returns: `true` when the reference was removed (or was already absent), `false` if
    ///   CloudKit rejects the update (see ``CloudKitManager/errorMessage``).
    @discardableResult
    func removeRoom(_ room: RoomModel) async -> Bool {
        guard let recordID = room.recordID else { return true }
        guard let roomsReference, roomsReference.contains(where: { $0.recordID == recordID }) else {
            return true
        }
        self.roomsReference = roomsReference.filter { $0.recordID != recordID }
        return await CloudKitManager.shared.update(self)
    }
    
    /// Appends the given users' record references to this house's `users` list and saves it.
    ///
    /// Unlike ``appendRoom(rooms:)``, this works even if `usersReference` starts as `nil`.
    @discardableResult
    func appendUsers(_ users: [UserModel]) async -> Bool {
        let newReferences = users.compactMap { user -> CKRecord.Reference? in
            guard let recordID = user.recordID else { return nil }
            return CKRecord.Reference(recordID: recordID, action: .none)
        }
        usersReference = (usersReference ?? []) + newReferences
        return await CloudKitManager.shared.update(self)
    }
    
    /// Removes the given user's record reference from this house's `users` list and saves it.
    ///
    /// Used when a member deletes their own profile
    /// Used when a member deletes their own profile.
    /// - Returns: `true` when the reference was removed (or was already absent), `false` if
    ///   CloudKit rejects the update (see ``CloudKitManager/errorMessage``).
    @discardableResult
    func removeUser(_ user: UserModel) async -> Bool {
        guard let recordID = user.recordID else { return true }
        return await removeUser(withID: recordID)
    }
    
    /// Removes a user's reference from this house's `users` list by its record ID and saves it.
    ///
    /// Useful when the user record may already be gone (e.g. undoing an onboarding step).
    @discardableResult
    func removeUser(withID recordID: CKRecord.ID) async -> Bool {
        guard let usersReference, usersReference.contains(where: { $0.recordID == recordID }) else {
            return true
        }
        self.usersReference = usersReference.filter { $0.recordID != recordID }
        return await CloudKitManager.shared.update(self)
    }
    
    /// Removes several rooms' references from this house's `rooms` list in a single save.
    ///
    /// - Returns: `true` when the references were removed (or none were present), `false` if
    ///   CloudKit rejects the update (see ``CloudKitManager/errorMessage``).
    @discardableResult
    func removeRooms(withIDs recordIDs: Set<CKRecord.ID>) async -> Bool {
        guard let roomsReference, roomsReference.contains(where: { recordIDs.contains($0.recordID) }) else {
            return true
        }
        self.roomsReference = roomsReference.filter { !recordIDs.contains($0.recordID) }
        return await CloudKitManager.shared.update(self)
    }
    
    /// Points this house at its shopping list and saves it.
    @discardableResult
    func setShopList(_ list: ShopListModel) async -> Bool {
        guard let recordID = list.recordID else { return false }
        shopListReference = CKRecord.Reference(recordID: recordID, action: .none)
        return await CloudKitManager.shared.update(self)
    }
    
    /// A reference to this house, to store in other records.
    /// - Parameter action: What CloudKit does to the referencing record when the house is deleted.
    /// - Returns: `nil` when the house is not saved yet.
    func reference(action: CKRecord.ReferenceAction) -> CKRecord.Reference? {
        if let recordID {
            return CKRecord.Reference(recordID: recordID, action: action)
        }
        print("House doesn't have a recordID")
        return nil
    }
    
    // MARK: - Authorization
    
    /// Whether the user is the one who created this house.
    func isAdmin() async -> Bool? {
        guard let recordID = self.recordID else { return nil }
        return await CloudKitManager.shared.isOwner(HouseModel.self, recordID: recordID)
    }
    
    // MARK: - Update
    //
    /// Renames the house and/or updates its description, persisting the change to CloudKit.
    ///
    /// Only the house admin (see ``isAdmin()``) may do it.
    ///
    /// - Parameters:
    ///   - name: New name for the house.
    ///   - description: New description for the house.
    ///   - requesterID: `recordID` of the ``UserModel`` asking for the change. Not checked: the
    ///     admin check uses the signed-in iCloud account.
    /// - Returns: `false` when the user is not the admin or CloudKit rejects the save.
    @discardableResult
    func update(name: String, description: String, requesterID: CKRecord.ID) async -> Bool {
        guard await isAdmin() == true else { return false }
        
        self.name = name
        self.description = description
        return await CloudKitManager.shared.update(self)
    }
    
    /// The house's raw CloudKit record, fetched again from the server. `nil` before it is saved.
    func fetchSelfRecord() async -> CKRecord? {
        if let recordID {
            return await CloudKitManager.shared.fetchRecord(for: self)
        }
        return nil
    }

    // MARK: - Premium

    /// Saves who pays for Premium, with which plan and until when. Pass `nil` to remove Premium.
    ///
    /// Writes only these two fields on the latest copy of the record. Any member may call it
    /// (the share is read-write); ``PremiumManager`` only does when this device has the
    /// subscription.
    @discardableResult
    func setPremium(expiresAt: Date?, ownerRecordName: String?, productID: String?) async -> Bool {
        guard let record = await fetchSelfRecord() else { return false }
        record["premiumExpiresAt"] = expiresAt
        record["premiumOwner"] = ownerRecordName
        record["premiumProductID"] = productID
        guard await CloudKitManager.shared.update(record: record) else { return false }
        premiumExpiresAt = expiresAt
        premiumOwnerRecordName = ownerRecordName
        premiumProductID = productID
        return true
    }

    // MARK: - Delete

    /// Deletes this house together with every record still in its CloudKit hierarchy.
    ///
    /// The house is the root of a CKShare record hierarchy (see
    /// ``CloudKitManager/resolveShare(for:)-(HouseModel)``): rooms and users are saved with
    /// `record.parent` pointing at the house, a room's chores with `parent` pointing at that
    /// room, and a chore's checklist items with `parent` pointing at that chore. CloudKit
    /// refuses to delete a hierarchy root while any descendant still references it — that's
    /// the "Record delete would violate validating reference" error — so every descendant has
    /// to be deleted in the *same* batch as the house itself.
    ///
    /// - Returns: `true` when the house and all its descendants were deleted, `false` if the
    ///   recordID is missing or CloudKit rejects the batch (see
    ///   ``CloudKitManager/errorMessage``).
    @discardableResult
    func deleteAllChildren() async -> Bool {
        guard let recordID
        else {
            return false
        }
        
        return await CloudKitManager.shared.deleteChildren(of: recordID)
    }
}
