//
//  ClotheslineViewModel.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 26/10/26.
//

import SwiftUI

/// Drives the "Tarefas sem dono" card on the progress tab: the chores hanging on the clothesline
/// and the details of the one the user tapped.
@Observable
final class ClotheslineViewModel {
    
    /// One chore hanging on the clothesline.
    struct Tile: Identifiable {
        let id: String
        let name: String
        let symbol: String
        let fillColor: Color
        let pinColor: Color
        let isSelected: Bool
    }
    
    let carouselViewModel: CarouselViewModel
    
    private var selectedItemID: String?
    
    init(carouselViewModel: CarouselViewModel) {
        self.carouselViewModel = carouselViewModel
    }
    
    var items: [CarouselViewModel.UnassignedItem] { carouselViewModel.unassignedItems }
    
    var isEmpty: Bool { items.isEmpty }
    
    var selectedItem: CarouselViewModel.UnassignedItem? {
        items.first { $0.id == selectedItemID }
    }
    
    var tiles: [Tile] {
        items.map { item in
            let room = carouselViewModel.getRoom(for: item.chore)
            let color = room?.color.uiColor ?? .gray
            return Tile(
                id: item.id,
                name: item.chore.localizedName,
                symbol: room?.symbol ?? item.chore.symbolName,
                fillColor: color.opacity(0.3),
                pinColor: color,
                isSelected: item.id == selectedItemID
            )
        }
    }
    
    func toggleSelection(of id: String) {
        selectedItemID = selectedItemID == id ? nil : id
    }
    
    @MainActor
    func pick(_ item: CarouselViewModel.UnassignedItem) {
        carouselViewModel.requestPick(item)
    }
}
