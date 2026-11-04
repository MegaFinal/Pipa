//
//  ChorePhase.swift
//  Cognitive-Work
//
//  Created by anshu Li on 27/10/26.
//

import Foundation
import FoundationModels

/// When in the day's flow a chore usually happens. The on-device model only picks one of these
/// per chore; the order itself is worked out by code in ``TodayChoreOrder``, so it's stable and
/// can say why ("depois de cozinhar").
@Generable
nonisolated enum GeneratedChorePhase: String, Codable {
    /// Putting things away before cleaning ("arrumar a sala", "organizar o quarto").
    case tidyUp
    /// Preparing food ("fazer o almoço", "cozinhar").
    case cooking
    /// Cleaning up after a meal ("lavar a louça", "limpar o fogão", "limpar a mesa").
    case afterMeal
    /// Dusting and wiping surfaces, before the floor ("tirar o pó", "limpar os móveis").
    case dusting
    /// Dry floor cleaning ("varrer", "aspirar").
    case floorDry
    /// Wet floor cleaning, after sweeping ("passar pano", "lavar o chão").
    case floorWet
    /// Starting the washing machine ("lavar roupa", "colocar roupa para lavar").
    case laundryWash
    /// Hanging or drying clothes, after washing ("estender roupa", "secar roupa").
    case laundryDry
    /// Folding and putting clothes away, after drying ("dobrar roupa", "passar roupa").
    case laundryFold
    /// Taking the trash out, after the cleaning that fills it ("tirar o lixo").
    case trash
    /// Anything that doesn't depend on other chores ("regar as plantas", "limpar o banheiro").
    case other
}

extension IntelligenceManager {

    /// Where a chore fits in the day (see ``GeneratedChorePhase``). Answers are kept on this
    /// device by name, so each chore is asked about once.
    ///
    /// - Returns: `nil` when AI is unavailable or the request fails.
    func phase(ofChore name: String) async -> GeneratedChorePhase? {
        let key = ChorePhaseCache.key(for: name)
        if let cached = ChorePhaseCache.phase(for: key) { return cached }

        let prompt = IntelligencePrompts.ChorePhase.self
        guard let phase = await generate(
            GeneratedChorePhase.self,
            prompt: prompt.prompt(for: name),
            instructions: instructions(task: prompt.task, output: .sameAsInput),
            promptID: prompt.id
        ) else { return nil }

        ChorePhaseCache.store(phase, for: key)
        return phase
    }
}

/// Phases already worked out, by folded chore name, kept in `UserDefaults` on this device.
enum ChorePhaseCache {
    private static let defaultsKey = "chorePhases.v1"

    static func key(for name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func phase(for key: String) -> GeneratedChorePhase? {
        let all = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
        return all[key].flatMap(GeneratedChorePhase.init(rawValue:))
    }

    static func store(_ phase: GeneratedChorePhase, for key: String) {
        var all = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
        all[key] = phase.rawValue
        UserDefaults.standard.set(all, forKey: defaultsKey)
    }
}
