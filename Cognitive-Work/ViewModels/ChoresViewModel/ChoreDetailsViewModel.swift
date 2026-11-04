//
//  ChoreDetailsViewModel.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 26/10/26.
//

import SwiftUI
import CloudKit

/// State and actions of the chore details card: checklist loading, postponing, completing and
/// the people responsible for the occurrence being shown.
@MainActor
@Observable
final class ChoreDetailsViewModel {
    
    /// The chore shown.
    let chore: ChoreModel
    
    /// The occurrence this card represents when opened from the list layout; `nil` in the carousel,
    /// where the card stands for the chore as a whole.
    let recurrentAssignment: RecurrentAssignmentModel?
    
    /// Gives the room, members, dates and assignments, and saves completion and postponing.
    let carouselViewModel: CarouselViewModel
    
    /// The chore's checklist items, loaded the first time the card is flipped.
    var checkList: [CheckItemModel] = []
    
    /// `true` while the checklist is being fetched.
    private(set) var isLoadingChecklist = false
    
    /// The postpone action being saved (1 or 7 days), to show its spinner and block double taps.
    private(set) var postponingDays: Int?
    
    /// Set when the new date couldn't be saved.
    var didFailToPostpone = false
    
    init(
        chore: ChoreModel,
        recurrentAssignment: RecurrentAssignmentModel?,
        carouselViewModel: CarouselViewModel
    ) {
        self.chore = chore
        self.recurrentAssignment = recurrentAssignment
        self.carouselViewModel = carouselViewModel
    }
    
    // MARK: - Chore data
    
    /// The chore's room (symbol, color and name).
    var room: RoomModel? { carouselViewModel.getRoom(for: chore) }
    
    /// The day shown: this occurrence's own day, or the chore's next date.
    var occurrenceDate: Date? { recurrentAssignment?.day ?? carouselViewModel.nextDate(for: chore) }
    
    /// The occurrence(s) this card is about.
    var targetAssignments: [RecurrentAssignmentModel] {
        if let recurrentAssignment { return [recurrentAssignment] }
        return carouselViewModel.getAssignments(for: chore, on: occurrenceDate)
    }
    
    /// Whether this occurrence is already done.
    var isDone: Bool {
        carouselViewModel.isDone(for: chore, assignment: recurrentAssignment)
    }
    
    /// Daily chores can't be postponed: tomorrow already has its own occurrence.
    var canPostpone: Bool { chore.frequency != .daily }
    
    /// The members responsible for this occurrence: the ones assigned to it, or else the chore's
    /// rotation (or its current responsible).
    var responsibleUsers: [UserModel] {
        let ids = responsibleUserIDs
        return carouselViewModel.userModels.filter { user in
            user.recordID.map(ids.contains) ?? false
        }
    }
    
    private var responsibleUserIDs: Set<CKRecord.ID> {
        if let references = targetAssignments.first?.userReferences {
            return Set(references.map(\.recordID))
        }
        if let references = chore.allResponsibleUsersReference, !references.isEmpty {
            return Set(references.map(\.recordID))
        }
        if let currentID = chore.currentResponsibleReference?.recordID {
            return [currentID]
        }
        return []
    }
    
    // MARK: - Accessibility
    
    /// Spoken checklist header: "Checklist, sexta-feira, 25 de setembro, 2 de 5 itens concluídos".
    var checklistAccessibilityLabel: String {
        var parts = [L10n.tr("Checklist")]
        parts.append(occurrenceDate.map(CarouselViewModel.accessibilityDateText) ?? L10n.tr("Sem data definida"))
        if !checkList.isEmpty {
            let done = checkList.filter(\.isDone).count
            parts.append(L10n.tr("\(done) de \(checkList.count) itens concluídos"))
        }
        return parts.joined(separator: ", ")
    }
    
    // MARK: - Actions
    
    /// Fetches the checklist once, when the card is flipped to this side.
    func loadChecklistIfNeeded(isShowingBack: Bool) async {
        guard isShowingBack, checkList.isEmpty, !(chore.checkListReference ?? []).isEmpty else { return }
        isLoadingChecklist = true
        checkList = await chore.checkList
        isLoadingChecklist = false
    }
    
    /// Marks the occurrence as done, or undoes it.
    func toggleCompletion() async {
        if let recurrentAssignment {
            _ = await carouselViewModel.toggle(assignment: recurrentAssignment)
        } else {
            _ = await carouselViewModel.toggle(chore: chore)
        }
    }
    
    /// Moves the occurrence `days` ahead and, on success, closes the card so it leaves today's list.
    func postpone(byDays days: Int) async {
        guard postponingDays == nil else { return }
        postponingDays = days
        let success = await carouselViewModel.postpone(
            chore: chore,
            assignment: recurrentAssignment ?? targetAssignments.first,
            byDays: days
        )
        postponingDays = nil
        
        guard success else {
            HapticsManager.notify(.error)
            didFailToPostpone = true
            return
        }
        
        HapticsManager.notify(.success)
        VoiceOver.announce(days == 1 ? L10n.tr("Tarefa adiada em 1 dia") : L10n.tr("Tarefa adiada em 1 semana"))
        if carouselViewModel.layoutMode == .grid {
            carouselViewModel.clearFocus()
        } else {
            carouselViewModel.clearFocusedDetails()
        }
    }
}
