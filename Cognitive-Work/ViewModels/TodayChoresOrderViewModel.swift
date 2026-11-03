//
//  TodayChoresOrderViewModel.swift
//  Cognitive-Work
//
//  Created by anshu Li on 27/10/26.
//

import Foundation
import CloudKit


/// The suggested order of the viewer's chores for today, shown in the box under "Hoje" in the
/// list, plus a "depois de …" note for each card's back face.
///
/// The on-device model only says where each chore fits in the day (``GeneratedChorePhase``);
/// code sorts the viewer's chores by that and finds, among *everyone's* chores today, the one
/// that should be done first (washing the dishes waits for whoever cooks). Nothing is changed
/// in the chores themselves: it's only a suggestion.
@MainActor
@Observable
final class TodayChoreOrder {

    static let shared = TodayChoreOrder()

    /// One of the viewer's chores, in the suggested order.
    struct Step: Identifiable, Equatable {
        /// The occurrence's id (see ``ChoreOccurrence/id``).
        let id: String
        let name: String
        /// "Depois de “Cozinhar” (Ana)", or `nil` when nothing needs to come first.
        let note: String?
    }

    /// The viewer's open chores today, in the suggested order. Empty when there's nothing to
    /// suggest (AI unavailable, or no chores today).
    private(set) var steps: [Step] = []

    /// What the last order was built from, so it isn't rebuilt for the same day and chores.
    @ObservationIgnored private var lastKey = ""

    private init() {}

    /// The grey line for a card's back face, if that occurrence is one of the viewer's today:
    /// its place in the suggested order and, when something comes first, what
    /// ("2ª de 3 hoje · Depois de “Cozinhar” (Ana)"). With a single chore and nothing before it,
    /// there's nothing to say.
    func note(for occurrenceID: String) -> String? {
        guard let index = steps.firstIndex(where: { $0.id == occurrenceID }) else { return nil }
        let step = steps[index]
        let place = steps.count >= 2 ? L10n.tr("\(index + 1)ª de \(steps.count) hoje") : nil
        switch (place, step.note) {
        case let (place?, note?): return place + " · " + note
        case let (place?, nil): return place
        case let (nil, note?): return note
        case (nil, nil): return nil
        }
    }

    /// Rebuilds the order when today's chores changed. Cheap to call often.
    func refresh(using carousel: CarouselViewModel) async {
        guard IntelligenceManager.shared.isAvailable else {
            #if DEBUG
            print("[TodayOrder] Apple Intelligence unavailable: no order")
            #endif
            steps = []
            return
        }
        let today = carousel.openOccurrencesToday()
        let day = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        let key = "\(day)|" + today
            .map { "\($0.occurrence.id):\($0.occurrence.chore.name):\($0.isMine)" }
            .sorted()
            .joined(separator: "|")
        guard key != lastKey else { return }

        // Each different name once (answers are also cached on the device).
        var phases: [String: GeneratedChorePhase] = [:]
        for entry in today {
            let name = entry.occurrence.chore.name
            let cacheKey = ChorePhaseCache.key(for: name)
            guard phases[cacheKey] == nil else { continue }
            phases[cacheKey] = await IntelligenceManager.shared.phase(ofChore: name) ?? .other
        }

        func phase(of entry: (occurrence: ChoreOccurrence, userIDs: Set<CKRecord.ID>, isMine: Bool)) -> GeneratedChorePhase {
            phases[ChorePhaseCache.key(for: entry.occurrence.chore.name)] ?? .other
        }

        let mine = today
            .filter(\.isMine)
            .sorted { lhs, rhs in
                let left = Self.rank(phase(of: lhs)), right = Self.rank(phase(of: rhs))
                if left != right { return left < right }
                // Same moment of the day: more urgent first.
                let leftPriority = lhs.occurrence.chore.priorityTag.scoreValue
                let rightPriority = rhs.occurrence.chore.priorityTag.scoreValue
                if leftPriority != rightPriority { return leftPriority > rightPriority }
                return lhs.occurrence.chore.name < rhs.occurrence.chore.name
            }

        // A newer refresh (today's chores changed again) replaced this one.
        guard !Task.isCancelled else { return }
        steps = mine.map { entry in
            let before = Self.predecessor(
                of: phase(of: entry),
                among: today.filter { $0.occurrence.id != entry.occurrence.id },
                phaseOf: phase(of:)
            )
            return Step(
                id: entry.occurrence.id,
                name: entry.occurrence.chore.name,
                note: before.map { Self.note(after: $0, carousel: carousel) }
            )
        }
        lastKey = key
        #if DEBUG
        print("[TodayOrder] today: \(today.count) open, mine: \(mine.count)")
        for entry in today {
            print("[TodayOrder]  \(entry.isMine ? "me " : "   ") \(entry.occurrence.chore.name) -> \(phase(of: entry))")
        }
        #endif
    }

    // MARK: - Rules (code, not the model)

    /// Position in the day; lower comes first. Laundry starts early so it can dry while the
    /// rest is done; the trash goes out last.
    private static func rank(_ phase: GeneratedChorePhase) -> Int {
        switch phase {
        case .tidyUp: return 0
        case .laundryWash: return 1
        case .cooking: return 2
        case .afterMeal: return 3
        case .dusting: return 4
        case .floorDry: return 5
        case .floorWet: return 6
        case .other: return 7
        case .laundryDry: return 7
        case .laundryFold: return 8
        case .trash: return 9
        }
    }

    /// The phases that must happen before `phase`, nearest first.
    private static func phasesBefore(_ phase: GeneratedChorePhase) -> [GeneratedChorePhase] {
        switch phase {
        case .afterMeal: return [.cooking]
        case .dusting: return [.tidyUp]
        case .floorDry: return [.dusting, .tidyUp]
        case .floorWet: return [.floorDry, .dusting, .tidyUp]
        case .laundryDry: return [.laundryWash]
        case .laundryFold: return [.laundryDry, .laundryWash]
        // The trash fills up with the cleaning, so it waits for the last of it.
        case .trash: return [.floorWet, .floorDry, .afterMeal, .dusting, .tidyUp]
        case .tidyUp, .cooking, .laundryWash, .other: return []
        }
    }

    /// The chore today that should be done right before one in `phase`, if any.
    private static func predecessor(
        of phase: GeneratedChorePhase,
        among others: [(occurrence: ChoreOccurrence, userIDs: Set<CKRecord.ID>, isMine: Bool)],
        phaseOf: ((occurrence: ChoreOccurrence, userIDs: Set<CKRecord.ID>, isMine: Bool)) -> GeneratedChorePhase
    ) -> (occurrence: ChoreOccurrence, userIDs: Set<CKRecord.ID>, isMine: Bool)? {
        for wanted in phasesBefore(phase) {
            if let found = others.first(where: { phaseOf($0) == wanted }) { return found }
        }
        return nil
    }

    /// "Depois de “Cozinhar”" for the viewer's own chore, "Depois de “Cozinhar” (Ana)" for
    /// someone else's.
    private static func note(
        after entry: (occurrence: ChoreOccurrence, userIDs: Set<CKRecord.ID>, isMine: Bool),
        carousel: CarouselViewModel
    ) -> String {
        let name = entry.occurrence.chore.name
        guard !entry.isMine else { return L10n.tr("Depois de “\(name)”") }
        let people = carousel.userModels
            .filter { user in user.recordID.map { entry.userIDs.contains($0) } ?? false }
            .map(\.name)
        guard !people.isEmpty else { return L10n.tr("Depois de “\(name)”") }
        return L10n.tr("Depois de “\(name)” (\(people.joined(separator: ", ")))")
    }
}
