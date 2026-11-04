//
//  ChoreCarouselCard.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 18/08/26.
//

import SwiftUI
import CloudKit

/// The front face of a chore's card in the carousel: the chore's name and its room's big icon,
/// over the room's color and texture.
struct ChoreCarouselCard: View {
    /// The chore on the card.
    let chore: ChoreModel
    /// Shared namespace for the card's matched-geometry animations.
    let namespace: Namespace.ID
    
    /// The chores screen's view model.
    var carouselViewModel: CarouselViewModel
    
    /// The chore's room, from the rooms already in memory.
    var room: RoomModel? { carouselViewModel.getRoom(for: chore) }
    
    var body: some View {
        ZStack {
            // MARK: - Chore name (top)
            VStack {
                Text(chore.localizedName)
                    .font(.custom("Alan Sans", size: 32))
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .frame(width: width * 0.62)
                Spacer()
            }
            .padding(.top, height * 0.05)
            
            // MARK: - Room icon (center)
            SymbolImage(name: room?.symbol ?? chore.symbolName)
                .frame(width: width * 0.6, height: height * 0.4)
                .padding(.top, height * 0.07)
        }
        // MARK: - Card style and accessibility
        .foregroundColor(.white)
        .frame(width: width * 0.7, height: height * 0.43)
        .background { cardBackground }
        .clipShape(RoundedRectangle(cornerRadius: 31))
        .shadow(color: .black.opacity(0.14), radius: 16.84883, x: 0, y: 4.79682)
        .transition(.identity)
        // One element: the room icon and texture are decorative.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(carouselViewModel.accessibilitySummary(
            for: chore,
            assignment: carouselViewModel.getAssignmentsForActiveContext(for: chore).first
        ))
        .voiceControlNames(carouselViewModel.voiceControlInputLabels(for: chore))
    }
    
    /// The carousel card is bigger than the onboarding ones, so its texture needs less zoom.
    private static let textureZoom: CGFloat = 1.5
    
    /// The room's color with its texture; gray when the chore's room is unknown.
    @ViewBuilder
    private var cardBackground: some View {
        if let room {
            RoomTextureBackground(room: room, zoom: Self.textureZoom)
        } else {
            Color.gray
        }
    }
}

#Preview("Com cômodo") {
    @Previewable @Namespace var namespace

    let vm: CarouselViewModel = {
        var room = RoomModel(name: "Cozinha", symbol: "pantry", color: .orange)
        room.recordID = CKRecord.ID(recordName: "preview-room")

        let vm = CarouselViewModel()
        vm.roomModels = [room]
        return vm
    }()

    let chore: ChoreModel = {
        let chore = ChoreModel(
            name: "Check expiration dates",
            description: "Depois do jantar",
            frequency: .daily,
            duration: 20,
            isPublic: true,
            priorityTag: .medium,
            roomReference: CKRecord.Reference(
                recordID: CKRecord.ID(recordName: "preview-room"),
                action: .none
            )
        )
        chore.symbolName = "toilet"
        return chore
    }()

    ChoreCarouselCard(chore: chore, namespace: namespace, carouselViewModel: vm)
}
