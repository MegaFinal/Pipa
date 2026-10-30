//
//  RoomsManagementViewModel.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 06/10/26.
//

import Foundation
import CloudKit

/// Owns the room CRUD shown in the house settings: lists the house's rooms and creates,
/// renames/recolors and deletes them.
@MainActor
@Observable
final class RoomsManagementViewModel {
    
    // MARK: - State
    
    /// Rooms of the current house, sorted by name. The house-wide "Casa" room is left out: it
    /// isn't a real room and every house needs it.
    private(set) var rooms: [RoomModel] = []
    
    /// How many chores each room has, keyed by the room's record ID.
    private(set) var choreCountByRoom: [CKRecord.ID: Int] = [:]
    
    /// True while the room list is being fetched.
    private(set) var isLoading = false
    
    /// True while a create/update is in flight.
    private(set) var isSaving = false
    
    /// True while a room (and its chores) is being deleted.
    var isDeleting = false
    
    /// Message for the error alert; `nil` hides it.
    var errorMessage: String?
    
    /// The house whose rooms are managed. Resolved on ``load()`` when not injected.
    private var house: HouseModel?
    
    /// Name of the room that represents chores for the whole house.
    static let houseWideRoomName = "Casa"
    
    /// Default icon for rooms created here (same one the onboarding uses for custom rooms).
    static let customRoomSymbol = "armchair"
    
    /// Icons a custom room can pick from: the artwork in the `ChoresSymbols` asset folder that
    /// isn't taken by a default room type (those live in its `DefaultRooms` subfolder).
    static let customRoomSymbols: [String] = [
        "armchair", "twin.bed.stripes", "laptop", "stove.pans",
        "shower", "washing.machine", "clothes.basket", "clothes.line.filled",
        "balcony.aluminum.chair", "default.plant", "bicicle", "kite"
    ]
    
    /// Creates the view model for `house`'s rooms.
    init(house: HouseModel? = nil) {
        self.house = house
    }
    
    // MARK: - Helpers
    
    /// Whether the room is one of the default types, whose color and icon come from
    /// ``DefaultRoomsOnboarding`` and can't be changed.
    static func isDefaultType(_ room: RoomModel) -> Bool {
        DefaultRoomsOnboarding(kind: room.kind, name: room.name) != nil
    }
    
    /// Whether `name` can't be used for a room ("Casa" is reserved for the house-wide room).
    static func isReservedName(_ name: String) -> Bool {
        name.trimmingCharacters(in: .whitespaces)
            .caseInsensitiveCompare(houseWideRoomName) == .orderedSame
    }
    
    /// How many chores `room` has.
    func choreCount(for room: RoomModel) -> Int {
        guard let recordID = room.recordID else { return 0 }
        return choreCountByRoom[recordID] ?? 0
    }
    
    // MARK: - Fetch
    
    /// Loads the house (if needed), its rooms and how many chores each room has.
    func load() async {
        isLoading = true
        defer { isLoading = false }
        
        if house == nil {
            house = try? await CloudKitManager.shared.currentHouse()
        }
        
        guard let houseID = house?.recordID else {
            errorMessage = L10n.tr("Não foi possível encontrar sua casa. Tente novamente.")
            return
        }
        
        let reference = CKRecord.Reference(recordID: houseID, action: .none)
        let predicate = NSPredicate(format: "house == %@", reference)
        
        async let fetchRooms = CloudKitManager.shared.fetchAll(RoomModel.self, predicate: predicate)
        async let fetchChores = CloudKitManager.shared.fetchAll(ChoreModel.self)
        let (fetchedRooms, chores) = await (fetchRooms, fetchChores)
        
        rooms = sorted(fetchedRooms.filter { !Self.isHouseWideRoom($0) })
        
        var counts: [CKRecord.ID: Int] = [:]
        for chore in chores {
            if let roomID = chore.roomReference?.recordID {
                counts[roomID, default: 0] += 1
            }
        }
        choreCountByRoom = counts
    }
    
    // MARK: - Create
    
