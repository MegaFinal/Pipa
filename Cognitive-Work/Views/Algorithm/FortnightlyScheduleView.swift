//
//  FortnightlySchedule.swift
//  Cognitive-Work
//
//  Created by Carolina Sun on 28/08/26.
//

import SwiftUI
import CloudKit

/// The division screen: shows ``WaitingAlgorithmView`` while the chores are being divided,
/// then the result in ``FortnightlyView`` with an info pop-up and a confirm button.
struct FortnightlyScheduleView: View {
    /// Loads (or creates) the division.
    @State private var scheduleViewModel: ScheduleViewModel
    /// Shows the pop-up that explains the division.
    @State private var showInfoPopUp = false
    
    /// `true` creates a new division; `false` only shows the current one.
    let shouldGenerate: Bool
    /// Called when the user confirms the division.
    let action: () -> Void
    
    /// Creates the screen.
    /// - Parameters:
    ///   - shouldGenerate: `true` creates a new division; `false` only shows the current one.
    ///   - scheduleViewModel: Pre-filled data (e.g. for previews). `nil` loads from CloudKit.
    ///   - knownChoreIDs: Chores saved just before this screen (onboarding) that a CloudKit
    ///     query may not return yet; they're read by ID so the division includes them.
    ///   - action: Called when the user confirms the division.
    init(
        shouldGenerate: Bool,
        scheduleViewModel: ScheduleViewModel? = nil,
        knownChoreIDs: [CKRecord.ID] = [],
        action: @escaping () -> Void
    ) {
        self.shouldGenerate = shouldGenerate
        self.action = action
        self._scheduleViewModel = State(
            initialValue: scheduleViewModel ?? ScheduleViewModel(knownChoreIDs: knownChoreIDs)
        )
    }
    
    /// `true` while `WaitingAlgorithmView` or the info pop-up is on screen: the navigation bar
    /// shows nothing (no confirm, no back) so the user can't leave or confirm mid-way.
    private var hidesNavigationBarItems: Bool {
        scheduleViewModel.isLoading || showInfoPopUp
    }
    
    var body: some View {
        Group {
            // MARK: - Waiting screen, then the division
            if scheduleViewModel.isLoading {
                WaitingAlgorithmView()
            } else {
                FortnightlyView(
                    users: scheduleViewModel.users,
                    chores: scheduleViewModel.chores,
                    assignments: scheduleViewModel.assignments,
                    rooms: scheduleViewModel.rooms
                )
                .disabled(showInfoPopUp)
                .onAppear {
                    showInfoPopUp = true
                }
            }
        }
        // MARK: - Confirm button (hidden while loading or with the pop-up open)
        .toolbar {
            // Not just disabled: while the division is generated or the info pop-up is up,
            // the bar must stay empty.
            if !hidesNavigationBarItems {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        action()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12))
                            .bold()
                            .foregroundColor(.white)
                    }
                    .tint(.blue)
                    .buttonStyle(.glassProminent)
                    .voiceOverLabel(L10n.tr("Confirmar escala"))
                    .voiceControlNames([L10n.tr("Confirmar"), L10n.tr("OK"), L10n.tr("Confirmar escala")])
                }
            }
        }
        // MARK: - Layout, info pop-up and loading
        .navigationBarBackButtonHidden(hidesNavigationBarItems)
        .hidesTabBar()
        .padding(.top, 40)
        .padding(.vertical)
        .ignoresSafeArea()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay { infoPopUpOverlay }
        .task {
            await scheduleViewModel.loadSchedule(shouldGenerate: shouldGenerate)
        }
        // MARK: - VoiceOver: says how the division ended once the waiting screen goes away
        .onChange(of: scheduleViewModel.isLoading) { _, isLoading in
            guard !isLoading else { return }
            if let error = scheduleViewModel.errorMessage {
                VoiceOver.announce(error)
            } else {
                VoiceOver.announce(L10n.tr("Escala quinzenal pronta"))
            }
        }
        .onChange(of: showInfoPopUp) { VoiceOver.screenChanged() }
    }
    
    /// The info pop-up over a dark background.
    @ViewBuilder
    private var infoPopUpOverlay: some View {
        if showInfoPopUp {
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { }
                    .accessibilityDecorative()
                
                ScheduleInfoPopUp {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showInfoPopUp = false
                    }
                }
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
            .transition(.opacity)
            // Only the pop-up is reachable; the escape gesture closes it like its button.
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showInfoPopUp = false
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        FortnightlyScheduleView(shouldGenerate: false, scheduleViewModel: .preview) {
            print("Action")
        }
    }
}

