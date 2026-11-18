//
//  MyBadgesView.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 18/11/26.
//

import SwiftUI

/// "Minhas Badges", opened from the profile: the room badges section of the rewards tab
/// (``RoomBadgesSection``), with the same tap-to-focus.
struct MyBadgesView: View {

    let viewModel: MyBadgesViewModel

    /// Id (``RoomBadge/id``) of the badge brought to the center of the screen, if any.
    @State private var focusedBadgeKey: String?

    /// Lets a badge fly from its row to the center and back.
    @Namespace private var badgeNamespace

    var body: some View {
        ScrollView(showsIndicators: false) {
            if viewModel.hasLoaded {
                RoomBadgesSection(
                    rooms: viewModel.rooms,
                    progress: viewModel.progress,
                    focusedBadgeKey: $focusedBadgeKey,
                    namespace: badgeNamespace
                )
                .padding(.vertical, 24)
            } else {
                ProgressView()
                    .padding(.top, 80)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.white.ignoresSafeArea())
        .navigationTitle("Minhas Badges")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.load()
        }
        .task {
            await viewModel.load()
        }
        .badgeFocus(
            progress: viewModel.progress,
            focusedBadgeKey: $focusedBadgeKey,
            namespace: badgeNamespace
        )
        // The focused badge covers the whole screen, the navigation bar included.
        .toolbar(focusedBadgeKey == nil ? .automatic : .hidden, for: .navigationBar)
    }
}

#Preview {
    var progress = RoomBadgeProgressModel(ownerRecordName: "preview")
    progress.apply([
        RoomBadgeChange(room: .kitchen, delta: 37),
        RoomBadgeChange(room: .garage, delta: 6)
    ], dayKey: "2026-11-18")
    return NavigationStack {
        MyBadgesView(viewModel: MyBadgesViewModel(
            previewProgress: progress,
            rooms: [.kitchen, .bathroom, .garage]
        ))
    }
}
