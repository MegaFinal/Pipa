//
//  NewRoomSheet.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 24/08/26.
//

import SwiftUI

/// Sheet for adding a custom room during onboarding, presented from
/// ``SelectRoomsOnboardingView`` when the user taps the "+" card.
///
/// Uses the same ``RoomFormSheet`` as the house settings, so the user picks the name, color,
/// texture and icon the same way in both places. Nothing is saved to CloudKit here: the room
/// is added, already selected, to ``OnboardingViewModel/availableRooms`` and persisted with
/// the others when the step is confirmed.
struct NewRoomSheet: View {
    /// The onboarding's view model, which keeps the selected rooms.
    @Environment(OnboardingViewModel.self) var viewModel
    
    var body: some View {
        // MARK: - Room form (adds the room to the onboarding's list)
        RoomFormSheet(room: nil) { name, color, symbol, pattern in
            viewModel.addCustomRoom(name: name, color: color, symbol: symbol, pattern: pattern)
            return true
        }
    }
}

#Preview {
    NewRoomSheet()
        .environment(OnboardingViewModel())
}
