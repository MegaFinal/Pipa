//
//  OnboardingViewModel.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 19/08/26.
//

import SwiftUI
import CloudKit

/// The shared state and business logic for the entire onboarding flow.
///
/// `OnboardingViewModel` is created once by ``Onboarding`` and passed to every step,
/// so every onboarding screen reads and changes the same instance.
///
/// It owns:
/// - Navigation flags that drive `navigationDestination` pushes between steps
/// - The in-progress ``currentUser`` and ``currentHouse`` CloudKit records
/// - The list of candidate rooms (``availableRooms``) offered during room selection
/// - Loading/error state surfaced by the various onboarding screens
@Observable
class OnboardingViewModel {
    /// The name entered by the user for their profile
    var userName: String = ""
    
    /// The picture picked for the profile being created.
    var userProfilePicture: UIImage?
    /// Banner picked for the profile being created.
    var userBanner: ProfileBanner = .default
    /// The name of the house being created
    var houseName: String = L10n.tr("Minha Casa")
    /// A short description of the house being created
    var houseDescription: String = L10n.tr("Organização Doméstica")
    
    /// Whether an asynchronous CloudKit operation is currently in progress
    var isLoading: Bool = false
    /// `true` while checking whether the iCloud account already has a profile.
    var isCheckingAccount: Bool = true
    /// A message describing the most recent error, if any
    var errorMessage: String? = nil

    /// Set when free time was saved on the private profile but could not be written to the house
    /// profile yet. Not an error: the save succeeded and the sync is retried automatically. The
    /// free-time screen shows it before moving on.
    var freeTimeSyncWarning: String? = nil

    /// Which onboarding step is showing, saved across launches.
    var stateMachine = OnboardingStateMachine()
    
    /// `true` once the onboarding finished; the root view then shows the main tabs.
    var isOnboardingSkipped: Bool = false
    /// The CloudKit user record created during onboarding
    var currentUser: UserModel?
    /// The CloudKit house record created during onboarding
    var currentHouse: HouseModel?
    
    /// The default set of room choices offered to the user, including the trailing "add custom room" entry
    var availableRooms: [RoomDTO] = DefaultRoomsOnboarding.onboardingOrder.map(\.roomDTO) + [
        RoomDTO(name: "Outro", symbol: "plus", isAddButton: true, color: .purple)
    ]
    
    /// Whether at least one room is selected.
    var hasSelectedRooms: Bool {
        availableRooms.contains { $0.isSelected && !$0.isAddButton }
    }
    
    /// The chores picked on the chores step.
    var selectedChores: [ChoreDTO] = []
    
    /// `true` once the first division of chores exists.
    var isScheduleReady: Bool = false

    /// True while the invited user is being added to the house. Separate from ``isLoading`` so
    /// the screen can tell "joining" from "creating" a house.
    private(set) var isJoiningHouse = false
    
    /// True from the moment an invite link is opened until the house is joined (or it fails).
    /// Covers the share acceptance, which runs *before* ``joinHouse()`` and takes a few seconds.
    var isAcceptingInvite = false
    
    /// `true` while checking whether the division exists, so checks don't overlap.
    private var isCheckingSchedule = false
    
    /// `true` while the previous session (step, house, profile) is being restored at launch.
    var isRestoringSession: Bool = true
    
    // MARK: - Going back
    
    /// True while a "voltar" is deleting the data of the step being returned to.
    private(set) var isRollingBack = false
    
    /// Why the last "voltar" failed. The user stays on the current step when it is set.
    var rollbackErrorMessage: String?
    
    /// What each step saved to CloudKit, so going back deletes exactly that.
    /// See ``OnboardingRollbackJournal``.
    @ObservationIgnored
    private var rollbackJournal = OnboardingRollbackJournal.load() {
        didSet { rollbackJournal.save() }
    }
    
    // MARK: - Free time sync

    /// The free time sync service, created on first use.
    @ObservationIgnored
    private var freeTimeSyncStorage: FreeTimeSyncService?

    /// Keeps free time on both the private profile and the in-house profile.
    /// See the documentation in `FreeTimeSyncService.swift`.
    private var freeTimeSync: FreeTimeSyncService {
        if let freeTimeSyncStorage { return freeTimeSyncStorage }
        let service = FreeTimeSyncService.live(publicStoreProvider: { [weak self] in
            await self?.houseFreeTimeStore()
        })
        freeTimeSyncStorage = service
        return service
    }

    // MARK: - CloudKit
    /// Creates the user's profile record in CloudKit and advances to the "join or create a house" step
    ///
    /// Uses ``userName`` (falling back to a default name if empty) to build a new
    /// `UserModel`. On success, stores the saved record in ``currentUser`` and sets
    /// ``navigateToThird`` to `true`. On failure, populates ``errorMessage``.
    @MainActor
    func createUser() async {
        isLoading = true
        errorMessage = nil
        
        let imageCKAsset = userProfilePicture?
            .jpegData(compressionQuality: 0.8)
            .flatMap { CloudKitManager.shared.createAsset(from: $0) }
        
        // A private profile that wasn't created in this onboarding (an account from an earlier
        // run) is kept when the user goes back to this step, so edit it instead of saving a
        // duplicate profile.
        if let existingProfile = currentUser,
           existingProfile.recordID != nil,
           !CloudKitManager.shared.isHouseUser(existingProfile) {
            existingProfile.name = userName.isEmpty ? existingProfile.name : userName
            if let imageCKAsset { existingProfile.profilePicture = imageCKAsset }
            existingProfile.banner = userBanner
            
            if await CloudKitManager.shared.update(existingProfile) {
                stateMachine.user = existingProfile
            } else {
                errorMessage = CloudKitManager.shared.errorMessage ?? L10n.tr("Erro ao criar usuário.")
            }
            isLoading = false
            return
        }
        
        if let ownerRecordName = await CloudKitManager.shared.fetchCurrentUserRecordID()?.recordName {
            let newUser = UserModel(name: userName.isEmpty ? "Novo Morador" : userName, profilePicture: imageCKAsset, banner: userBanner, tier: .tier1, ownerRecordName: ownerRecordName)
            
            if let savedUser = await CloudKitManager.shared.create(newUser) {
                self.currentUser = savedUser
                self.stateMachine.user = savedUser
                CloudKitManager.shared.setCurrentUser(savedUser)
                rollbackJournal.createdProfile = savedUser.recordID.map(OnboardingRollbackJournal.StoredRecordID.init)
            } else {
                errorMessage = CloudKitManager.shared.errorMessage ?? L10n.tr("Erro ao criar usuário.")
            }
        } else {
            errorMessage = L10n.tr("Não foi possível acessar sua conta do iCloud. Verifique se você está conectado e tente novamente.")
        }
        isLoading = false
    }
    
