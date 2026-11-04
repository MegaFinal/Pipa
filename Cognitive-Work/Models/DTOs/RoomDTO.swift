//
//  RoomDTO.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 26/08/26.
//

import SwiftUI
import CloudKit

/// A room as presented during onboarding, before it is persisted to CloudKit.
///
/// This type carries only what the room selection screens need, keeping the UI
/// free from CloudKit references. Once the user confirms the selection, the
/// picked instances are mapped into ``RoomModel`` records.
///
/// Each instance also holds its own presentation state, so a list of rooms can
/// track selection and expansion per row instead of sharing a single flag.
///
/// Example:
/// ```swift
/// var rooms = [
///     RoomDTO(name: "Kitchen", symbol: "fork.knife"),
///     RoomDTO(name: "Bathroom", symbol: "shower")
/// ]
/// ```
struct RoomDTO: Identifiable {

    // MARK: - Properties

    /// Stable identity used by `ForEach`.
    ///
    /// > Note: Generated locally rather than derived from ``RoomModel``, whose
    /// > `recordID` is `nil` until the record reaches CloudKit.
    let id = UUID()

    /// Name shown to the user.
    var name: String

    /// SF Symbol name used as the room icon.
    var symbol: String

    /// Whether the user picked this room to be part of the house.
    var isSelected: Bool = false

    /// Whether this entry is the trailing "add room" placeholder instead of a
    /// real room.
    ///
    /// Lets the grid render the creation button as one more cell, keeping a
    /// single `ForEach` over the collection.
    var isAddButton: Bool = false

    /// Color used to identify the room in the UI.
    var color: RoomColor = .blue
    
    /// Texture picked for a custom room; `nil` for the default types, which have their own.
    var pattern: RoomTexturePattern? = nil

    /// Whether the room section is showing its chores.
    ///
    /// Held per room so expanding one section leaves the others untouched.
    var isExpanded: Bool = false
    
    /// One entry per room of this type in the house (e.g. two bedrooms), edited with a long
    /// press on the room's card. Never empty: every type has at least one room.
    var instances: [RoomInstanceDTO] = [RoomInstanceDTO()]
    
    // MARK: - Quantity
    
    /// How many rooms of this type the house has.
    var quantity: Int { instances.count }
    
    /// The name the room at `index` is saved with: the name the user typed for it, if any,
    /// otherwise ``name`` — numbered ("Quarto 1", "Quarto 2") once there's more than one.
    func instanceName(at index: Int) -> String {
        if instances.indices.contains(index), let customName = instances[index].customName {
            return customName
        }
        return quantity == 1 ? name : "\(name) \(index + 1)"
    }
    
    /// Adds rooms to, or removes them from, the end of ``instances`` until there are exactly
    /// `newQuantity` — never fewer than one.
    mutating func setQuantity(_ newQuantity: Int) {
        let target = max(1, newQuantity)
        
        if target > instances.count {
            instances += (instances.count..<target).map { _ in RoomInstanceDTO() }
        } else if target < instances.count {
            instances.removeLast(instances.count - target)
        }
    }
}

/// One room of a ``RoomDTO`` type — e.g. the second bedroom.
struct RoomInstanceDTO: Identifiable, Equatable {
    
    /// Stable identity used by `ForEach` and focus.
    let id = UUID()
    
    /// A name the user typed for this room, or `nil` to use the default one
    /// (see ``RoomDTO/instanceName(at:)``).
    var customName: String?
}
