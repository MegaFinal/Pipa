//
//  ChoreSuggestion.swift
//  Cognitive-Work
//
//  Created by anshu Li on 26/10/26.
//

import Foundation
import FoundationModels

// MARK: - What the on-device model returns

/// How often the chore repeats: what the person said, or else what usually fits the chore.
@Generable
nonisolated enum GeneratedChoreFrequency: String {
    case once, daily, weekly, fortnightly, monthly
}

/// Mirror of ``ChoreDurationTier`` without `undefined`.
@Generable
nonisolated enum GeneratedChoreDuration: String {
    case quick, moderate, slow, verySlow
}

/// Mirror of ``PriorityTag``; `notSaid` when the person didn't say how urgent it is.
@Generable
nonisolated enum GeneratedChorePriority: String {
    case notSaid, low, medium, high, urgent
}

@Generable
nonisolated struct GeneratedChore {
    @Guide(description: "The chore, short, starting with a verb")
    var name: String

    @Guide(description: "One room copied exactly from the rooms list, or none")
    var room: String

    var frequency: GeneratedChoreFrequency
    var duration: GeneratedChoreDuration
    var priority: GeneratedChorePriority

    @Guide(description: "Extra how-to details the person said, in their words. Empty if none")
    var details: String

    @Guide(description: "Steps or parts the person listed, one short item each. Empty if none", .maximumCount(8))
    var steps: [String]
}

/// Typical checklist steps for a chore, suggested when the person listed none.
@Generable
nonisolated struct GeneratedChecklistIdeas {
    @Guide(description: "Short, concrete steps to do the chore", .maximumCount(5))
    var items: [String]
}

// MARK: - What the form uses

/// A filled-in chore form, ready for the person to check. Only `name` and `durationMinutes`
/// are always set; the rest is `nil` when the text didn't say it (or no room fits).
struct ChoreSuggestion {
    /// What the person typed or said.
    let input: String
    let name: String
    let room: RoomModel?
    let frequency: Recurrence?
    let durationMinutes: Double
    let priority: PriorityTag?
    /// Housemates named in the text (and the person typing, for "eu"), read by code.
    let responsibleUsers: [UserModel]?
    /// How-to details the person said ("usar luva"), for "Detalhes"; `nil` when none.
    let details: String?
    /// Steps the person listed ("o vaso, a pia e o box"), for the checklist; empty when none.
    let steps: [String]
    /// The day the person mentioned ("amanhã", "sábado", "dia 30"), read by code; `nil` when none.
    let date: Date?
}

extension IntelligenceManager {

    /// Fills a chore form from a description ("lavar a louça toda semana, eu e Ana").
    ///
    /// The model picks name, room, frequency, duration and priority. People are matched by code
    /// from the text itself, like the shopping list, so a name is never invented.
    ///
    /// - Returns: `nil` when AI is unavailable or the request fails.
    func suggestChore(
        for text: String,
        rooms: [RoomModel],
        housemates: [UserModel],
        currentUser: UserModel?
    ) async -> ChoreSuggestion? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        // Rooms as the person sees them (translated default names, e.g. "Kitchen").
        let roomNames = rooms.map { $0.name.localizedDefault }
        let prompt = IntelligencePrompts.ChoreParse.self
        guard let generated = await generate(
            GeneratedChore.self,
            prompt: prompt.prompt(for: input, rooms: roomNames),
            instructions: instructions(task: prompt.task, output: .appLanguage),
            promptID: prompt.id
        ) else { return nil }

        // A day said without how often ("amanhã", "sábado", "dia 30") means a one-time chore; the
        // model tends to guess a usual frequency instead, so code decides this case.
        let date = ChoreDateReader.date(in: input)
        let frequency: Recurrence? = (date != nil && !ChoreDateReader.mentionsRepetition(input))
            ? Recurrence.none
            : Self.recurrence(from: generated.frequency)

        let name = String(
            generated.name
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(TextLimits.choreName)
        )

