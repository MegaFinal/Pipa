//
//  HouseSnapshot+Preview.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 26/10/26.
//

#if DEBUG
import CloudKit

extension HouseSnapshot {
    
    /// A house with three members, a few rooms, chores spread over the week and some chores
    /// nobody owns, for SwiftUI previews. The signed-in member is "Dayô".
    static var preview: HouseSnapshot {
        PreviewHouse().snapshot
    }
}

private struct PreviewHouse {
    private let calendar = Calendar.current
    
    private let me = PreviewHouse.member("Dayô", points: 120)
    private let ana = PreviewHouse.member("Ana", points: 90)
    private let bruno = PreviewHouse.member("Bruno", points: 60)
    
    private let kitchen = PreviewHouse.room("Cozinha", symbol: "stove.pans", color: .yellow)
    private let bathroom = PreviewHouse.room("Banheiro", symbol: "toilet", color: .blue)
    private let livingRoom = PreviewHouse.room("Sala de Estar", symbol: "sofa", color: .orange)
    private let laundry = PreviewHouse.room("Área de Serviço", symbol: "clothes.line.stripes", color: .blue)
    private let garden = PreviewHouse.room("Jardim", symbol: "snake.plant", color: .green)
    
    var snapshot: HouseSnapshot {
        let members = [me, ana, bruno]
        let rooms = [kitchen, bathroom, livingRoom, laundry, garden]
        let ownedChores = [
            recurringChore("Lavar a louça", room: kitchen, frequency: .daily, owner: me, dayOffsets: -3...3),
            recurringChore("Varrer o chão", room: livingRoom, frequency: .daily, owner: ana, dayOffsets: -3...3),
            recurringChore("Limpar o vaso", room: bathroom, frequency: .weekly, owner: me, dayOffsets: [1]),
            recurringChore("Lavar as roupas", room: laundry, frequency: .weekly, owner: bruno, dayOffsets: [2])
        ]
        let unownedChores = [
            recurringChore("Regar plantas", room: garden, frequency: .daily, owner: nil, dayOffsets: 1...3),
            recurringChore("Limpar o box", room: bathroom, frequency: .weekly, owner: nil, dayOffsets: [4]),
            recurringChore("Passar roupa", room: laundry, frequency: .weekly, owner: nil, dayOffsets: [5]),
            oneOffChore("Limpar geladeira", room: kitchen, frequency: .none),
            oneOffChore("Tirar o lixo", room: kitchen, frequency: .none)
        ]
        let chores = (ownedChores + unownedChores).map(\.chore)
        let assignments = (ownedChores + unownedChores).flatMap(\.assignments)
        
        return HouseSnapshot(
            chores: chores, users: members, userRecords: members, rooms: rooms, assignments: assignments,
            houseUser: me, privateUser: nil, shopList: nil, shopItems: [],
            rankHistory: [], coupons: [], cycles: [], houseID: nil
        )
    }
    
    // MARK: - Builders
    
    private static func member(_ name: String, points: Int) -> UserModel {
        UserModel(
            name: name, tier: Tier(points: points), points: points,
            recordID: CKRecord.ID(recordName: "preview-user-\(name)"),
            ownerRecordName: "preview-owner-\(name)"
        )
    }
    
    private static func room(_ name: String, symbol: String, color: RoomColor) -> RoomModel {
        var room = RoomModel(name: name, symbol: symbol, color: color)
        room.recordID = CKRecord.ID(recordName: "preview-room-\(name)")
        return room
    }
    
    private func recurringChore<Days: Sequence<Int>>(
        _ name: String, room: RoomModel, frequency: Recurrence, owner: UserModel?, dayOffsets: Days
    ) -> (chore: ChoreModel, assignments: [RecurrentAssignmentModel]) {
        let chore = makeChore(name, room: room, frequency: frequency)
        let choreReference = CKRecord.Reference(recordID: chore.recordID!, action: .none)
        let ownerReferences = owner?.recordID.map { [CKRecord.Reference(recordID: $0, action: .none)] }
        let today = calendar.startOfDay(for: .now)
        
        let assignments = dayOffsets.compactMap { offset -> RecurrentAssignmentModel? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let assignment = RecurrentAssignmentModel(
                day: day, isCompleted: offset < 0, users: ownerReferences, chore: choreReference
            )
            assignment.recordID = CKRecord.ID(recordName: "preview-assignment-\(name)-\(offset)")
            return assignment
        }
        chore.dailyAssignmentsReference = assignments.compactMap { assignment in
            assignment.recordID.map { CKRecord.Reference(recordID: $0, action: .none) }
        }
        if let ownerReference = ownerReferences?.first {
            chore.currentResponsibleReference = ownerReference
            chore.allResponsibleUsersReference = [ownerReference]
        }
        return (chore, assignments)
    }
    
    private func oneOffChore(
        _ name: String, room: RoomModel, frequency: Recurrence
    ) -> (chore: ChoreModel, assignments: [RecurrentAssignmentModel]) {
        (makeChore(name, room: room, frequency: frequency), [])
    }
    
    private func makeChore(_ name: String, room: RoomModel, frequency: Recurrence) -> ChoreModel {
        let chore = ChoreModel(
            name: name,
            description: "Descrição da tarefa \(name.lowercased()).",
            frequency: frequency,
            duration: 20,
            isPublic: true,
            priorityTag: .medium,
            roomReference: room.recordID.map { CKRecord.Reference(recordID: $0, action: .none) }
        )
        chore.recordID = CKRecord.ID(recordName: "preview-chore-\(name)")
        return chore
    }
}
#endif
