//
//  MyFortghtlyView.swift
//  Cognitive-Work
//
//  Created by Carolina Sun on 02/10/26.
//

import SwiftUI
import CloudKit

/// The "current division" card: the signed-in member's share of the schedule (a chart of their
/// chores per day), ready to drop into a screen.
///
/// Uses a ``CurrentScheduleViewModel`` and shows a ``UserScheduleCard`` once it has loaded.
/// All parameters are optional:
/// - Pass nothing and the view fetches everything from CloudKit.
/// - Pass `users` and `chores` and only the rest is fetched.
/// - Pass `sharedViewModel` (the dashboard does) and the view only displays it.
struct UserCurrentDivisionComponent: View {
    
    /// Every resident of the house. When `nil`, data is fetched from CloudKit.
    var users: [UserModel]? = nil
    
    /// Every chore of the house. When `nil`, data is fetched from CloudKit.
    var chores: [ChoreModel]? = nil
    
    /// Assignments already in memory. Must be provided together with ``rooms``.
    var assignments: [RecurrentAssignmentModel]? = nil
    
    /// Rooms already in memory. Must be provided together with ``assignments``.
    var rooms: [RoomModel]? = nil
    
    /// The signed-in resident, when already known.
    var analizedUser: UserModel? = nil
    
    /// Day the algorithm was run (start of the division).
    /// When `nil`, falls back to the view model's own start date.
    var periodStart: Date? = nil
    
    /// View model owned by a parent that loads everything together (the dashboard).
    /// When set, this view only displays it and does no loading of its own.
    var sharedViewModel: CurrentScheduleViewModel? = nil
    
    /// The view model used when no shared one is given.
    @State private var ownViewModel = CurrentScheduleViewModel()
    
    /// The view model in use: the shared one, or the view's own.
    private var viewModel: CurrentScheduleViewModel { sharedViewModel ?? ownViewModel }
    
    /// `CloudKitManager.dataRevision` the schedule was last loaded at.
    @State private var loadedRevision: Int?
    
    var body: some View {
        Group {
            // MARK: - Empty space while loading, then the schedule card
            if viewModel.isLoading {
                // Only seen standalone; inside the dashboard the parent overlay covers loading.
                Color.clear.frame(height: 200)
            } else {
                UserScheduleCard(
                    user: viewModel.currentUser,
                    entries: viewModel.myEntries,
                    startDate: periodStart ?? viewModel.startDate,
                    roomCaption: viewModel.roomsInUse,
                    chore: viewModel.chore(for:),
                    room: viewModel.room(for:),
                )
            }
        }
        // MARK: - Loads (again) when the data changes, unless a parent loads it
        .task(id: CloudKitManager.shared.dataRevision) {
            guard sharedViewModel == nil else { return }
            let revision = CloudKitManager.shared.dataRevision
            guard loadedRevision != revision else { return }
            await load()
            if !Task.isCancelled { loadedRevision = revision }
        }
    }
    
    /// Loads the schedule using whatever data was provided, fetching the rest.
    private func load() async {
        if let users, let chores {
            await viewModel.setup(users: users, chores: chores,
                                  assignments: assignments, rooms: rooms, me: analizedUser)
        } else {
            await viewModel.setupWithFetch(me: analizedUser)
        }
    }
}

// MARK: PREVIEW
#Preview {
    ScrollView {
        UserCurrentDivisionComponent.preview
            .padding(.horizontal, 16)
    }
}

private extension UserCurrentDivisionComponent {
    
    /// Three residents, four rooms and a fortnight of chores, all in memory.
    static var preview: UserCurrentDivisionComponent {
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
            currentResponsible: userReferences.first,
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
        
        return UserCurrentDivisionComponent(
            users: users,
            chores: chores,
            assignments: assignments,
            rooms: [kitchen, bathroom, livingRoom, laundry],
            analizedUser: users.first,
            periodStart: today
        )
    }
}
