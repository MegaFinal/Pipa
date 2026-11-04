//
//  ChorePopOverComponent.swift
//  Cognitive-Work
//
//  Created by Carolina Sun on 05/10/26.
//

import SwiftUI
import CloudKit

/// The pop-over shown when a bar of the week chart is tapped: the chore's room and name, and its
/// frequency, priority and duration tags.
struct ChorePopOverComponent: View {
    
    /// The chore shown.
    let chore: ChoreModel
    /// The member responsible (not shown at the moment).
    let user: UserModel?
    /// The chore's room, if known.
    let room: RoomModel?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // MARK: - Room and chore name, then the tags
            title
            ChorePriority(chore: chore, user: user)
        }
        .foregroundColor(.black)
        .frame(minWidth: width * 0.55, alignment: .leading)
        .frame(minHeight: height * 0.1)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        // Room, chore name and the three tags read as one sentence.
        .accessibilityElement(children: .ignore)
        .voiceOverLabel(accessibilityText)
    }
    
    /// "Cozinha: Lavar a louça. Semanal, prioridade alta, duração curta".
    private var accessibilityText: String {
        let tier = ChoreDurationTier.from(minutes: chore.duration)
        let roomName = room?.name.localizedDefault ?? L10n.tr("Cômodo")
        return L10n.tr("\(roomName): \(chore.localizedName). \(chore.frequency.displayName), prioridade \(chore.priorityTag.displayName), duração \(tier.displayText)")
    }
    
    /// Room name over the chore name.
    private var title: some View {
        VStack(alignment: .leading) {
            Text(room?.name.localizedDefault ?? L10n.tr("Cômodo"))
                .fontWeight(.regular)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            
            Text(chore.localizedName)
                .bold()
                .font(.title2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The pop-over's tags: frequency, priority and duration.
private struct ChorePriority: View {
    /// The chore whose tags are shown.
    let chore: ChoreModel
    /// The member responsible (not shown at the moment).
    let user: UserModel?
    
    var body: some View {
        HStack() {
            // MARK: Frequency, priority and duration tags
            CapsuleTag(
                tagName: chore.frequency.displayName,
                tagColor: chore.frequency.color,
                horizontalPadding: 7,
                verticalPadding: 1.5
            )
            
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
    
    /// The chore's duration group.
    private var tier: ChoreDurationTier {
        ChoreDurationTier.from(minutes: chore.duration)
    }
}

#Preview {
    let mockChore = ChoreModel(
        name: "Lavar banheiro",
        description: "Limpeza completa",
        frequency: .none,
        duration: 60.0,
        isPublic: true,
        priorityTag: .urgent
    )
    
    ChorePopOverComponent(chore: mockChore, user: nil, room: nil)
}
