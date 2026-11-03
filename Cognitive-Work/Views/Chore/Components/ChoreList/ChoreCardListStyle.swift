//
//  ChoreCardListStyle.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 26/08/26.
//

import Foundation
import SwiftUI
import UIKit
import CloudKit

/// A compact chore row used by the list layout: the room's folder shape with its icon,
/// who does it, the tags, the room and chore names and a button to mark it as done.
struct ChoreCardListStyle: View {
    /// The chore shown.
    var chore: ChoreModel
    /// The occurrence shown, for recurring chores. `nil` uses the chore's next occurrence.
    var recurrentAssignment: RecurrentAssignmentModel?
    /// Shared namespace for matched animations between the layouts.
    let namespace: Namespace.ID
    
    /// Gives the room, dates, assignments and members, and marks chores as done.
    @Bindable var carouselViewModel: CarouselViewModel
    /// Called when the row is tapped (opens the details).
    var onTap: () -> Void = {}
    
    /// The chore's room (its color and icon).
    var room: RoomModel? { carouselViewModel.getRoom(for: chore) }
    
    /// The next day the chore is due.
    var nextDate: Date? { carouselViewModel.nextDate(for: chore) }
    
    /// The occurrence(s) this row is about.
    var targetAssignments: [RecurrentAssignmentModel] {
        if let recurrentAssignment {
            return [recurrentAssignment]
        }
        return carouselViewModel.getAssignments(for: chore, on: nextDate)
    }
    
    /// Who is responsible for this occurrence (or for the chore, if the occurrence has nobody set).
    var occurrenceResponsibleUsers: [UserModel] {
        if let target = targetAssignments.first {
            if let refs = target.userReferences {
                let targetIDs = Set(refs.map(\.recordID))
                guard !targetIDs.isEmpty else { return [] }
                
                return carouselViewModel.userModels.filter { user in
                    guard let userID = user.recordID else { return false }
                    return targetIDs.contains(userID)
                }
            }
        }
        
        var targetIDs = Set<CKRecord.ID>()
        if let refs = chore.allResponsibleUsersReference, !refs.isEmpty {
            targetIDs.formUnion(refs.map(\.recordID))
        } else if let currentID = chore.currentResponsibleReference?.recordID {
            targetIDs.insert(currentID)
        }
        
        guard !targetIDs.isEmpty else { return [] }
        
        return carouselViewModel.userModels.filter { user in
            guard let userID = user.recordID else { return false }
            return targetIDs.contains(userID)
        }
    }
    
    /// Avatars shown before the "+N" badge takes over.
    private let maxVisibleUsers = 2
    
    /// The avatars that are drawn.
    private var visibleResponsibleUsers: [UserModel] {
        Array(occurrenceResponsibleUsers.prefix(maxVisibleUsers))
    }
    
    /// How many responsible members don't fit (the "+N").
    private var hiddenResponsibleCount: Int {
        max(0, occurrenceResponsibleUsers.count - maxVisibleUsers)
    }
    
    /// Circle with "+N", sized like an avatar.
    private var overflowBadge: some View {
        let side = width * 0.07
        return Text("+\(hiddenResponsibleCount)")
            .font(.system(size: side * 0.4, weight: .semibold))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .foregroundColor(.black)
            .frame(width: side, height: side)
            .background(Color(white: 0.9))
            .clipShape(Circle())
    }
    
    /// Whether this occurrence is already done.
    var isOccurrenceDone: Bool {
        carouselViewModel.isDone(for: chore, assignment: recurrentAssignment)
    }
    