    /// Updates the profile image with the image received from the keyboard.
    /// - Parameter image: The image selected by the user.
    func updateProfileImage(_ image: UIImage) {
        userProfilePicture = image
    }
    
    /// Creates a new house record and links the current user to it, then advances to room selection
    ///
    /// - Requires ``currentUser`` to already be set (created via ``createUser()``)
    /// - Creates a new `HouseModel` referencing the user, saves it, sets it as the
    /// user record's CloudKit parent, and updates the user record
    /// - On success, stores the saved house in ``currentHouse`` and sets ``navigateToFourth`` to `true`
    /// - On failure, populates ``errorMessage``
    @MainActor
    func createHouseAndLinkUser() async {
        if currentUser == nil {
            await fetchCurrentUser()
        }
        
        guard let user = currentUser, let userRecordID = user.recordID else {
            errorMessage = L10n.tr("Seu perfil ainda não foi salvo. Volte e crie o perfil antes de criar a casa.")
            return
        }
         
        isLoading = true
        errorMessage = nil
         
        // Clears the spinner on *every* exit, including the early returns below. Without it,
        // any of those returns leaves the button spinning forever with no way out.
        defer { isLoading = false }
         
        // Pre-compute the house's recordID and zoneID locally to avoid a sequential network round-trip.
        let zoneID = CloudKitManager.shared.houseZoneID
        let houseRecordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID)
        let houseCascadeRef = CKRecord.Reference(recordID: houseRecordID, action: .none)
        
