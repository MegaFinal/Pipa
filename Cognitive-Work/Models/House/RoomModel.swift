//
//  RoomModel.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 12/08/26.
//

import Foundation
import CloudKit

/// A room inside a house, grouping the chores that happen there.
struct RoomModel: CloudKitSyncable, Identifiable, Hashable {
    /// Local identifier for SwiftUI lists.
    var id = UUID()
    
    /// CloudKit record type backing this model.
    static var recordType: String = "RoomModel"
    
    /// Identifier of the stored record, or `nil` before the room is saved.
    var recordID: CKRecord.ID?
    
    /// Color used to identify the room in the UI.
    var color: RoomColor
    
    /// Name shown to the user.
    var name: String
    
    /// SF Symbol name of the room's icon.
    var symbol: String
    
    /// References to the ``ChoreModel`` records that belong to this room.
    private var relatedChoresReference: [CKRecord.Reference]?
    
    /// The house this room belongs to.
    var houseReference: CKRecord.Reference?
    
    /// The room type this room was created from during onboarding (e.g. `"Quarto"`).
    var kind: String?
    
    /// Texture picked for a custom room. Default room types ignore it and use their own
    /// (see ``texturePattern``); `nil` uses ``RoomTexturePattern/fallback``.
    var pattern: RoomTexturePattern?
    
    /// Whether the color or symbol stored in CloudKit differs from ``color``/``symbol`` — a
    /// value from an older palette, or a default room still carrying its old look — so the
    /// record should be re-saved. See ``migrateStoredColorsIfNeeded(_:)``.
    private(set) var needsColorMigration = false
    
    /// The room's chores, fetched from CloudKit.
    var relatedChores: [ChoreModel] {
        get async {
            guard let relatedChoresReference, !relatedChoresReference.isEmpty else {
                return []
            }
            return await CloudKitManager.shared.fetchRecordsByRecordReference(for: ChoreModel.self, recordReferences: relatedChoresReference) ?? []
        }
    }
    
    /// The house this room belongs to, fetched from CloudKit. `nil` if not set or not found.
    var house: HouseModel? {
        get async {
            if let houseReference {
                return await CloudKitManager.shared.fetchRecordsByRecordReference(for: HouseModel.self, recordReferences: [houseReference])?.first
            }
            return nil
        }
    }
        
    /// Creates a model from a CloudKit record.
    ///
    /// - Parameter record: The record to decode.
    /// - Returns: `nil` only when `name` is missing.
    init?(record: CKRecord) {
        guard let name = record["name"] as? String else {
            return nil
        }
        
        let kind = record["kind"] as? String
        let storedColor = record["roomColor"] as? String
        let storedSymbol = record["symbol"] as? String
        let defaultRoom = DefaultRoomsOnboarding(kind: kind, name: name)
        
        let color = defaultRoom?.color
            ?? RoomColor(storedValue: storedColor)
            ?? .blue
        let symbol = defaultRoom?.symbol ?? storedSymbol ?? "house"
        
        self.recordID = record.recordID
        self.name = name
        self.symbol = symbol
        self.relatedChoresReference = record["relatedChores"] as? [CKRecord.Reference]
        self.houseReference = record["house"] as? CKRecord.Reference
        self.kind = kind
        self.pattern = (record["pattern"] as? String).flatMap(RoomTexturePattern.init(rawValue:))
        self.color = color
        self.needsColorMigration = storedColor != color.rawValue || storedSymbol != symbol
    }
    
    /// Creates a new, unsaved room.
    ///
    ///   - name: Name shown to the user.
    ///   - symbol: SF Symbol name of the room's icon.
    ///   - relatedChores: Chores already known to belong to this room.
    ///   - house: The owning house.
    ///   - color: Color used to identify the room.
    ///   - kind: The default room type it was created from, if any.
    ///   - pattern: Texture for a custom room.
    init(
        name: String,
        symbol: String,
        relatedChores: [CKRecord.Reference]? = nil,
        house: CKRecord.Reference? = nil,
        color: RoomColor,
        kind: String? = nil,
        pattern: RoomTexturePattern? = nil
    ) {
        self.recordID = nil
        self.name = name
        self.symbol = symbol
        self.relatedChoresReference = relatedChores
        self.houseReference = house
        self.color = color
        self.kind = kind
        self.pattern = pattern
    }
    
    /// Writes this model's values into a CloudKit record.
    ///
    /// - Parameter record: The record to populate.
    ///
    /// > Note: `nil` relationships are skipped rather than written, preserving whatever is
    /// > already on the server.
    func populate(record: CKRecord) {
        record["name"] = name
        record["symbol"] = symbol
        if let relatedChoresReference {
            record["relatedChores"] = relatedChoresReference
        }
        if let houseReference {
            record["house"] = houseReference
        }
        record["roomColor"] = color.rawValue
        if let kind {
            record["kind"] = kind
        }
        if let pattern {
            record["pattern"] = pattern.rawValue
        }
    }
    
    /// Saves the current palette color again for every room whose saved color or symbol is
    /// outdated (see ``needsColorMigration``).
    static func migrateStoredColorsIfNeeded(_ rooms: [RoomModel]) async {
        let outdated = rooms.filter { $0.needsColorMigration && $0.recordID != nil }
        guard !outdated.isEmpty else { return }
        await CloudKitManager.shared.batchUpdate(outdated)
    }
    
    /// The room's chores, fetched from CloudKit. Same as ``relatedChores``.
    func fetchRelatedChores() async -> [ChoreModel] {
        guard let relatedChoresReference, !relatedChoresReference.isEmpty else {
            return []
        }
        return await CloudKitManager.shared.fetchRecordsByRecordReference(for: ChoreModel.self, recordReferences: relatedChoresReference) ?? []
    }
}