    var body: some View {
        ZStack {
            // MARK: - Folder background
            FolderShape(
                cornerRadius: 25,
                tabWidth: 95,
                topCutoutHeight: 38
            )
            .fill(room?.color.uiColor ?? .gray)
            .shadow(color: .black.opacity(0.21), radius: 3.35, x: 0, y: 5)
            
            // MARK: - Room icon and content
            HStack(spacing: 15) {
                SymbolImage(name: room?.symbol ?? chore.symbolName)
                    .frame(width: width * 0.18, height: height * 0.08)
                    .foregroundColor(.white)
                
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 10) {
                        // MARK: - Avatars
                        HStack(spacing: -10) {
                            ForEach(visibleResponsibleUsers, id: \.recordID) { user in
                                UserProfilePictureTag(user: user, widthMultiplier: 0.07)
                                    .shadow(color: .black.opacity(0.24), radius: 1.83087, x: 1.71644, y: 1.14429)
                            }
                            
                            // Users that don't fit are summarized as "+N".
                            if hiddenResponsibleCount > 0 {
                                overflowBadge
                                    .shadow(color: .black.opacity(0.24), radius: 1.83087, x: 1.71644, y: 1.14429)
                            }
                        }
                        .padding(.bottom, 8)
                        
                        // MARK: - Tags
                        ChoreTagsRow(chore: chore, spacing: 8, horizontalPadding: 7.0, verticalPadding: 1.0)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    
                    // MARK: - Room name, chore name and completion button
                    VStack {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(room?.name.localizedDefault ?? L10n.tr("Sem cômodo"))
                                    .font(.system(size: 12))
                                
                                Text(chore.localizedName)
                                    .font(.system(size: 22))
                                    .bold()
                            }
                            .foregroundColor(.white)
                            
                            Spacer()
                            
                            // MARK: Completion button
                            Button {
                                toggleCompletion()
                            } label: {
                                ZStack {
                                    Circle()
                                        .foregroundColor(.white)
                                        .frame(width: width * 0.05)
                                    
                                    Image(systemName: isOccurrenceDone ? "checkmark.circle.fill" : "circle.fill")
                                        .foregroundColor(isOccurrenceDone ? .black : .white)
                                        .font(.system(size: 28))
                                }
                            }
                        }
                        .padding(.bottom, 16)
                    }
                }
            }
            .padding(.horizontal, 18.5)
        }
        .frame(width: width * 0.92)
        .frame(minHeight: height * 0.14)
        .onTapGesture(perform: onTap)
        .transition(.identity)
        // MARK: - VoiceOver
        // One element; the completion button becomes a named action.
        .accessibilityElement(children: .ignore)
        .voiceOverLabel(carouselViewModel.accessibilitySummary(for: chore, assignment: recurrentAssignment))
        // Voice Control: "Toque em <tarefa>"; the completion circle via "Mostrar ações para <tarefa>".
        .voiceControlNames(carouselViewModel.voiceControlInputLabels(for: chore))
        .voiceOverHint(L10n.tr("Toque duas vezes para ver os detalhes."))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onTap() }
        .accessibilityAction(named: Text(isOccurrenceDone ? L10n.tr("Marcar como pendente") : L10n.tr("Marcar como concluída"))) {
            toggleCompletion()
        }
    }
    
    /// Marks this occurrence as done (or not done again), from the circle button or VoiceOver.
    private func toggleCompletion() {
        let willBeDone = !isOccurrenceDone
        HapticsManager.notify(willBeDone ? .success : .warning)
        
        Task {
            recurrentAssignment == nil
            ? await carouselViewModel.toggle(chore: chore)
            : await carouselViewModel.toggle(assignment: recurrentAssignment!)
            VoiceOver.announce(willBeDone ? L10n.tr("Tarefa concluída") : L10n.tr("Tarefa marcada como pendente"))
        }
    }
}

#Preview("Card em lista") {
    @Previewable @Namespace var namespace
    
    let room: RoomModel = {
        var room = RoomModel(name: "Cozinha", symbol: "sofa", color: .orange)
        room.recordID = CKRecord.ID(recordName: "preview-room")
        return room
    }()
    
    let chore: ChoreModel = {
        let chore = ChoreModel(
            name: "Lavar a louça",
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
        chore.symbolName = "dishwasher"
        return chore
    }()
    
    let vm: CarouselViewModel = {
        let vm = CarouselViewModel()
        vm.roomModels = [room]
        return vm
    }()
    
    ChoreCardListStyle(chore: chore, namespace: namespace, carouselViewModel: vm) {
        print("Tapped")
    }
}
