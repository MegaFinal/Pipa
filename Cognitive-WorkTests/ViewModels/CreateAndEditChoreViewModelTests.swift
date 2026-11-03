//
//  CreateAndEditChoreViewModelTests.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 29/09/26.
//

import Testing
import Foundation
import CloudKit
@testable import Cognitive_Work

/// Rules of the create/edit chore form that don't need CloudKit.
@MainActor
struct CreateAndEditChoreViewModelTests {
    
    // MARK: - Fixtures
    
    private func makeChore(recordName: String? = nil) -> ChoreModel {
        let chore = ChoreModel(
            name: "Lavar a louça",
            description: "Secar e guardar",
            frequency: .weekly,
            duration: 30,
            isPublic: true,
            priorityTag: .medium
        )
        chore.recordID = recordName.map { CKRecord.ID(recordName: $0) }
        return chore
    }
    
    private func makeUser(_ recordName: String, owner: String, inHouse: Bool) -> UserModel {
        UserModel(
            name: recordName,
            tier: .tier1,
            house: inHouse ? CKRecord.Reference(recordID: CKRecord.ID(recordName: "house"), action: .none) : nil,
            recordID: CKRecord.ID(recordName: recordName),
            ownerRecordName: owner
        )
    }
    
    private func makeViewModel(
        chore: ChoreModel? = nil,
        users: [UserModel] = [],
        now: Date = Date()
    ) -> CreateAndEditChoreViewModel {
        CreateAndEditChoreViewModel(
            originalModel: chore ?? makeChore(),
            availableHouseUsers: users,
            carouselViewModel: CarouselViewModel(),
            now: { now }
        )
    }
    
    // MARK: - Draft isolation (bug: unconfirmed edits showing up as saved)
    
    @Test func editingTheDraftNeverTouchesTheModel() {
        let chore = makeChore(recordName: "chore")
        let viewModel = makeViewModel(chore: chore)
        
        viewModel.draft.name = "Outro nome"
        viewModel.draft.priorityTag = .urgent
        viewModel.draft.isPublic = false
        
        #expect(chore.name == "Lavar a louça")
        #expect(chore.priorityTag == .medium)
        #expect(chore.isPublic)
    }
    
    @Test func confirmIsRefusedBeforeLoadingAndLeavesTheModelUntouched() async {
        let chore = makeChore(recordName: "chore")
        let viewModel = makeViewModel(chore: chore)
        viewModel.draft.name = "Outro nome"
        
        let saved = await viewModel.confirm()
        
        #expect(!saved)
        #expect(!viewModel.canConfirm)
        #expect(chore.name == "Lavar a louça")
    }
    
