//
//  UserProfilePictureList.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 27/08/26.
//

import SwiftUI
import CloudKit

/// A row of overlapping user avatars (for example, the members responsible for a chore).
///
/// Up to ``maxVisible`` users are shown as-is. With more than that, only the
/// first `maxVisible - 1` avatars are drawn, followed by a circle with "+N",
/// where N is how many users are hidden.
struct UserProfilePictureList: View {
    /// The users to show.
    let users: [UserModel]
    /// Each avatar's size, as a fraction of the screen width.
    var widthMultiplier: Double
    /// Space between two avatars; negative to overlap them.
    var spacing: CGFloat = -18
    
    /// Maximum number of circles (avatars + overflow badge) shown at once.
    private let maxVisible = 3
    
    /// Whether there are more users than fit.
    private var hasOverflow: Bool { users.count > maxVisible }
    /// The users whose avatar is drawn.
    private var visibleUsers: [UserModel] {
        hasOverflow ? Array(users.prefix(maxVisible - 1)) : users
    }
    /// How many users are hidden behind "+N".
    private var overflowCount: Int { users.count - visibleUsers.count }
    
    var body: some View {
        HStack(spacing: spacing) {
            // MARK: - Avatars
            ForEach(visibleUsers, id: \.recordID) { user in
                UserProfilePictureTag(user: user, widthMultiplier: widthMultiplier)
                    .shadow(color: .black.opacity(0.24), radius: 1.83, x: 1.71, y: 1.14)
            }
            
            // MARK: - "+N" badge for the hidden users
            if hasOverflow {
                overflowBadge
                    .shadow(color: .black.opacity(0.24), radius: 1.83, x: 1.71, y: 1.14)
            }
        }
        // Read as "Fulano, Ciclano e mais 2" instead of one stop per avatar.
        .accessibilityElement(children: .ignore)
        .voiceOverLabel(ProfileAccessibility.memberList(users.map(\.name)))
        .accessibilityHidden(users.isEmpty)
    }
    
    /// Circle showing "+N" for the users that don't fit.
    private var overflowBadge: some View {
        let side = width * widthMultiplier
        return Text("+\(overflowCount)")
            .font(.system(size: side * 0.4, weight: .semibold))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .foregroundColor(.black)
            .frame(width: side, height: side)
            .background(Color(white: 0.9))
            .clipShape(Circle())
    }
}