        // Pre-compute the shopping list's recordID too, so the house record can point at it
        // from the start.
        let shopListRecordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID)
        let shopListReference = CKRecord.Reference(recordID: shopListRecordID, action: .none)
        
        // Construct the HouseModel and its underlying CKRecord.
        let userReference = CKRecord.Reference(recordID: userRecordID, action: .none)
        let newHouse = HouseModel(name: houseName, description: houseDescription, users: [userReference], shopList: shopListReference)
        let houseRecord = CKRecord(recordType: HouseModel.recordType, recordID: houseRecordID)
        newHouse.populate(record: houseRecord)
        
        // Construct the house's shopping list and its underlying CKRecord.
        let shopList = ShopListModel(name: "Lista de compras", house: houseCascadeRef, recordID: shopListRecordID)
        let shopListRecord = CKRecord(recordType: ShopListModel.recordType, recordID: shopListRecordID)
        shopList.populate(record: shopListRecord)
        shopListRecord.parent = houseCascadeRef
         
        // Prepare the user copy record and map all properties.
        let assetCopy = user.profilePicture.flatMap { try? duplicateCKAsset($0) }
        let ownerRecordName = await CloudKitManager.shared.fetchCurrentUserRecordID()?.recordName ?? "error to fetch users id"
         
        let userCopy = UserModel(
            name: user.name,
            profilePicture: assetCopy,
            banner: user.banner,
            // Points (and the rank) live in the house's `UserScoreModel`, not on the user.
            tier: .novatoDaCasa,
            coins: user.coins,
            badges: user.badgesReference,
            tasks: user.choresReference,
            // Free time is no longer copied from the private profile: those records live outside
            // the house hierarchy. It is written straight to this copy by
            // `flushPendingFreeTimeIfNeeded()` below.
            house: houseCascadeRef,
            coupons: user.couponsReference,
            couponLimit: user.couponLimit,
            ownerRecordName: ownerRecordName
        )
         
        let copyRecordID = CloudKitManager.shared.houseUserRecordID(
            for: userRecordID,
            inHouseZone: zoneID
        )
        let userCopyRecord = CKRecord(recordType: UserModel.recordType, recordID: copyRecordID)
        userCopy.populate(record: userCopyRecord)
        userCopyRecord.parent = houseCascadeRef
         
        // `.allKeys`: the in-house copy has a deterministic recordID (profile name + "-house").
        // If an earlier house was deleted, or creation is retried, that record already exists
        // and the default policy rejected the whole batch with serverRecordChanged.
        let success = await CloudKitManager.shared.batchSave(
            records: [houseRecord, userCopyRecord, shopListRecord],
            zoneID: zoneID,
            savePolicy: .allKeys
        )
         
        if success {
            rollbackJournal.createdHouse = OnboardingRollbackJournal.StoredRecordID(houseRecordID)
            let savedHouse = HouseModel(record: houseRecord)
            self.currentHouse = savedHouse
            self.stateMachine.house = savedHouse
             
            let savedUserCopy = UserModel(record: userCopyRecord)
            self.currentUser = savedUserCopy
            self.stateMachine.user = savedUserCopy
             
            // Free time is now picked before the house exists; persist it on the in-house copy.
            await flushPendingFreeTimeIfNeeded()
            
            try? await CloudKitManager.shared.createSharedSubscription()
        } else {
            errorMessage = CloudKitManager.shared.errorMessage ?? L10n.tr("Erro ao criar a casa.")
        }
    }
    
    // MARK: - Fourth View
    /// Toggles the selection state of the room dto with the given identifier
    ///
    /// - Parameter id: The `RoomDTO.id` of the room to toggle
    func toggleRoomSelection(id: UUID) {
        if let index = availableRooms.firstIndex(where: { $0.id == id }) {
            availableRooms[index].isSelected.toggle()
        }
    }
    
    /// Inserts a new, pre-selected custom room dto just before the "add room" entry
    ///
    /// - Parameters:
    ///   - name: The display name for the new room
    ///   - color: The accent color chosen for the new room
    ///   - symbol: The SF Symbol chosen for the new room
    ///   - pattern: The texture chosen for the new room
    func addCustomRoom(
        name: String,
        color: RoomColor,
        symbol: String = RoomsManagementViewModel.customRoomSymbol,
        pattern: RoomTexturePattern = .fallback
    ) {
        let newRoom = RoomDTO(name: name, symbol: symbol, isSelected: true, color: color, pattern: pattern)
        let otherButtonIndex = availableRooms.count - 1
        availableRooms.insert(newRoom, at: otherButtonIndex)
    }
    
    /// Persists all selected rooms to CloudKit as children of the current house
    ///
    /// Filters ``availableRooms`` down to selected, non-add-button drafts, creates a
    /// `RoomModel` for each under the current house, and appends the resulting
    /// references to the house's `rooms` list before saving the updated house.
    ///
    /// - On success, sets ``onboardingFinished`` to `true`.
    /// - Requires ``currentHouse`` to already be set.
    @MainActor
    func saveSelectedRooms() async {
        errorMessage = nil
        guard let house = currentHouse,
              let zoneID = house.recordID?.zoneID else {
            errorMessage = L10n.tr("Não foi possível encontrar sua casa. Tente novamente.")
            return
        }
        isLoading = true
        
        let selectedDrafts = availableRooms.filter { $0.isSelected && !$0.isAddButton }
        let houseReference = house.reference(action: .deleteSelf)
        let parentReference = house.reference(action: .none)
        
        // One room per instance: a type set to 2 bedrooms saves "Quarto 1" and "Quarto 2" (or
        // whatever the user named them), all of kind "Quarto" so they get its default chores.
        var roomModels = selectedDrafts.flatMap { draft in
            draft.instances.indices.map { index in
                RoomModel(
                    name: draft.instanceName(at: index),
                    symbol: draft.symbol,
                    house: houseReference,
                    color: draft.color,
                    kind: draft.name,
                    pattern: draft.pattern
                )
            }
        }
        
        var recordsToSave: [CKRecord] = []
        for roomModel in roomModels {
            let record = CKRecord(recordType: RoomModel.recordType, zoneID: zoneID)
            roomModel.populate(record: record)
            
            record.parent = parentReference
            
            recordsToSave.append(record)
        }
        
        let successBatch = await CloudKitManager.shared.batchSave(records: recordsToSave, zoneID: zoneID)
        
        if successBatch {
            for (index, record) in recordsToSave.enumerated() {
                roomModels[index].recordID = record.recordID
            }
            rollbackJournal.createdRooms += recordsToSave.map { OnboardingRollbackJournal.StoredRecordID($0.recordID) }
            
            let successAppend = await house.appendRoom(rooms: roomModels)
            if successAppend {
                self.currentHouse = house
            } else {
                errorMessage = CloudKitManager.shared.errorMessage ?? L10n.tr("Erro ao atrelar cômodos.")
            }
        } else {
            errorMessage = CloudKitManager.shared.errorMessage ?? L10n.tr("Erro ao salvar cômodos.")
        }
        
        isLoading = false
    }
    
    /// Fetches every user currently linked to ``currentHouse``.
    ///
    /// Used to display the members who have already joined while the house owner
    /// waits on the invite screen.
    ///
    /// The query alone missed people who had just joined: CloudKit query indexes lag behind
    /// writes. So the result is merged with the house record's `users` list (re-read fresh by
    /// ID, which is immediately consistent — ``joinHouse()`` appends to it) and with this
    /// device's own in-house record.
    @MainActor
    func fetchHouseUsers() async -> [UserModel] {
        guard let houseID = currentHouse?.recordID else {
            return await CloudKitManager.shared.fetchHouseUsers(of: currentHouse)
        }
        
        async let queried = CloudKitManager.shared.fetchHouseUsers(of: currentHouse)
        async let freshHouse = CloudKitManager.shared.fetchRecordsByRecordReference(
            for: HouseModel.self,
            recordReferences: [CKRecord.Reference(recordID: houseID, action: .none)]
        )?.first
        
        var users = await queried
        var candidates: [UserModel] = []
        if let house = await freshHouse {
            candidates += await house.users
        }
        if let me = currentUser, CloudKitManager.shared.isHouseUser(me) {
            candidates.append(me)
        }
        
        for candidate in candidates
        where candidate.houseReference?.recordID == houseID
            && !users.contains(where: { $0.recordID == candidate.recordID || $0.ownerRecordName == candidate.ownerRecordName }) {
            users.append(candidate)
        }
        
        return users.sorted { ($0.recordID?.recordName ?? "") < ($1.recordID?.recordName ?? "") }
    }
    
    /// The rooms of the house being set up.
    @MainActor
    func fetchRooms() async -> [RoomModel] {
        guard let houseID = currentHouse?.recordID else { return [] }
        let reference = CKRecord.Reference(recordID: houseID, action: .deleteSelf)
        let predicate = NSPredicate(format: "house == %@", reference)
        return await CloudKitManager.shared.fetchAll(RoomModel.self, predicate: predicate)
    }
    
    /// Creates a `ChoreModel` for each chore the user selected, skipping any that
    /// another housemate already saved for the same room.
    ///
    /// Every resident walks through ``SelectChoresOnboardingView`` independently and picks
    /// from the same default chore list per room, so without this check the same chore would
    /// be duplicated once per person who selects it.
    func createDefaultChores() async {
        isLoading = true
        errorMessage = nil
        
        guard let rooms = currentHouse?.room,
              let houseRecordID = currentHouse?.recordID else {
            isLoading = false
            return
        }
        
        let zoneID = houseRecordID.zoneID
        let parentReference = CKRecord.Reference(recordID: houseRecordID, action: .none)
        
        let existingChores = await CloudKitManager.shared.fetchAll(
            ChoreModel.self,
            predicate: NSPredicate(format: "room != nil")
        )
        
        let existingSet = Set(existingChores.map {
            "\($0.roomReference?.recordID.recordName ?? "")_\($0.name)"
        })
        
        var recordsToCreate: [CKRecord] = []
        var couponRecords: [CKRecord] = []
        
        for choreDTO in selectedChores {
            // The room the chore was picked under (set on selection). Matching by name alone
            // no longer works once a type has several rooms ("Quarto 1", "Quarto 2") — the
            // chore's `roomDTO` only knows the type, "Quarto". Name is the fallback.
            let choreRoom = rooms.first(where: { $0.recordID == choreDTO.roomReference?.recordID })
                ?? rooms.first(where: { $0.name == choreDTO.roomDTO.name })
            
            guard let choreRoom, let roomRecordID = choreRoom.recordID else {
                continue
            }
            
            let roomReference = CKRecord.Reference(recordID: roomRecordID, action: .none)
            let uniqueKey = "\(roomRecordID.recordName)_\(choreDTO.name)"
            
            if existingSet.contains(uniqueKey) {
                continue
            }
            
            let choreModel = ChoreModel(
                name: choreDTO.name,
                description: choreDTO.description,
                frequency: choreDTO.frequency,
                duration: choreDTO.duration,
                isPublic: true,
                priorityTag: choreDTO.priorityTag,
                roomReference: roomReference
            )
            
            // `ChoreModel.init` flips a coin for `shouldBeIncluded` on monthly chores (it spreads
            // them over alternating 14-day divisions), which left about half of the monthly
            // chores picked here out of the first division. Everything the user selected in the
            // onboarding must enter it; the scheduler flips the flag afterwards, so the next
            // division is the one that skips them.
            choreModel.shouldBeIncluded = choreDTO.frequency == .monthly ? true : nil
            
            let record = CKRecord(recordType: ChoreModel.recordType, zoneID: zoneID)
            choreModel.populate(record: record)
            record.parent = parentReference
            
            recordsToCreate.append(record)
            
            // The chore's coupon, saved in the same batch. Its `task` reference deletes it
            // together with the chore, so the rollback journal only needs the chore.
            let coupon = CouponModel(for: choreModel, choreRecordID: record.recordID)
            let couponRecord = CKRecord(recordType: CouponModel.recordType, zoneID: zoneID)
            coupon.populate(record: couponRecord)
            couponRecord.parent = CKRecord.Reference(recordID: record.recordID, action: .none)
            couponRecords.append(couponRecord)
        }
        
        if !recordsToCreate.isEmpty {
            let success = await CloudKitManager.shared.batchSave(records: recordsToCreate + couponRecords, zoneID: zoneID)
            if success {
                rollbackJournal.createdChores += recordsToCreate.map { OnboardingRollbackJournal.StoredRecordID($0.recordID) }
            } else {
                errorMessage = CloudKitManager.shared.errorMessage ?? L10n.tr("Erro ao criar tarefas padrão.")
            }
        }
        
        isLoading = false
    }
    
    /// Moves to the next step.
    func goToNextView() {
        stateMachine.next()
    }
    
    /// Moves to the previous step (without undoing anything; see the "Going back" section).
    func goToPreviousView() {
        stateMachine.back()
    }
    
    // MARK: - Going back
    
    /// Returns to the previous onboarding step, first deleting from CloudKit whatever that step
    /// saved when the user left it.
    ///
    /// Leaving a step is what writes its data ("Continuar" creates the profile, the house, the
    /// rooms…). Returning to it means the user will submit it again, so its records are removed
    /// first — otherwise a second "Continuar" would leave duplicates behind. Only the records of
    /// the step being returned to are touched; earlier steps keep their data.
    ///
    /// If the cleanup fails the user stays on the current step and ``rollbackErrorMessage``
    /// explains why, so CloudKit and the screen never disagree.
    @MainActor
    func goBack() async {
        guard !isRollingBack, !isLoading, let target = stateMachine.previousStep else { return }
        
        isRollingBack = true
        isLoading = true
        rollbackErrorMessage = nil
        CloudKitManager.shared.errorMessage = nil
        defer {
            isRollingBack = false
            isLoading = false
        }
        
        guard await rollbackData(savedBy: target) else {
            rollbackErrorMessage = L10n.tr("Não foi possível desfazer esta etapa. Verifique sua conexão e tente novamente.")
            return
        }
        
        // Without its house, the creator is back to choosing between creating and joining one.
        let newFlow: NavigationFlowsOnboarding? =
            (target == .createOrEnterHome && stateMachine.flow == .houseCreator) ? .notDefined : nil
        stateMachine.back(to: target, switchingTo: newFlow)
    }
    
    /// Deletes what `step` saved to CloudKit when the user left it.
    ///
    /// - Returns: `true` when there was nothing to delete or everything was deleted.
    @MainActor
    private func rollbackData(savedBy step: OnboardingNavigationSteps) async -> Bool {
        switch step {
        case .createProfile:
            return await rollbackProfile()
        case .chooseFreeTime:
            return await rollbackFreeTime()
        case .createOrEnterHome:
            return await rollbackHouse()
        case .chooseRooms:
            return await rollbackRooms()
        case .chooseChores:
            return await rollbackChores()
        case .welcome, .waitAcceptLink, .inviteAndConfirmJoin, .setUpScheduleChores,
             .scheduleChores, .waitAdminScheduling, .waitGuestsFreeTime:
            // These steps only navigate; they don't write anything.
            return true
        }
    }
    
    /// Undoes "Criar perfil": the private profile and, for an invited user who joined right
    /// after creating it, their member record in the house.
    @MainActor
    private func rollbackProfile() async -> Bool {
        let manager = CloudKitManager.shared
        
        if let membershipID = rollbackJournal.joinedMembership?.recordID {
            // Unlink from the house first, so it never lists a member that no longer exists.
            if let house = await freshHouse(for: membershipID.zoneID),
               !(await house.removeUser(withID: membershipID)) {
                return false
            }
            guard await manager.delete(recordIDs: [membershipID], zoneID: membershipID.zoneID) else {
                return false
            }
            rollbackJournal.joinedMembership = nil
            manager.invalidateSessionCache()
        }
        
        if let profileID = rollbackJournal.createdProfile?.recordID {
            guard await manager.delete(recordIDs: [profileID], zoneID: profileID.zoneID) else {
                return false
            }
            rollbackJournal.createdProfile = nil
            manager.clearCurrentUser()
            currentUser = nil
            stateMachine.user = nil
        } else if let user = currentUser, manager.isHouseUser(user) {
            // A profile from an earlier run is kept (it is edited on "Continuar" instead); point
            // back at it now that the member record is gone.
            await fetchCurrentUser()
            stateMachine.user = currentUser
        }
        
        return true
    }
    
    /// Undoes "Selecionar tempo livre" when the slots were written to CloudKit (the user
    /// already belonged to a house). A choice still pending locally stays, so the sliders
    /// come back filled in.
    @MainActor
    private func rollbackFreeTime() async -> Bool {
        let recordIDs = rollbackJournal.freeTimeRecords.map(\.recordID)
        guard let zoneID = recordIDs.first?.zoneID else { return true }
        
        // Detach the slots from the member first: a reference to a deleted record would make
        // the owner's screen read stale availability.
        if let houseUser = currentUser, CloudKitManager.shared.isHouseUser(houseUser) {
            houseUser.availableTimeReference = []
            guard await CloudKitManager.shared.update(houseUser) else { return false }
        }
        guard await CloudKitManager.shared.delete(recordIDs: recordIDs, zoneID: zoneID) else {
            return false
        }
        
        rollbackJournal.freeTimeRecords = []
        if pendingFreeTimeMinutes == nil {
            pendingFreeTimeMinutes = rollbackJournal.lastFreeTimeMinutes
        }
        return true
    }
    
    /// Undoes "Criar uma casa": the house with its whole hierarchy (member copy, shopping list,
    /// availability, anything below it) and its share.
    ///
    /// Only for the house creator: joining a house through an invite creates nothing here.
    @MainActor
    private func rollbackHouse() async -> Bool {
        guard stateMachine.flow == .houseCreator else { return true }
        
        let manager = CloudKitManager.shared
        guard let houseID = rollbackJournal.createdHouse?.recordID
                ?? (stateMachine.isOwner == true ? currentHouse?.recordID : nil)
        else { return true }
        
        // The share isn't part of the parent hierarchy, so remove it explicitly. A missing
        // share (the invite was never prepared) is fine.
        if let house = currentHouse, house.recordID == houseID,
           let houseRecord = await manager.fetchRecord(for: house),
           let share = await manager.fetchShare(for: houseRecord) {
            guard await manager.delete(recordIDs: [share.recordID], zoneID: houseID.zoneID) else {
                return false
            }
        }
        
        guard await manager.deleteChildren(of: houseID, includingSelf: true) else { return false }
        manager.invalidateSessionCache()
        
        // Free time was written on the deleted member copy; keep it pending for the next house.
        if pendingFreeTimeMinutes == nil {
            pendingFreeTimeMinutes = rollbackJournal.lastFreeTimeMinutes
        }
        
        rollbackJournal.createdHouse = nil
        rollbackJournal.createdRooms = []
        rollbackJournal.createdChores = []
        rollbackJournal.freeTimeRecords = []
        
        currentHouse = nil
        stateMachine.house = nil
        selectedChores = []
        
        // `currentUser` was the in-house copy that was just deleted.
        await fetchCurrentUser()
        stateMachine.user = currentUser
        return true
    }
    
    /// Undoes "Definir os cômodos": the rooms that step created, and their references on the
    /// house. The room selection on screen is kept, so the user only adjusts it.
    @MainActor
    private func rollbackRooms() async -> Bool {
        var roomIDs = rollbackJournal.createdRooms.map(\.recordID)
        
        // Progress saved before the journal existed: at this point of the flow, every room in
        // the house was created by that step.
        if roomIDs.isEmpty, stateMachine.isOwner == true {
            roomIDs = await fetchRooms().compactMap(\.recordID)
        }
        guard let zoneID = roomIDs.first?.zoneID else { return true }
        
        if let house = await freshHouse(for: zoneID) ?? currentHouse {
            guard await house.removeRooms(withIDs: Set(roomIDs)) else { return false }
            currentHouse = house
            stateMachine.house = house
        }
        guard await CloudKitManager.shared.delete(recordIDs: roomIDs, zoneID: zoneID) else {
            return false
        }
        
        rollbackJournal.createdRooms = []
        // The marks pointed at the rooms that were just deleted.
        selectedChores = []
        return true
    }
    
    /// Undoes "Escolher tarefas": the chores that step created, together with the occurrences
    /// the division generated for them (children of each chore).
    ///
    /// Without this the step looked like it wrote nothing, so coming back and confirming again
    /// was a no-op for every chore that already existed (``createDefaultChores()`` skips them by
    /// room and name): a changed frequency was ignored and unmarked chores stayed in the house.
    @MainActor
    private func rollbackChores() async -> Bool {
        let choreIDs = rollbackJournal.createdChores.map(\.recordID)
        
        if let zoneID = choreIDs.first?.zoneID {
            guard await CloudKitManager.shared.delete(recordIDs: choreIDs, zoneID: zoneID) else {
                return false
            }
        }
        
        rollbackJournal.createdChores = []
        // The marks on screen are rebuilt from the defaults, so the old selection must go too.
        selectedChores = []
        return true
    }
    
    /// The house record re-read by ID (immediately consistent), when it lives in `zoneID`.
    @MainActor
    private func freshHouse(for zoneID: CKRecordZone.ID) async -> HouseModel? {
        guard let houseID = currentHouse?.recordID, houseID.zoneID == zoneID else { return nil }
        return await CloudKitManager.shared.fetchRecordsByRecordReference(
            for: HouseModel.self,
            recordReferences: [CKRecord.Reference(recordID: houseID, action: .none)]
        )?.first
    }
    
    /// Chores saved by the chores step of this onboarding. The division step fetches them by ID
    /// so the scheduler sees them even before CloudKit's query index catches up.
    var createdChoreRecordIDs: [CKRecord.ID] {
        rollbackJournal.createdChores.map(\.recordID)
    }
    
    /// Free time to show when the free-time step opens again: the pending choice, or the last
    /// one saved during this onboarding.
    var freeTimeToRestore: [Int]? {
        pendingFreeTimeMinutes ?? rollbackJournal.lastFreeTimeMinutes
    }
    
    /// Ends the onboarding and shows the main tabs.
    func finishOnboarding() {
        isOnboardingSkipped = true
        // `pendingFreeTimeMinutes` is deliberately kept: it is only set while the house profile
        // does not have the free time yet, and `FreeTimeSyncService.reconcile()` (run when the
        // main screen opens) finishes the job if the write during onboarding failed.
        stateMachine.resetProgress()
        rollbackJournal = OnboardingRollbackJournal()
        OnboardingRollbackJournal.clear()
    }
    
    /// Moves an invited user (``NavigationFlowsOnboarding/invitedWithProfile``) past the
    /// "join a house" steps once the house has been joined.
    ///
    /// Idempotent on purpose: the join can be detected by both the `.didAcceptShare`
    /// notification and ``WaitAcceptLinkOnboardingView``'s own check, and a plain
    /// ``goToNextView()`` from each would skip ``OnboardingNavigationSteps/waitAdminScheduling``.
    /// It also covers the share being accepted *before* free time was chosen.
    ///
    /// A house that was already divided has nothing to wait for, so the guest finishes
    /// onboarding and goes straight to the main screen instead of the waiting screen.
    @MainActor
    func advanceAfterJoiningHouse() async {
        let steps = stateMachine.steps
        guard let target = steps.firstIndex(of: .waitAdminScheduling) else {
            goToNextView()
            return
        }
        
        if let freeTimeIndex = steps.firstIndex(of: .chooseFreeTime),
           stateMachine.index <= freeTimeIndex,
           pendingFreeTimeMinutes == nil {
            stateMachine.jumpToStep(index: freeTimeIndex)
            return
        }
        
        guard stateMachine.index < target else { return }
        
        // Keeps the "entering the house" loading state on screen while this is checked.
        isJoiningHouse = true
        let isAlreadyDivided = await joinedHouseIsAlreadyDivided()
        isJoiningHouse = false
        
        if isAlreadyDivided {
            finishOnboarding()
        } else if stateMachine.index < target {
            stateMachine.jumpToStep(index: target)
        }
    }
    
    /// `true` when the house already has a division and none of it belongs to this user,
    /// which is the case for a guest who joins a house that was divided before they arrived.
    @MainActor
    private func joinedHouseIsAlreadyDivided() async -> Bool {
        let assignments = await CloudKitManager.shared.fetchAll(RecurrentAssignmentModel.self)
        guard !assignments.isEmpty else { return false }
        let ownsUpcoming = await ownsUpcomingAssignment(in: assignments)
        return !ownsUpcoming
    }
    
    /// Whether this user has an occurrence the division screen would show (from tomorrow on,
    /// like ``FortnightlyViewModel``).
    ///
    /// Past occurrences don't count: a resident who left the house and came back keeps the same
    /// member record ID, so their old occurrences still point at them even though the screen
    /// would only show everyone else's chores. When the member record can't be read, the user
    /// is treated as having none, so they land on the main screen rather than on that screen.
    @MainActor
    private func ownsUpcomingAssignment(in assignments: [RecurrentAssignmentModel]) async -> Bool {
        guard let myName = await CloudKitManager.shared.fetchMyHouseUser()?.recordID?.recordName
        else { return false }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let firstShownDay = calendar.date(byAdding: .day, value: 1, to: today) else { return false }
        
        // Compared by record name so a different zone ID can't make the match fail.
        return assignments.contains { assignment in
            assignment.day >= firstShownDay
                && (assignment.userReferences ?? []).contains { $0.recordID.recordName == myName }
        }
    }
    
    /// Leaves the free-time step. A user who already joined a house through an invite skips
    /// the create/enter/wait-link steps instead of being sent back to them.
    @MainActor
    func advanceAfterFreeTime() async {
        if stateMachine.flow == .invitedWithProfile,
           let user = currentUser, CloudKitManager.shared.isHouseUser(user) {
            await advanceAfterJoiningHouse()
        } else {
            // A returning user who had to fill in free time on the way (none was saved) still
            // goes back to the welcome screen from "create or enter", not to this screen.
            if stateMachine.steps.indices.contains(stateMachine.index + 1),
               stateMachine.steps[stateMachine.index + 1] == .createOrEnterHome {
                stateMachine.skippedToCreateOrEnter = isReturningUser
            }
            goToNextView()
        }
    }
    
    /// The profile already existed before this onboarding run (e.g. the user left a house),
    /// as opposed to one created in this run.
    private var isReturningUser: Bool {
        currentUser != nil && rollbackJournal.createdProfile == nil
    }
    
    // MARK: - Pending free time
    
    /// Free time that is already on the private profile but not (known to be) on the in-house
    /// profile yet (minutes per day, Monday first). Persisted so a relaunch doesn't lose it.
    ///
    /// Free time is stored on the private profile (survives leaving a house) *and* on the
    /// in-house profile (what housemates and the scheduler read). This is the gap between the
    /// two: set while the user has no house yet, or when writing the in-house profile failed,
    /// and cleared by ``flushPendingFreeTimeIfNeeded()`` / `FreeTimeSyncService`.
    var pendingFreeTimeMinutes: [Int]? {
        get { freeTimeSync.pendingPublicSync }
        set { freeTimeSync.pendingPublicSync = newValue }
    }

    /// The in-house profile as a free-time store, or `nil` while the user has no house yet.
    @MainActor
    private func houseFreeTimeStore() async -> FreeTimeProfileStore? {
        guard let houseUser = await resolveHouseUser() else { return nil }
        return UserModelFreeTimeStore(user: houseUser)
    }

    /// The user's in-house record, or `nil` while they don't belong to a house yet.
    @MainActor
    private func resolveHouseUser() async -> UserModel? {
        if let user = currentUser, CloudKitManager.shared.isHouseUser(user) {
            return user
        }
        guard currentHouse != nil,
              let houseUser = await CloudKitManager.shared.fetchMyHouseUser() else { return nil }
        currentUser = houseUser
        stateMachine.user = houseUser
        return houseUser
    }
    
    /// Writes ``pendingFreeTimeMinutes`` to the in-house user once it exists.
    ///
    /// - Returns: `true` when nothing is pending or the save succeeded.
    @MainActor
    @discardableResult
    func flushPendingFreeTimeIfNeeded() async -> Bool {
        await freeTimeSync.flushPending()
    }

    /// Saves the free time chosen by the user on the private profile *and* on the in-house
    /// profile.
    ///
    /// The private profile is written first and is the source of truth: it survives leaving a
    /// house, so the next house gets the same free time without asking again. When the user has
    /// no house yet, the choice stays in ``pendingFreeTimeMinutes`` and is written to the
    /// in-house profile by ``flushPendingFreeTimeIfNeeded()`` once the house exists (the
    /// in-house profile is what housemates and the scheduler read).
    ///
    /// - Returns: `false` (with ``errorMessage`` set) only when the private profile could not be
    ///   written, in which case nothing was changed. If just the in-house write failed, it
    ///   returns `true` and sets ``freeTimeSyncWarning``; the sync is retried automatically.
    @MainActor
    @discardableResult
    func setAvailableTimeToUser(daysOfWeekDTO: [DayOfWeekDTO]) async -> Bool {
        isLoading = true
        errorMessage = nil
        freeTimeSyncWarning = nil
        defer { isLoading = false }

        let minutes = daysOfWeekDTO.map { Int(($0.freeTime.timeInHours * 60).rounded()) }
        rollbackJournal.lastFreeTimeMinutes = minutes

        await reloadSessionIfNeeded()

        let genericError = L10n.tr("Não foi possível salvar seus horários. Tente novamente.")

        do {
            switch try await freeTimeSync.save(minutes: minutes) {
            case .synced:
                // `setAvailableTimes` already replaced (and deleted) the previous slots.
                if let houseUser = currentUser, CloudKitManager.shared.isHouseUser(houseUser) {
                    rollbackJournal.freeTimeRecords = (houseUser.availableTimeReference ?? [])
                        .map { OnboardingRollbackJournal.StoredRecordID($0.recordID) }
                }
            case .privateOnly:
                break
            case .publicSyncPending:
                freeTimeSyncWarning = L10n.tr("Seus horários foram salvos no seu perfil, mas ainda não chegaram à casa. Vamos tentar de novo automaticamente.")
            }
            return true
        } catch let error as FreeTimeSyncError {
            switch error {
            case .invalidInput:
                errorMessage = L10n.tr("Escolha o tempo livre de pelo menos um dia.")
            case .privateProfileUnavailable:
                errorMessage = genericError
            case .privateWriteFailed:
                errorMessage = CloudKitManager.shared.errorMessage ?? genericError
            }
            return false
        } catch {
            errorMessage = genericError
            return false
        }
    }

    /// Loads the free time currently saved for the user, keyed by the row index used in
    /// `SelectFreeTimeOnboardingView.weekOrder` (0 = Monday … 6 = Sunday).
    ///
    /// Reads the private profile first and falls back to the in-house profile. Used when the
    /// screen is opened from the profile to edit existing values.
    @MainActor
    func fetchCurrentFreeTime() async -> [Int: FreeTimeEnum] {
        await reloadSessionIfNeeded()
        guard case .found(let minutes) = await freeTimeSync.restore() else { return [:] }

        var freeTimeByIndex: [Int: FreeTimeEnum] = [:]
        for (index, value) in minutes.enumerated() where value > 0 {
            freeTimeByIndex[index] = FreeTimeEnum(minutes: value)
        }
        return freeTimeByIndex
    }

    /// Brings the free time saved on the private profile back, so a user who left a house (or
    /// reinstalled the app) is not asked for it again. The value is kept as pending so the next
    /// house created or joined receives it.
    ///
    /// - Returns: `true` when free time is known (already pending, or found on the profile).
    ///   `false` when there is none, or it could not be read: the free-time step is then shown,
    ///   so a house is never created without it.
    @MainActor
    private func restoreFreeTimeFromProfile() async -> Bool {
        guard await freeTimeSync.restoreAsPending() else { return false }
        rollbackJournal.lastFreeTimeMinutes = pendingFreeTimeMinutes
        return true
    }

    // MARK: - Welcome

    /// Leaves the welcome screen. A new user goes on to create a profile; a user who already has
    /// a profile and free time (e.g. after leaving a house) goes straight to "create or enter a
    /// house", without being asked for either again.
    func advanceFromWelcome() {
        let target = OnboardingRouting.stepAfterWelcome(
            hasProfile: currentUser != nil,
            hasFreeTime: freeTimeToRestore != nil
        )
        if let index = stateMachine.steps.firstIndex(of: target) {
            // "Voltar" from "create or enter" must come back here, not to the skipped steps.
            stateMachine.skippedToCreateOrEnter = (target == .createOrEnterHome)
            stateMachine.jumpToStep(index: index)
        } else {
            goToNextView()
        }
    }
    
    /// Loads the house the user belongs to into ``currentHouse``.
    func fetchHouse() async {
        currentHouse = try? await CloudKitManager.shared.fetchFirst(HouseModel.self)
    }
    
    /// Publishes the current user's profile into the house that was just joined via a
    /// CloudKit share invite.
    ///
    /// ``createUser()`` saves the profile into this device's own private zone, which is
    /// invisible to anyone else's account. This creates a second `UserModel` record — with
    /// the same profile data — directly inside the house's shared zone, links it to the house
    /// (`house` field) and appends it to the house's `users` list, so housemates (including
    /// the owner) can see this member. ``currentUser`` is updated to point at this new,
    /// house-linked record; the *persisted* current-user record keeps pointing at the private
    /// profile, which is the anchor ``CloudKitManager/fetchMyHouseUser()`` derives this copy's
    /// `recordID` from.
    ///
    /// - Requires ``currentUser`` to already exist (created via ``createUser()``).
    @MainActor
    func joinHouse() async -> Bool {
        guard !isJoiningHouse else { return false }
        isJoiningHouse = true
        defer { isJoiningHouse = false }
        
        async let houseTask = resolveJoinedHouse()
        async let ownerIDTask = CloudKitManager.shared.fetchCurrentUserRecordID()
        
        currentHouse = await houseTask
        let ownerRecordName = (await ownerIDTask)?.recordName ?? "error fetch user's ID"
        
        guard let house = currentHouse, let houseRecordID = house.recordID,
              let profile = currentUser, let profileRecordID = profile.recordID
        else {
            errorMessage = L10n.tr("Não foi possível encontrar a casa do convite. Tente abrir o link novamente.")
            isLoading = false
            return false
        }
        
        isLoading = true
        errorMessage = nil
        
        let houseReference = CKRecord.Reference(recordID: houseRecordID, action: .none)
        let assetCopy = profile.profilePicture.flatMap { try? duplicateCKAsset($0) }
        
        let sharedUser = UserModel(
            name: profile.name,
            profilePicture: assetCopy,
            banner: profile.banner,
            tier: .novatoDaCasa,
            coins: profile.coins,
            house: houseReference,
            couponLimit: profile.couponLimit,
            ownerRecordName: ownerRecordName
        )
        
        let sharedUserID = CloudKitManager.shared.houseUserRecordID(
            for: profileRecordID,
            inHouseZone: houseRecordID.zoneID
        )
        
        async let subTask = CloudKitManager.shared.createSharedSubscription()
        
        let existingUser = await CloudKitManager.shared.fetchRecordsByRecordReference(
            for: UserModel.self,
            recordReferences: [CKRecord.Reference(recordID: sharedUserID, action: .none)]
        )?.first
        
        var savedUser = existingUser
        if savedUser == nil {
            savedUser = await CloudKitManager.shared.create(sharedUser, id: sharedUserID, parent: house.reference(action: .none))
            if let savedUser {
                await house.appendUsers([savedUser])
                rollbackJournal.joinedMembership = savedUser.recordID.map(OnboardingRollbackJournal.StoredRecordID.init)
            }
        }
        
        _ = try? await subTask
        
        isLoading = false
        
        if let savedUser {
            self.currentUser = savedUser
            self.stateMachine.user = savedUser
            CloudKitManager.shared.clearPendingJoin(ifMatching: houseRecordID.zoneID)
            // Free time picked before joining was never copied to the house record.
            await flushPendingFreeTimeIfNeeded()
            return true
        } else {
            errorMessage = CloudKitManager.shared.errorMessage ?? L10n.tr("Erro ao entrar na casa.")
            return false
        }
    }
    
    /// Resolves the house that was just joined through a share.
    private func resolveJoinedHouse() async -> HouseModel? {
        let attempts = 4
        for attempt in 0..<attempts {
            if let house = try? await CloudKitManager.shared.fetchFirst(HouseModel.self) {
                return house
            }
            // 1s, 2s, 3s back-off between attempts (no wait after the last one).
            if attempt < attempts - 1 {
                try? await Task.sleep(for: .seconds(attempt + 1))
            }
        }
        return nil
    }
    
    /// Fetches the current user's own profile record, used to re-hydrate ``currentUser``
    /// when onboarding resumes on a fresh launch (see ``restoreProgressIfNeeded()``).
    func fetchCurrentUser() async {
        currentUser = await CloudKitManager.shared.fetchMyUser()
    }
    
    /// Re-hydrates ``currentUser`` and ``currentHouse`` after the app relaunches mid-onboarding.
    ///
    /// ``OnboardingStateMachine`` persists which step the user is on, but ``currentUser`` and
    /// ``currentHouse`` live only in memory and are lost when the process ends. Steps past
    /// profile/house creation read those two properties directly, so without this they'd load
    /// a blank screen after a relaunch. Call once when ``Onboarding`` first appears.
    @MainActor
    func restoreProgressIfNeeded() async {
        guard stateMachine.index > 0 else { return }
        await reloadSessionIfNeeded()
        await flushPendingFreeTimeIfNeeded()
    }
    
    /// Loads ``currentUser`` and ``currentHouse`` (and mirrors them into ``stateMachine``)
    /// whenever either is missing.
    @MainActor
    func reloadSessionIfNeeded() async {
        if currentUser == nil {
            await fetchCurrentUser()
        }
        if currentHouse == nil {
            await fetchHouse()
        }
        
        if currentHouse != nil,
           let user = currentUser, !CloudKitManager.shared.isHouseUser(user),
           let houseUser = await CloudKitManager.shared.fetchMyHouseUser() {
            currentUser = houseUser
            stateMachine.user = houseUser
        }
        
        if let currentUser { stateMachine.user = currentUser }
        if let currentHouse { stateMachine.house = currentHouse }
    }
    
    /// A copy of `asset` in a new temporary file, so the picture can be saved in another record.
    private func duplicateCKAsset(_ asset: CKAsset) throws -> CKAsset? {
        guard let origem = asset.fileURL else { return nil }
        
        let destino = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        
        try FileManager.default.copyItem(at: origem, to: destino)
        return CKAsset(fileURL: destino)
    }
    
    // MARK: - Algorithm

    /// Advances the guest past the waiting screen once the admin's division exists.
    ///
    /// A guest who joins a house that was already divided has no occurrences of their own yet,
    /// so the division screen would only show everyone else's chores. That guest finishes
    /// onboarding and goes straight to the main screen instead.
    @MainActor
    func checkAndAdvanceIfScheduleReady() async {
        guard !isCheckingSchedule else { return }
        isCheckingSchedule = true
        defer { isCheckingSchedule = false }
        
        let assignments = await CloudKitManager.shared.fetchAll(RecurrentAssignmentModel.self)
        let scheduleIsReady = !assignments.isEmpty
        guard scheduleIsReady else { return }

        isScheduleReady = true
        guard stateMachine.current == .waitAdminScheduling else { return }
        
        guard await ownsUpcomingAssignment(in: assignments) else {
            finishOnboarding()
            return
        }
        
        // The state may have changed while the house user was being fetched.
        guard stateMachine.current == .waitAdminScheduling else { return }
        goToNextView()
    }
    
    // MARK: - Pending join
    
    /// `true` when the current house is someone else's (reached through an accepted invite) but
    /// this profile still has no member record in it.
    @MainActor
    func needsToJoinCurrentHouse() async -> Bool {
        guard let zoneID = currentHouse?.recordID?.zoneID,
              zoneID.ownerName != CKCurrentUserDefaultName,
              let user = currentUser, !CloudKitManager.shared.isHouseUser(user)
        else { return false }
        return await CloudKitManager.shared.fetchMyHouseUser() == nil
    }
    
    /// Creates the missing member record for an invite that was accepted but never joined, and
    /// moves the flow past the join steps.
    @MainActor
    func completePendingJoinIfNeeded() async {
        guard await needsToJoinCurrentHouse() else { return }
        
        // The user has a profile, so this is the "with profile" path regardless of what a race
        // may have set (`.invitedWithoutProfile` when `currentUser` wasn't loaded yet).
        stateMachine.flow = .invitedWithProfile
        if await joinHouse() {
            await advanceAfterJoiningHouse()
        }
    }
    
    // MARK: - Auto Login / Initial Validation
    
    /// Checks if the current iCloud user already possesses an account within the application.
    ///
    /// - If only the profile exists: resets the state machine flow to `.notDefined` and jumps
    ///   to the free-time step (`.chooseFreeTime`) — or straight to `.createOrEnterHome` when free
    ///   time is already pending — bypassing welcome and profile creation. The flow is corrected to `.houseCreator`/`.invitedWithProfile` once the
    ///   user picks "Criar" or "Entrar" on that screen.
    @MainActor
    func checkExistingAccount() async {
        
        guard !isLoading else { return }
        
        isCheckingAccount = true
        isLoading = true
        
        defer {
            isCheckingAccount = false
            isLoading = false
        }
        
        // Leaves any house this iCloud account is still attached to without a member record
        await CloudKitManager.shared.pruneOrphanedSharedMemberships()
        
        async let fetchedUser = CloudKitManager.shared.fetchMyUser()
        async let fetchedHouse = try? await CloudKitManager.shared.fetchFirst(HouseModel.self)
        
        let user = await fetchedUser
        let house = await fetchedHouse
        
        let hasOnboardingInProgress = stateMachine.flow != .notDefined && stateMachine.index > 0
        if hasOnboardingInProgress {
            if let user { currentUser = user; stateMachine.user = user }
            if let house { currentHouse = house; stateMachine.house = house }
            // An invite accepted while the app was starting may have left the flow without the
            // member record (e.g. `.didAcceptShare` arrived before `currentUser` was loaded).
            await completePendingJoinIfNeeded()
            return
        }
        
        if let existingUser = user {
            self.currentUser = existingUser
            self.stateMachine.user = existingUser
            
            if let existingHouse = house {
                self.currentHouse = existingHouse
                self.stateMachine.house = existingHouse
                
                // When the app is opened through an invite link, the share is accepted in
                // parallel with this check, so the invited house is already visible here even
                // though `joinHouse()` never ran. Finishing onboarding at this point dropped the
                // user into the app without their public (in-house) record.
                if await needsToJoinCurrentHouse() {
                    await completePendingJoinIfNeeded()
                } else {
                    self.finishOnboarding()
                }
            } else {
                // An account with a profile and no house (it left or deleted its house, or the
                // app was reinstalled) always starts over at the welcome screen, which leads to
                // "create or enter a house" (see `advanceFromWelcome()`). Progress and rollback
                // data persisted by an earlier onboarding are stale here: resuming them used to
                // jump straight to "create or enter" with "voltar" pointing at the free-time step.
                stateMachine.resetProgress()
                rollbackJournal = OnboardingRollbackJournal()
                
                // Free time is stored on the private profile too, so it survives leaving a
                // house. A returning user keeps it instead of being asked again; it is only
                // missing for accounts that never saved one (or when it could not be read),
                // and a house is never created without it (the owner would be stuck waiting).
                _ = await restoreFreeTimeFromProfile()
            }
        }
    }
}
