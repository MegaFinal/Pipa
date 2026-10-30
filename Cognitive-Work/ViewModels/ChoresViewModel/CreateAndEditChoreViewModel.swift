//
//  CreateAndEditChoreViewModel.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 29/09/26.
//

import Foundation
import CloudKit

/// Drives ``CreateAndEditChoreView``, the form shared by the create and edit flows.
@MainActor
@Observable
final class CreateAndEditChoreViewModel {
    
    // MARK: - Mode
    
    /// Fixed at init, so it never flips while a new chore is being saved.
    enum Mode: Equatable {
        /// Creating a new chore.
        case create
        /// Editing an existing chore.
        case edit
    }
    
    // MARK: - Alert
    
    /// A failure presented to the user while the form stays open.
    struct FormAlert: Identifiable, Equatable {
        /// Which action failed.
        enum Kind: Equatable {
            /// Saving the chore failed.
            case saveFailed
            /// Deleting the chore failed.
            case deleteFailed
        }
        
        /// Identifier for SwiftUI alerts.
        let id = UUID()
        /// Which action failed.
        let kind: Kind
        /// What went wrong, already user-facing.
        let message: String
        
        /// The alert's title, translated.
        var title: String {
            switch kind {
            case .saveFailed: return L10n.tr("Não foi possível salvar")
            case .deleteFailed: return L10n.tr("Não foi possível excluir")
            }
        }
    }
    
    // MARK: - Dependencies
    
    /// The persisted chore being edited, or an unsaved instance when creating a new one.
    let originalModel: ChoreModel
    
    /// The occurrence(s) of a recurring chore this screen was opened for, if any.
    let targetAssignments: [RecurrentAssignmentModel]
    
    /// The chores screen's view model, refreshed after saving or deleting.
    private let carouselViewModel: CarouselViewModel
    
    /// Saves and deletes in CloudKit.
    private let cloudKit: CloudKitManager
    /// Gives points for creating chores.
    private let scoreManager: ScoreManager
    
    /// Gives the current date (fixed in tests).
    private let now: () -> Date
    
    /// Whether the form creates or edits a chore.
    let mode: Mode
    
    // MARK: - Form state
    
    /// The editable copy of the chore.
    var draft: ChoreDTO
    
    /// The date picked in the form (for one-off and weekly-or-rarer chores).
    var selectedDate: Date?
    
    /// The house's rooms, to pick from.
    private(set) var availableRooms: [RoomModel] = []
    
    /// The house members, to pick the responsible ones from.
    private(set) var availableHouseUsers: [UserModel]
    
    /// The signed-in member's record inside the house.
    private(set) var currentHouseUser: UserModel?
    
    /// `true` once rooms and members are loaded.
    private(set) var isLoaded = false
    
    /// `true` while saving.
    private(set) var isSaving = false
    
    /// `true` while deleting.
    private(set) var isDeleting = false
    
    /// An error to show, or `nil`.
    var alert: FormAlert?

    // MARK: - Apple Intelligence

    /// Form fields the AI can fill from a description.
    enum SuggestedField: Hashable {
        case room, frequency, duration, priority, responsible, date
    }

    /// The "Detalhes" text the AI wrote last; it's replaced by a new description only while the
    /// field still holds exactly that (or is empty), so the person's own text is never lost.
    private var suggestedDescription: String?

    /// Checklist items the AI added (steps the person listed, or ideas they tapped). A new
    /// description replaces the listed steps; items the person typed stay.
    private(set) var aiChecklistIDs: Set<UUID> = []

    /// Whether "Detalhes" still holds the AI's text (for sparkles).
    var isDescriptionSuggested: Bool {
        guard let suggestedDescription, !suggestedDescription.isEmpty else { return false }
        return draft.description == suggestedDescription
    }

    /// Whether the checklist has items the AI added (for sparkles).
    var hasSuggestedChecklistItems: Bool {
        draft.checklist.contains { aiChecklistIDs.contains($0.id) && !$0.name.isEmpty }
    }