    /// Creates a custom room in the current house.
    ///
    /// - Returns: `true` on success, otherwise `false` with ``errorMessage`` set.
    @discardableResult
    func createRoom(
        name: String,
        color: RoomColor,
        symbol: String = customRoomSymbol,
        pattern: RoomTexturePattern = .fallback
    ) async -> Bool {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !Self.isReservedName(name) else { return false }
        
        guard let house, let houseID = house.recordID,
              let houseReference = house.reference(action: .deleteSelf),
              let parentReference = house.reference(action: .none)
        else {
            errorMessage = L10n.tr("Não foi possível encontrar sua casa. Tente novamente.")
            return false
        }
        
        isSaving = true
        defer { isSaving = false }
        
        let draft = RoomModel(
            name: name,
            symbol: symbol,
            house: houseReference,
            color: color,
            pattern: pattern
        )
        
        guard let created = await CloudKitManager.shared.create(
            draft,
            zoneID: houseID.zoneID,
            parent: parentReference
        ) else {
            errorMessage = L10n.tr("Não foi possível criar o cômodo. Verifique sua conexão e tente novamente.")
            return false
        }
        
        // Re-read the house so appending the room doesn't overwrite fields that changed since
        // it was loaded (HouseModel writes every relationship on save).
        let freshHouse = await fetchFreshHouse() ?? house
        await freshHouse.appendRoom(rooms: [created])
        self.house = freshHouse
        
        // CloudKit query indexes lag behind writes, so add it locally instead of refetching.
        rooms = sorted(rooms + [created])
        return true
    }
    
    // MARK: - Update
    
    /// Renames a room and, for custom rooms, changes its color, icon and texture.
    ///
    /// - Returns: `true` on success, otherwise `false` with ``errorMessage`` set.
    @discardableResult
    func updateRoom(
        _ room: RoomModel,
        name: String,
        color: RoomColor,
        symbol: String,
        pattern: RoomTexturePattern
    ) async -> Bool {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !Self.isReservedName(name) else { return false }
        
        isSaving = true
        defer { isSaving = false }
        
        var updated = room
        
        if Self.isDefaultType(room) {
            // Rooms saved before `kind` existed are matched to their type by name, so pin the
            // type before renaming — otherwise the room would lose its default look and chores.
            if updated.kind == nil {
                updated.kind = room.name
            }
        } else {
            updated.color = color
            updated.symbol = symbol
            updated.pattern = pattern
        }
        updated.name = name
        
        guard await CloudKitManager.shared.update(updated) else {
            errorMessage = L10n.tr("Não foi possível salvar o cômodo. Verifique sua conexão e tente novamente.")
            return false
        }
        
        if let index = rooms.firstIndex(where: { $0.recordID == room.recordID }) {
            rooms[index] = updated
        }
        rooms = sorted(rooms)
        return true
    }
    
    // MARK: - Delete
    
    /// Deletes a room together with every chore that belongs to it.
    ///
    /// Chores are parented to the house, not to the room, so CloudKit would leave them behind
    /// pointing at a room that no longer exists — they're deleted explicitly first.
    ///
    /// - Returns: `true` on success, otherwise `false` with ``errorMessage`` set.
    @discardableResult
    func deleteRoom(_ room: RoomModel) async -> Bool {
        guard let roomID = room.recordID else { return false }
        
        isDeleting = true
        defer { isDeleting = false }
        
        let chores = await CloudKitManager.shared.fetchAll(ChoreModel.self)
            .filter { $0.roomReference?.recordID == roomID }
        
        for chore in chores {
            guard await chore.delete() else {
                errorMessage = L10n.tr("Não foi possível excluir as tarefas do cômodo. Verifique sua conexão e tente novamente.")
                return false
            }
        }
        
        guard await CloudKitManager.shared.delete(room) else {
            errorMessage = L10n.tr("Não foi possível excluir o cômodo. Verifique sua conexão e tente novamente.")
            return false
        }
        
        if let freshHouse = await fetchFreshHouse() ?? house {
            await freshHouse.removeRoom(room)
            house = freshHouse
        }
        
        rooms.removeAll { $0.recordID == roomID }
        choreCountByRoom[roomID] = nil
        return true
    }
    
    // MARK: - Private
    
    /// Whether `room` is the "Casa" room that holds chores of the whole house.
    private static func isHouseWideRoom(_ room: RoomModel) -> Bool {
        room.kind == nil && room.name == houseWideRoomName
    }
    
    /// `rooms` in alphabetical order.
    private func sorted(_ rooms: [RoomModel]) -> [RoomModel] {
        rooms.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    
    /// Reads the house record by ID (immediately consistent, unlike queries).
    private func fetchFreshHouse() async -> HouseModel? {
        guard let houseID = house?.recordID else { return nil }
        return await CloudKitManager.shared.fetchRecordsByRecordReference(
            for: HouseModel.self,
            recordReferences: [CKRecord.Reference(recordID: houseID, action: .none)]
        )?.first
    }
}