private extension ScheduleViewModel {
    
    /// Three residents, four rooms and a fortnight of chores, all in memory.
    static var preview: ScheduleViewModel {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let house = CKRecord.Reference(recordID: CKRecord.ID(recordName: "preview-house"), action: .none)
        
        func reference(_ recordName: String) -> CKRecord.Reference {
            CKRecord.Reference(recordID: CKRecord.ID(recordName: recordName), action: .none)
        }
        
        let users = ["Ana", "Bruno", "Carla"].map { name in
            UserModel(
                name: name,
                tier: .tier1,
                house: house,
                recordID: CKRecord.ID(recordName: "preview-user-\(name)"),
                ownerRecordName: "preview-owner-\(name)"
            )
        }
        let userReferences = users.compactMap { $0.recordID.map { CKRecord.Reference(recordID: $0, action: .none) } }
        
        func room(_ name: String, symbol: String, color: RoomColor) -> RoomModel {
            var room = RoomModel(name: name, symbol: symbol, house: house, color: color)
            room.recordID = CKRecord.ID(recordName: "preview-room-\(name)")
            return room
        }
        let kitchen = room("Cozinha", symbol: "fork.knife", color: .orange)
        let bathroom = room("Banheiro", symbol: "toilet", color: .blue)
        let livingRoom = room("Sala", symbol: "sofa", color: .green)
        let laundry = room("Lavanderia", symbol: "washer", color: .purple)
        
        var assignments: [RecurrentAssignmentModel] = []
        
        /// A recurring chore with one occurrence every `step` days of the fortnight, rotating
        /// between the residents.
        func recurringChore(
            _ name: String,
            room: RoomModel,
            minutes: Double,
            frequency: Recurrence,
            step: Int,
            firstDay: Int = 0,
            priority: PriorityTag = .medium
        ) -> ChoreModel {
            let choreRecordName = "preview-chore-\(name)"
            let chore = ChoreModel(
                name: name,
                description: "",
                frequency: frequency,
                duration: minutes,
                isPublic: true,
                priorityTag: priority,
                roomReference: room.recordID.map { CKRecord.Reference(recordID: $0, action: .none) }
            )
            chore.recordID = CKRecord.ID(recordName: choreRecordName)
            
            var occurrenceReferences: [CKRecord.Reference] = []
            for (index, dayOffset) in stride(from: firstDay, to: 14, by: step).enumerated() {
                let day = calendar.date(byAdding: .day, value: dayOffset, to: tomorrow) ?? tomorrow
                let assignment = RecurrentAssignmentModel(
                    day: day,
                    users: [userReferences[index % userReferences.count]],
                    chore: reference(choreRecordName)
                )
                let assignmentRecordName = "\(choreRecordName)-\(dayOffset)"
                assignment.recordID = CKRecord.ID(recordName: assignmentRecordName)
                assignments.append(assignment)
                occurrenceReferences.append(reference(assignmentRecordName))
            }
            chore.dailyAssignmentsReference = occurrenceReferences
            return chore
        }
        
        let oneOffChore = ChoreModel(
            name: "Trocar lâmpada",
            description: "",
            dueDate: calendar.date(byAdding: .day, value: 4, to: tomorrow),
            frequency: .none,
            duration: 15,
            isPublic: true,
            priorityTag: .high,
            currentResponsible: userReferences.last,
            roomReference: livingRoom.recordID.map { CKRecord.Reference(recordID: $0, action: .none) }
        )
        oneOffChore.recordID = CKRecord.ID(recordName: "preview-chore-lampada")
        
        let chores = [
            recurringChore("Lavar a louça", room: kitchen, minutes: 15, frequency: .daily, step: 1, priority: .high),
            recurringChore("Limpar o banheiro", room: bathroom, minutes: 60, frequency: .weekly, step: 7, firstDay: 1),
            recurringChore("Lavar roupa", room: laundry, minutes: 30, frequency: .weekly, step: 7, firstDay: 2),
            recurringChore("Aspirar a sala", room: livingRoom, minutes: 30, frequency: .weekly, step: 7, firstDay: 4, priority: .low),
            recurringChore("Faxina geral", room: livingRoom, minutes: 120, frequency: .fortnightly, step: 14, firstDay: 5, priority: .urgent),
            oneOffChore
        ]
        
        return ScheduleViewModel(
            users: users,
            chores: chores,
            assignments: assignments,
            rooms: [kitchen, bathroom, livingRoom, laundry]
        )
    }
}