    /// Whether the person typed checklist items themselves; then no ideas are offered.
    var hasHandWrittenChecklistItems: Bool {
        draft.checklist.contains {
            !aiChecklistIDs.contains($0.id)
                && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Typical steps for the chore named so far, to offer as chips. Only for new chores.
    func checklistIdeas() async -> [String]? {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSuggest, !name.isEmpty else { return nil }
        return await IntelligenceManager.shared.suggestChecklist(
            for: name,
            room: draft.room?.name.localizedDefault,
            existing: draft.checklist.map(\.name).filter { !$0.isEmpty }
        )
    }

    /// Adds a tapped idea to the checklist (into the empty row if there is one).
    func addChecklistIdea(_ idea: String) {
        let item = CheckItemDTO(name: idea, isDone: false)
        aiChecklistIDs.insert(item.id)
        draft.checklist.removeAll { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        draft.checklist.append(item)
    }

    /// Puts the steps the person listed in the checklist, replacing steps from an earlier
    /// description; items they typed stay first. There's always at least one row to type into.
    private func applyChecklistSteps(_ steps: [String]) {
        var kept = draft.checklist.filter {
            !aiChecklistIDs.contains($0.id)
                && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let keptKeys = Set(kept.map { IntelligenceManager.foldedKey($0.name) })
        for step in steps where !keptKeys.contains(IntelligenceManager.foldedKey(step)) {
            let item = CheckItemDTO(name: step, isDone: false)
            aiChecklistIDs.insert(item.id)
            kept.append(item)
        }
        if kept.isEmpty { kept.append(CheckItemDTO(name: "", isDone: false)) }
        draft.checklist = kept
    }

    /// Fields the AI filled and the person hasn't picked by hand since (for sparkles).
    private(set) var suggestedFields: Set<SuggestedField> = []

    /// Fields the person picked by hand: a description never overwrites them. Everything else
    /// can be filled, because a new chore starts with placeholder values (the first option of
    /// each picker, see ``replaceUndefinedTags(in:)``), not real choices.
    private var handPickedFields: Set<SuggestedField> = []

    /// Whether the name field can take a description: only for a new chore, and only when the
    /// on-device model can run here.
    var canSuggest: Bool {
        mode == .create && IntelligenceManager.shared.isAvailable
    }

    /// Asks the on-device model to fill the form from `text` ("lavar a louça toda semana, eu e Ana").
    func suggestChore(for text: String) async -> ChoreSuggestion? {
        await IntelligenceManager.shared.suggestChore(
            for: text,
            rooms: availableRooms,
            housemates: availableHouseUsers,
            currentUser: currentHouseUserInList
        )
    }

    /// Applies a suggestion to both steps of the form. 
    func apply(_ suggestion: ChoreSuggestion) {
        draft.name = suggestion.name

        func fill(_ field: SuggestedField, _ update: () -> Void) {
            guard !handPickedFields.contains(field) else { return }
            update()
            suggestedFields.insert(field)
        }

        if let room = suggestion.room {
            fill(.room) { draft.room = room }
        }
        
        if let frequency = suggestion.frequency {
            fill(.frequency) { draft.frequency = frequency }
        }
        
        fill(.duration) { draft.duration = suggestion.durationMinutes }
        // The day said ("amanhã", "sábado"): only when the chore asks for a date (daily chores
        // start today on their own) and the calendar would offer that day.
        if let date = suggestion.date, showsDateSection {
            let day = Calendar.current.startOfDay(for: date)
            if dateWindow.contains(day), day >= earliestSelectableDay {
                fill(.date) { selectedDate = day }
            }
        }
        if let priority = suggestion.priority {
            fill(.priority) { draft.priorityTag = priority }
        }

        let currentDescription = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if let details = suggestion.details,
           currentDescription.isEmpty || draft.description == suggestedDescription {
            draft.description = details
            suggestedDescription = details
        }
        // Steps the person listed go straight into the checklist.
        if !suggestion.steps.isEmpty {
            applyChecklistSteps(suggestion.steps)
        }

        if let people = suggestion.responsibleUsers {
            let picked = people.compactMap { person in
                selectableResponsibleUsers.first { candidate in
                    (candidate.recordID != nil && candidate.recordID == person.recordID)
                        || candidate.ownerRecordName == person.ownerRecordName
                }
            }
            if !picked.isEmpty {
                fill(.responsible) { draft.responsibleUsers = picked }
            }
        }
    }

    // MARK: Repeated chores

    /// An existing chore the new one seems to repeat, checked before going to the second step.
    /// Exact names (ignoring case, accents and small words) count right away; similar ones are
    /// confirmed by the on-device model when it's available. Chores in another room never count
    /// ("Limpar o chão" of the kitchen and of the living room are different chores).
    func existingDuplicate() async -> ChoreModel? {
        guard mode == .create else { return nil }
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let roomID = draft.room?.recordID
        let sameRoom = carouselViewModel.cardModels.filter { chore in
            guard let roomID, let choreRoom = chore.roomReference?.recordID else { return true }
            return choreRoom == roomID
        }

        for candidate in ChoreDuplicateFinder.candidates(for: name, in: sameRoom) {
            if ChoreDuplicateFinder.isExactMatch(name, candidate.name) { return candidate }
            if await IntelligenceManager.shared.isSameChore(name, as: candidate.name) == true {
                return candidate
            }
        }
        return nil
    }

    /// The chores screen's model, to open the existing chore's editor from the warning.
    var carouselForEditing: CarouselViewModel { carouselViewModel }

    /// "Cozinha · Semanal": where the existing chore is and how often, for the warning.
    func summary(of chore: ChoreModel) -> String {
        var parts: [String] = []
        if let room = carouselViewModel.getRoom(for: chore) {
            parts.append(room.name.localizedDefault)
        }
        if chore.frequency != .undefined {
            parts.append(chore.frequency.displayName.prefix(1).uppercased() + chore.frequency.displayName.dropFirst())
        }
        return parts.joined(separator: " · ")
    }

    /// Whether `field` still holds the AI's value; the form shows sparkles next to it.
    func isSuggested(_ field: SuggestedField) -> Bool {
        suggestedFields.contains(field)
    }

    /// Called when the person picks a value by hand, so a later description leaves it alone.
    func markChosenByHand(_ field: SuggestedField) {
        suggestedFields.remove(field)
        handPickedFields.insert(field)
    }
    
    // MARK: - Init
    
    /// - Parameters:
    ///   - originalModel: The chore to edit, or a new unsaved one to create.
    ///   - availableHouseUsers: The house members.
    ///   - carouselViewModel: The chores screen's view model.
    ///   - targetAssignments: The occurrence(s) the form was opened for, if any.
    ///   - cloudKit: Saves and deletes in CloudKit.
    ///   - scoreManager: Gives points.
    ///   - now: Gives the current date.
    init(
        originalModel: ChoreModel,
        availableHouseUsers: [UserModel],
        carouselViewModel: CarouselViewModel,
        targetAssignments: [RecurrentAssignmentModel] = [],
        cloudKit: CloudKitManager = .shared,
        scoreManager: ScoreManager = .shared,
        now: @escaping () -> Date = { Date() }
    ) {
        self.originalModel = originalModel
        self.targetAssignments = targetAssignments
        self.carouselViewModel = carouselViewModel
        self.cloudKit = cloudKit
        self.scoreManager = scoreManager
        self.now = now
        self.mode = originalModel.recordID == nil ? .create : .edit
        self.availableHouseUsers = Self.uniqueByOwner(availableHouseUsers)
        self.draft = ChoreDTO(from: originalModel, users: [], checklist: [], room: nil)
        Self.replaceUndefinedTags(in: draft)
        fillFromMemory()
    }
    
    // MARK: - Derived state
    
    /// Only an existing chore can be deleted.
    var showsDeleteButton: Bool {
        mode == .edit
    }
    
    /// Whether the name has any text.
    var hasValidName: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    /// Whether a room was picked.
    var hasRoom: Bool {
        draft.room != nil
    }
    
    /// Whether the chore has the date it needs (daily chores and edits don't need one).
    var hasDate: Bool {
        mode == .edit || draft.frequency == .daily || selectedDate != nil
    }
    
    /// Whether the "Confirmar" button is enabled.
    var canConfirm: Bool {
        isLoaded && hasValidName && hasRoom && hasDate && !isSaving && !isDeleting
    }
    
    /// Whether to warn that a room is missing.
    var showsMissingRoomWarning: Bool {
        isLoaded && hasValidName && !hasRoom
    }
    
    /// Whether to warn that a date is missing.
    var showsMissingDateWarning: Bool {
        isLoaded && hasValidName && hasRoom && !hasDate
    }
    
    /// Daily chores don't ask for a date.
    var showsDateSection: Bool {
        draft.frequency != .daily
    }
    
    /// Today: the calendar can't go before it.
    var earliestSelectableDay: Date {
        Calendar.current.startOfDay(for: now())
    }
    
    /// Members who can be picked as responsible: everyone for a public chore, only the user for a private one.
    var selectableResponsibleUsers: [UserModel] {
        guard !draft.isPublic else { return availableHouseUsers }
        return currentHouseUserInList.map { [$0] } ?? []
    }
    
    /// Days the calendar shows
    var dateWindow: Range<Date> {
        let calendar = Calendar.current
        
        if draft.frequency == .weekly {
            if let anchor = targetAssignments.first?.day {
                return Self.weekRange(containing: anchor, calendar: calendar)
            }
            if mode == .create {
                return Self.weekRange(containing: now(), calendar: calendar)
            }
        }
        
        return carouselViewModel.cycleWindow ?? carouselViewModel.pickerWindow
    }
    
    /// How busy `day` is, used to shade the calendar.
    func loadOpacity(on day: Date) -> Double {
        carouselViewModel.loadOpacity(on: day, in: dateWindow)
    }
    
    /// The signed-in member as found in ``availableHouseUsers``.
    private var currentHouseUserInList: UserModel? {
        guard let myID = currentHouseUser?.recordID else { return nil }
        return availableHouseUsers.first { $0.recordID == myID } ?? currentHouseUser
    }
    
    /// Who takes the occurrences generated for a new recurring chore.
    private var responsibleUsersForScheduling: [UserModel] {
        draft.isPublic ? draft.responsibleUsers : (currentHouseUserInList.map { [$0] } ?? [])
    }
    
    // MARK: - Loading
    
    /// Rebuilds the draft from what is persisted and loads everything the form needs.
    func load() async {
        isLoaded = false
        fillFromMemory()
        
        if availableRooms.isEmpty {
            availableRooms = await cloudKit.fetchAll(RoomModel.self).filter { $0.name != "Casa" }
        }
        if currentHouseUser == nil {
            currentHouseUser = await cloudKit.currentHouseUser()
        }
        if draft.room == nil, originalModel.roomReference != nil {
            draft.room = await originalModel.room
        }
        
        draft.responsibleUsers = persistedResponsibleUsers()
        
        let checklistModels = await originalModel.checkList
        draft.checklist = checklistModels.map(CheckItemDTO.init(from:))
        if draft.checklist.isEmpty {
            draft.checklist.append(CheckItemDTO(name: "", isDone: false))
        }
        draft.hasChecklist = true
        
        isLoaded = true
    }
    
    /// Fills the room, the rooms list, the current resident, the responsible users and the date
    /// from what ``CarouselViewModel`` already holds
    private func fillFromMemory() {
        availableRooms = carouselViewModel.roomModels.filter { $0.name != "Casa" }
        currentHouseUser = carouselViewModel.dashboardUser
        draft.room = carouselViewModel.getRoom(for: originalModel)
        selectedDate = targetAssignments.first?.day ?? originalModel.dueDate
        applyResponsibleUsers()
    }
    
    /// The persisted responsible users, or only the current resident for a private chore.
    private func applyResponsibleUsers() {
        draft.responsibleUsers = draft.isPublic
        ? persistedResponsibleUsers()
        : (currentHouseUserInList.map { [$0] } ?? [])
    }
    
    /// The responsible users stored on the occurrence(s) being edited, or on the chore.
    private func persistedResponsibleUsers() -> [UserModel] {
        var userIDs = Set<CKRecord.ID>()
        
        if let target = targetAssignments.first {
            if let refs = target.userReferences {
                userIDs.formUnion(refs.map(\.recordID))
                return availableHouseUsers.filter { user in
                    guard let id = user.recordID else { return false }
                    return userIDs.contains(id)
                }
            }
        }
        
        if let refs = originalModel.allResponsibleUsersReference {
            userIDs.formUnion(refs.map(\.recordID))
        }
        
        return availableHouseUsers.filter { user in
            guard let id = user.recordID else { return false }
            return userIDs.contains(id)
        }
    }
    
    // MARK: - Form events
    
    /// The calendar window changes with the frequency; reset selection rule per target frequency.
    func frequencyDidChange() {
        if draft.frequency == .daily {
            // Changing to .daily always starts from today
            selectedDate = Calendar.current.startOfDay(for: now())
        } else if let date = selectedDate {
            let day = Calendar.current.startOfDay(for: date)
            if !dateWindow.contains(day) || day < earliestSelectableDay {
                selectedDate = nil
            }
        }
    }
    
    /// Turning a chore private hands it to the current resident alone.
    func visibilityDidChange(isPublic: Bool) {
        guard isLoaded, !isPublic else { return }
        draft.responsibleUsers = currentHouseUserInList.map { [$0] } ?? []
    }
    
    // MARK: - Confirm
    
    /// Saves the draft and runs everything a save implies.
    ///
    /// - Returns: `true` when the chore was saved and the screen can close. On failure the
    ///   chore is left untouched, ``alert`` explains why and the draft stays on screen.
    func confirm() async -> Bool {
        guard canConfirm else { return false }
        isSaving = true
        defer { isSaving = false }
        
        let isNewChore = mode == .create
        let cycleEnd = carouselViewModel.currentCycleEnd
        let previousFrequency = originalModel.frequency
        let frequencyChanged = !isNewChore && previousFrequency != draft.frequency
        
        do {
            try await originalModel.save(
                from: draft,
                pickedDate: selectedDate,
                targetAssignments: frequencyChanged ? [] : targetAssignments
            )
        } catch {
            alert = FormAlert(kind: .saveFailed, message: UserFacingError.message(for: error))
            return false
        }
        
        if isNewChore {
            await scheduleNewRecurringChore(
                originalModel,
                responsibleUsers: responsibleUsersForScheduling,
                cycleEnd: cycleEnd,
                pickedDate: selectedDate
            )
            await awardCreationScore()
        } else if frequencyChanged {
            await carouselViewModel.handleFrequencyChange(
                for: originalModel,
                from: previousFrequency,
                responsibleUsers: responsibleUsersForScheduling,
                pickedDate: selectedDate
            )
        } else if let target = targetAssignments.first {
            if let pickedDate = selectedDate {
                target.day = Calendar.current.startOfDay(for: pickedDate)
            }
            
            let selectedRefs = draft.responsibleUsers.compactMap { user -> CKRecord.Reference? in
                guard let id = user.recordID else { return nil }
                return CKRecord.Reference(recordID: id, action: .none)
            }
            target.userReferences = selectedRefs.isEmpty ? nil : selectedRefs
            
            await cloudKit.update(target)
        } else {
            await applyPickedDateToOccurrence(isNewChore: isNewChore)
        }
        
        let newOccurrenceIDs: Set<CKRecord.ID> = (isNewChore || frequencyChanged)
        ? Set((originalModel.dailyAssignmentsReference ?? []).map(\.recordID))
        : []
        
        await carouselViewModel.refreshAfterChoreUpdate()
        await syncCalendar(newOccurrenceIDs: newOccurrenceIDs, frequencyChanged: frequencyChanged)
        carouselViewModel.refreshVisible()
        
        return true
    }
    
    /// Gives the points for creating a chore (with a bonus when every detail is filled in).
    private func awardCreationScore() async {
        let score = draft.hasFullDetails
        ? ScoreValues.choreAdded.points + ScoreValues.choreCreatedWithFullDetails.points
        : ScoreValues.choreAdded.points
        _ = await scoreManager.assignScoreForMyUser(score: score)
    }
    
    /// Moves the chosen occurrence to the date picked in the form (weekly or rarer chores).
    ///
    /// When editing, the occurrence the form was opened for moves; for a new chore, the occurrence
    /// closest to the picked date does.
    private func applyPickedDateToOccurrence(isNewChore: Bool) async {
        switch draft.frequency {
        case .weekly, .fortnightly, .monthly: break
        default: return
        }
        
        guard let selectedDate else { return }
        let calendar = Calendar.current
        let picked = calendar.startOfDay(for: selectedDate)
        
        if let target = targetAssignments.first {
            guard !calendar.isDate(target.day, inSameDayAs: picked) else { return }
            
            target.day = picked
            await cloudKit.update(target)
            
        } else if isNewChore {
            let created = await originalModel.dailyAssignments
            
            guard let closest = created.min(by: {
                abs($0.day.timeIntervalSince(picked)) < abs($1.day.timeIntervalSince(picked))
            }) else { return }
            
            closest.day = picked
            await cloudKit.update(closest)
        }
    }
    
    /// Mirrors the saved chore (or the occurrences it touched) into the user's calendar.
    private func syncCalendar(newOccurrenceIDs: Set<CKRecord.ID>, frequencyChanged: Bool) async {
        let chore = originalModel
        
        guard chore.frequency != .none else {
            await carouselViewModel.syncSingleChoreToCalendar(chore)
            return
        }
        
        let freshAssignments = await cloudKit.fetchAll(RecurrentAssignmentModel.self)
        carouselViewModel.dailyAssignments = freshAssignments
        
        // When frequency changed, targetAssignments were wiped — use newOccurrenceIDs instead
        let targetIDs = frequencyChanged
        ? newOccurrenceIDs
        : Set(targetAssignments.compactMap(\.recordID)).union(newOccurrenceIDs)
        
        let updatedTargets = freshAssignments.filter { assignment in
            guard let id = assignment.recordID else { return false }
            return targetIDs.contains(id)
        }
        
        for assignment in updatedTargets {
            await carouselViewModel.syncSingleAssignmentToCalendar(for: assignment, chore: chore)
        }
    }
    
    // MARK: - Delete
    
    /// Deletes the chore — or, when it's recurring, just the occurrence(s) this screen was
    /// opened for.
    ///
    /// - Returns: `true` when the screen can close. On failure ``alert`` explains why.
    func delete() async -> Bool {
        guard mode == .edit, !isSaving, !isDeleting else { return false }
        isDeleting = true
        defer { isDeleting = false }
        
        let success = await carouselViewModel.delete(chore: originalModel, targetOccurrences: targetAssignments)
        
        if !success {
            alert = FormAlert(
                kind: .deleteFailed,
                message: carouselViewModel.errorMessage ?? L10n.tr("Não foi possível excluir a tarefa.")
            )
            carouselViewModel.errorMessage = nil
        }
        
        return success
    }
    
    // MARK: - Helpers
    
    /// `undefined` is never shown: tags not chosen yet start at the first option of each picker.
    static func replaceUndefinedTags(in draft: ChoreDTO) {
        if draft.priorityTag == .undefined {
            draft.priorityTag = PriorityTag.allCases.first { $0 != .undefined } ?? .low
        }
        if draft.frequency == .undefined {
            draft.frequency = Recurrence.allCases.first { $0 != .undefined } ?? Recurrence.none
        }
        if draft.duration <= 0 {
            draft.duration = ChoreDurationTier.quick.minutes
        }
    }
    
    /// Keeps one `UserModel` per person.
    ///
    /// Onboarding can leave two records for the same owner (the profile created before a house
    /// existed, plus its in-house copy); the in-house one wins.
    static func uniqueByOwner(_ users: [UserModel]) -> [UserModel] {
        var bestByOwner: [String: UserModel] = [:]
        var order: [String] = []
        
        for user in users {
            let key = user.ownerRecordName
            if let existing = bestByOwner[key] {
                if existing.houseReference == nil && user.houseReference != nil {
                    bestByOwner[key] = user
                }
            } else {
                bestByOwner[key] = user
                order.append(key)
            }
        }
        
        // Keeps the incoming order, so avatars don't shuffle between openings.
        return order.compactMap { bestByOwner[$0] }
    }
    
    /// The calendar week (per `calendar`'s first weekday) that contains `date`.
    static func weekRange(containing date: Date, calendar: Calendar) -> Range<Date> {
        let startOfWeek = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        ) ?? calendar.startOfDay(for: date)
        let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek) ?? startOfWeek
        return startOfWeek..<endOfWeek
    }
}