    @Test func saveWithoutRoomThrowsAndLeavesTheModelUntouched() async {
        let chore = makeChore()
        let draft = ChoreDTO(from: chore, users: [], checklist: [])
        draft.name = "Sem cômodo"
        
        await #expect(throws: ChoreSaveError.self) {
            try await chore.save(from: draft)
        }
        #expect(chore.name == "Lavar a louça")
        #expect(chore.recordID == nil)
    }
    
    // MARK: - Validation (bug: chores without a room)
    
    @Test func roomIsRequired() {
        let viewModel = makeViewModel()
        viewModel.draft.name = "Nome"
        
        #expect(viewModel.hasValidName)
        #expect(!viewModel.hasRoom)
        #expect(!viewModel.canConfirm)
    }
    
    @Test func whitespaceOnlyNameIsInvalid() {
        let viewModel = makeViewModel()
        viewModel.draft.name = "   \n"
        
        #expect(!viewModel.hasValidName)
    }
    
    @Test func missingRoomWarningWaitsForLoading() {
        let viewModel = makeViewModel()
        viewModel.draft.name = "Nome"
        
        #expect(!viewModel.showsMissingRoomWarning)
    }
    
    // MARK: - Mode
    
    @Test func creatingHidesTheDeleteButton() {
        let viewModel = makeViewModel(chore: makeChore())
        
        #expect(viewModel.mode == .create)
        #expect(!viewModel.showsDeleteButton)
    }
    
    @Test func editingShowsTheDeleteButton() {
        let viewModel = makeViewModel(chore: makeChore(recordName: "chore"))
        
        #expect(viewModel.mode == .edit)
        #expect(viewModel.showsDeleteButton)
    }
    
    // MARK: - Private chores
    
    @Test func privateChoreIsHiddenFromOtherResidents() {
        let me = CKRecord.ID(recordName: "me")
        let other = CKRecord.ID(recordName: "other")
        let chore = makeChore()
        chore.isPublic = false
        chore.currentResponsibleReference = CKRecord.Reference(recordID: me, action: .none)
        
        #expect(chore.isVisible(viewerIDs: [me], otherResidentIDs: [other]))
        #expect(!chore.isVisible(viewerIDs: [other], otherResidentIDs: [me]))
    }
    
    @Test func privateChoreWithUnmatchedOwnerStaysVisible() {
        let chore = makeChore()
        chore.isPublic = false
        chore.allResponsibleUsersReference = [CKRecord.Reference(recordID: CKRecord.ID(recordName: "old-copy"), action: .none)]
        
        #expect(chore.isVisible(viewerIDs: [CKRecord.ID(recordName: "me")], otherResidentIDs: [CKRecord.ID(recordName: "other")]))
    }
    
    @Test func publicAndLegacyPrivateChoresAreVisibleToEveryone() {
        let viewer = CKRecord.ID(recordName: "viewer")
        let publicChore = makeChore()
        let legacyPrivate = makeChore()
        legacyPrivate.isPublic = false
        
        #expect(publicChore.isVisible(viewerIDs: [], otherResidentIDs: [viewer]))
        #expect(legacyPrivate.isVisible(viewerIDs: [], otherResidentIDs: [viewer]))
    }
    
    @Test func newChoreStartsAtTheFirstOptionOfEachPicker() {
        let newChore = ChoreModel(name: "", description: "", frequency: .undefined, duration: 0, isPublic: true, priorityTag: .undefined)
        let viewModel = makeViewModel(chore: newChore)
        
        #expect(viewModel.draft.priorityTag == .low)
        #expect(viewModel.draft.frequency == Recurrence.none)
        #expect(ChoreDurationTier.from(minutes: viewModel.draft.duration) == .quick)
    }
    
    @Test func longDurationIsNeverUndefined() {
        #expect(ChoreDurationTier.from(minutes: 120) == .verySlow)
    }
    
    @Test func turningPrivateBeforeLoadingDoesNotTouchResponsibles() {
        let user = makeUser("u1", owner: "o1", inHouse: true)
        let viewModel = makeViewModel(users: [user])
        viewModel.draft.responsibleUsers = [user]
        
        viewModel.visibilityDidChange(isPublic: false)
        
        #expect(viewModel.draft.responsibleUsers.count == 1)
    }
    
    // MARK: - Form events
    
    @Test func turningTheChecklistOnAddsASingleEmptyRow() {
        let viewModel = makeViewModel()
        
        viewModel.checklistToggleDidChange(isOn: true)
        viewModel.checklistToggleDidChange(isOn: true)
        
        #expect(viewModel.draft.checklist.count == 1)
        #expect(viewModel.draft.checklist.first?.name == "")
    }
    
    @Test func frequencyChangeDropsAPastDate() {
        let viewModel = makeViewModel()
        viewModel.selectedDate = Calendar.current.date(byAdding: .day, value: -3, to: Date())
        
        viewModel.frequencyDidChange()
        
        #expect(viewModel.selectedDate == nil)
    }
    
    @Test func weeklyCreationShowsTheCurrentWeek() {
        let now = Date()
        let viewModel = makeViewModel(now: now)
        viewModel.draft.frequency = .weekly
        
        let window = viewModel.dateWindow
        
        #expect(window.contains(now))
        #expect(Calendar.current.dateComponents([.day], from: window.lowerBound, to: window.upperBound).day == 7)
    }
    
    @Test func deletingAChoreThatWasNeverSavedIsRefused() async {
        let viewModel = makeViewModel()
        
        #expect(await viewModel.delete() == false)
    }
    
    // MARK: - Helpers
    
    @Test func duplicateUsersKeepTheInHouseCopyAndTheirOrder() {
        let profileCopy = makeUser("profile", owner: "ana", inHouse: false)
        let houseCopy = makeUser("house-copy", owner: "ana", inHouse: true)
        let bruno = makeUser("bruno", owner: "bruno", inHouse: true)
        
        let unique = CreateAndEditChoreViewModel.uniqueByOwner([profileCopy, bruno, houseCopy])
        
        #expect(unique.map { $0.recordID?.recordName } == ["house-copy", "bruno"])
    }
    
    @Test func fullDetailsRequireEveryOptionalField() {
        let draft = ChoreDTO(from: makeChore(), users: [], checklist: [])
        #expect(!draft.hasFullDetails) // no room yet
        
        draft.description = "   "
        #expect(!draft.hasFullDetails)
    }
    
    // MARK: - Date
    
    @Test func newChoreNeedsADate() {
        let viewModel = makeViewModel()
        viewModel.draft.frequency = .weekly
        viewModel.selectedDate = nil
        
        #expect(!viewModel.hasDate)
        #expect(!viewModel.canConfirm)
    }
    
    @Test func dailyChoreCountsAsDated() {
        let viewModel = makeViewModel()
        viewModel.draft.frequency = .daily
        viewModel.selectedDate = nil
        
        #expect(viewModel.hasDate)
    }
    
    @Test func editingDoesNotRequireADate() {
        let viewModel = makeViewModel(chore: makeChore(recordName: "chore"))
        viewModel.selectedDate = nil
        
        #expect(viewModel.hasDate)
    }
    
    @Test func savingANewChoreWithoutDateIsRefused() async {
        let chore = makeChore()
        let draft = ChoreDTO(from: chore, users: [], checklist: [])
        draft.roomReference = CKRecord.Reference(recordID: CKRecord.ID(recordName: "room"), action: .none)
        
        do {
            try await chore.save(from: draft)
            Issue.record("save should have thrown")
        } catch ChoreSaveError.missingDate {
        } catch {
            Issue.record("unexpected error: \(error)")
        }
        #expect(chore.recordID == nil)
    }
}
