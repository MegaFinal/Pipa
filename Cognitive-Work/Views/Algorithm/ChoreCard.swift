//
//  ChoreCard.swift
//  Cognitive-Work
//
//  Created by anshu Li on 25/08/26.
//

import SwiftUI
import CloudKit

/// A chore's card on the generated schedule screen: room and chore name, the room icon, and
/// who does it with the chore's priority and duration.
struct ChoreCard: View {
    
    /// The chore on the card.
    let chore: ChoreModel
    /// The member responsible, if any.
    let user: UserModel?
    /// The chore's room, if known.
    let room: RoomModel?
    
    var body: some View {
        VStack(spacing: 30) {
            // MARK: - Room and chore name
            title
            
            // MARK: - Room icon, responsible member and tags
            HStack {
                SymbolImage(name: room?.symbol ?? chore.symbolName)
                    .frame(width: width * 0.3)
                    .padding(.horizontal)
                
                ChorePriority(chore: chore, user: user)
            }
        }
        .foregroundColor(.white)
        .frame(width: width * 0.85, height: height * 0.35)
        .background(room?.color.lowOpacityColor ?? .gray)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.32), radius: 5.8, x: 4, y: 6)
        // One sentence instead of icon, avatar and tags read separately.
        .accessibilityElement(children: .ignore)
        .voiceOverLabel(accessibilityText)
    }
    
    /// "Cozinha: Lavar a louça. Responsável: Ana, prioridade alta, duração curta".
    private var accessibilityText: String {
        let tier = ChoreDurationTier.from(minutes: chore.duration)
        let roomName = room?.name.localizedDefault ?? L10n.tr("Cômodo")
        if let user {
            return L10n.tr("\(roomName): \(chore.localizedName). Responsável: \(user.name), prioridade \(chore.priorityTag.displayName), duração \(tier.displayText)")
        }
        return L10n.tr("\(roomName): \(chore.localizedName). Prioridade \(chore.priorityTag.displayName), duração \(tier.displayText)")
    }
    
    /// Room name over the chore name.
    private var title: some View {
        VStack {
            Text(room?.name.localizedDefault ?? L10n.tr("Cômodo"))
                .fontWeight(.regular)
                .font(.system(size: 17, weight: .semibold))
            Text(chore.localizedName)
                .bold()
                .font(.custom("Alan Sans", size: 26))
        }
    }
}

/// The right side of ``ChoreCard``: the responsible member's avatar and the priority and duration tags.
private struct ChorePriority: View {
    /// The chore whose tags are shown.
    let chore: ChoreModel
    /// Was `@State`: SwiftUI keeps a `@State` value across re-renders and ignores the new one
    /// passed in by the parent, so every card kept showing the first selected user's photo.
    let user: UserModel?
    
    var body: some View {
        HStack {
            // MARK: - Divider line
            Rectangle()
                .frame(width: 2)
            
            // MARK: - Avatar and tags
            VStack(alignment: .leading) {
                UserProfilePictureTag(user: user, widthMultiplier: 0.08)

                CapsuleTag(
                    tagName: chore.priorityTag.displayName,
                    tagColor: chore.priorityTag.color,
                    horizontalPadding: 7,
                    verticalPadding: 1.5
                )
                
                CapsuleTag(
                    tagName: tier.displayText,
                    tagColor: tier.color,
                    horizontalPadding: 7,
                    verticalPadding: 1.5
                )
            }
        }
        .frame(height: 100)
    }
    
    /// The chore's duration group.
    private var tier: ChoreDurationTier {
        ChoreDurationTier.from(minutes: chore.duration)
    }
}

#Preview {
    let mockChore = ChoreModel(
        name: "Lavar banheiro",
        description: "Limpeza completa",
        frequency: .weekly,
        duration: 90.0,
        isPublic: true,
        priorityTag: .urgent
    )
    
    ChoreCard(chore: mockChore, user: nil, room: nil)
}