        return ChoreSuggestion(
            input: input,
            name: name.isEmpty ? String(input.prefix(TextLimits.choreName)) : name,
            room: Self.room(named: generated.room, in: rooms),
            frequency: frequency,
            durationMinutes: Self.tier(from: generated.duration).minutes,
            priority: Self.priority(from: generated.priority),
            responsibleUsers: Self.consumersMentioned(
                in: input,
                housemates: housemates,
                currentUser: currentUser,
                everyoneCounts: false
            ),
            details: Self.cleaned(generated.details, limit: TextLimits.choreDescription),
            steps: generated.steps.compactMap { Self.cleaned($0, limit: TextLimits.checklistItem) },
            date: date
        )
    }

    /// Up to five typical steps for a chore ("Limpar o banheiro" -> vaso, pia, box…), in the
    /// app's language. Only suggestions: the form shows them as chips the person taps to add.
    ///
    /// - Parameter existing: Items already on the checklist, so they aren't suggested again.
    /// - Returns: `nil` when AI is unavailable or the request fails.
    func suggestChecklist(for name: String, room: String?, existing: [String]) async -> [String]? {
        let prompt = IntelligencePrompts.ChoreChecklistIdeas.self
        guard let generated = await generate(
            GeneratedChecklistIdeas.self,
            prompt: prompt.prompt(name: name, room: room, existing: existing),
            instructions: instructions(task: prompt.task, output: .appLanguage),
            promptID: prompt.id
        ) else { return nil }

        let taken = Set(existing.map(Self.foldedKey))
        var seen = Set<String>()
        return generated.items.compactMap { item in
            guard let text = Self.cleaned(item, limit: TextLimits.checklistItem) else { return nil }
            let key = Self.foldedKey(text)
            guard !taken.contains(key), seen.insert(key).inserted else { return nil }
            return text
        }
    }

    /// Trimmed, first letter capitalized, cut to `limit`; `nil` when empty.
    private static func cleaned(_ text: String, limit: Int) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;:-")))
        guard !trimmed.isEmpty else { return nil }
        let capitalized = trimmed.prefix(1).uppercased(with: L10n.locale) + trimmed.dropFirst()
        return String(capitalized.prefix(limit))
    }

    /// Lowercased without accents, to compare checklist items.
    static func foldedKey(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Mapping

    /// The room whose name (stored or translated) matches, ignoring case and accents.
    private static func room(named name: String, in rooms: [RoomModel]) -> RoomModel? {
        func folded(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let wanted = folded(name)
        guard !wanted.isEmpty, wanted != "none" else { return nil }
        return rooms.first { folded($0.name) == wanted || folded($0.name.localizedDefault) == wanted }
    }

    private static func recurrence(from frequency: GeneratedChoreFrequency) -> Recurrence? {
        switch frequency {
        case .once: return Recurrence.none
        case .daily: return .daily
        case .weekly: return .weekly
        case .fortnightly: return .fortnightly
        case .monthly: return .monthly
        }
    }

    private static func tier(from duration: GeneratedChoreDuration) -> ChoreDurationTier {
        switch duration {
        case .quick: return .quick
        case .moderate: return .moderate
        case .slow: return .slow
        case .verySlow: return .verySlow
        }
    }

    private static func priority(from priority: GeneratedChorePriority) -> PriorityTag? {
        switch priority {
        case .notSaid: return nil
        case .low: return .low
        case .medium: return .medium
        case .high: return .high
        case .urgent: return .urgent
        }
    }
}

// MARK: - Dates said in the text (code, not the model)

/// Finds the day a chore description mentions, in Portuguese or English: "hoje", "amanhã",
/// "depois de amanhã", a weekday ("sábado", "toda segunda" -> the next one), "dia 30", "30/10",
/// or any date `NSDataDetector` recognizes. Plain code, so it never invents a date.
enum ChoreDateReader {

    /// Weekday words -> `Calendar` weekday numbers (1 = Sunday).
    private static let weekdays: [String: Int] = [
        "domingo": 1, "segunda": 2, "terca": 3, "quarta": 4, "quinta": 5, "sexta": 6, "sabado": 7,
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7
    ]

    /// Words saying the chore repeats ("toda segunda", "a cada 15 dias", "every week").
    private static let repetitionWords: Set<String> = [
        "todo", "toda", "todos", "todas", "cada", "diario", "diaria", "diariamente",
        "semanal", "semanalmente", "quinzenal", "mensal", "mensalmente", "sempre",
        "every", "daily", "weekly", "monthly", "always"
    ]

    /// Whether `text` says how often the chore repeats, so a day in it is just the first one
    /// ("toda segunda") rather than a one-time date ("segunda").
    static func mentionsRepetition(_ text: String) -> Bool {
        let words = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        return words.contains { repetitionWords.contains($0) }
    }

    /// The first day mentioned in `text`, at the start of the day, or `nil`.
    static func date(in text: String, now: Date = .now, calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: now)
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let words = folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let joined = " " + words.joined(separator: " ") + " "

        func days(_ count: Int) -> Date? { calendar.date(byAdding: .day, value: count, to: today) }

        // Longest phrases first: "depois de amanhã" also contains "amanhã".
        if joined.contains(" depois de amanha ") || joined.contains(" day after tomorrow ") { return days(2) }
        if joined.contains(" amanha ") || joined.contains(" tomorrow ") { return days(1) }
        if joined.contains(" hoje ") || joined.contains(" today ") { return today }

        // A weekday: the next one, today included.
        for word in words {
            guard let weekday = weekdays[word] else { continue }
            let todayWeekday = calendar.component(.weekday, from: today)
            return days((weekday - todayWeekday + 7) % 7)
        }

        // "dia 30": that day this month, or next month if it already passed.
        if let index = words.firstIndex(of: "dia"), index + 1 < words.count,
           let day = Int(words[index + 1]), (1...31).contains(day) {
            return nextDate(day: day, month: nil, from: today, calendar: calendar)
        }

        // "30/10" (day first, as written in Brazil).
        if let match = folded.firstMatch(of: #/(\d{1,2})/(\d{1,2})/#),
           let day = Int(match.1), let month = Int(match.2) {
            return nextDate(day: day, month: month, from: today, calendar: calendar)
        }

        // Anything else the system recognizes ("October 30", "next Friday").
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
           let found = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))?.date {
            let day = calendar.startOfDay(for: found)
            return day >= today ? day : nil
        }
        return nil
    }

    /// The next date with that day (and month, when given), today included.
    private static func nextDate(day: Int, month: Int?, from today: Date, calendar: Calendar) -> Date? {
        var components = DateComponents(day: day)
        if let month { components.month = month }
        return calendar.nextDate(
            after: calendar.date(byAdding: .second, value: -1, to: today) ?? today,
            matching: components,
            matchingPolicy: .strict
        ).map { calendar.startOfDay(for: $0) }
    }
}

// MARK: - Finding a chore that already exists

@Generable
nonisolated enum GeneratedSameChore: String {
    case same, different
}

/// Looks for an existing chore that a new one repeats ("Lavar louça" vs "Lavar a louça").
/// Plain code picks the candidates; the model only judges the unclear ones.
enum ChoreDuplicateFinder {

    /// Small words that don't tell chores apart.
    private static let fillers: Set<String> = [
        "a", "o", "as", "os", "de", "da", "do", "das", "dos", "e", "em", "na", "no", "nas", "nos",
        "the", "of", "and", "in", "on", "to"
    ]

    /// Lowercased words without accents and fillers; "Lavar a Louça" -> ["lavar", "louca"].
    static func words(in text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !fillers.contains($0) }
    }

    /// Whether both names have the same words once fillers, case and accents are ignored.
    static func isExactMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = words(in: lhs)
        return !left.isEmpty && left == words(in: rhs)
    }

    /// Up to `limit` chores whose name looks like `name`: same words first, then one name
    /// containing the other, then a shared word of 4+ letters ("banheiro").
    static func candidates(for name: String, in chores: [ChoreModel], limit: Int = 2) -> [ChoreModel] {
        let newWords = words(in: name)
        guard !newWords.isEmpty else { return [] }

        let scored: [(chore: ChoreModel, score: Int)] = chores.compactMap { chore in
            let existing = words(in: chore.name)
            guard !existing.isEmpty else { return nil }
            if existing == newWords { return (chore, 3) }
            if Set(newWords).isSuperset(of: existing) || Set(existing).isSuperset(of: newWords) {
                return (chore, 2)
            }
            let shared = Set(newWords).intersection(existing).filter { $0.count >= 4 }
            return shared.isEmpty ? nil : (chore, 1)
        }
        return scored.sorted { $0.score > $1.score }.prefix(limit).map(\.chore)
    }
}

extension IntelligenceManager {

    /// Asks the on-device model whether two chore names are the same task.
    ///
    /// - Returns: `nil` when AI is unavailable or the request fails; callers then treat them as
    ///   different, so nothing is blocked by mistake.
    func isSameChore(_ newName: String, as existingName: String) async -> Bool? {
        let prompt = IntelligencePrompts.SameChore.self
        guard let answer = await generate(
            GeneratedSameChore.self,
            prompt: prompt.prompt(newName: newName, existingName: existingName),
            instructions: instructions(task: prompt.task, output: .sameAsInput),
            promptID: prompt.id
        ) else { return nil }
        return answer == .same
    }
}
