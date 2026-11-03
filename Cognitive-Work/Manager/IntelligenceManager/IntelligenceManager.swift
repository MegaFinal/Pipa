//
//  IntelligenceManager.swift
//  Cognitive-Work
//
//  Created by anshu Li on 16/10/26.
//

import Foundation
import FoundationModels

/// Shared entry point for every on-device Apple Intelligence (Foundation Models) feature.
///
/// Rules every feature follows:
/// - AI only *pre-fills* data; the person always confirms before anything is saved.
/// - A `nil` result means "no suggestion": the manual flow stays exactly as it is.
/// - What gets saved is a plain CloudKit field, so housemates whose device has no Apple
///   Intelligence see the same data.
final class IntelligenceManager {

    static let shared = IntelligenceManager()

    /// The on-device system model (4,096 tokens of context on iOS 26).
    private let model = SystemLanguageModel.default

    private init() {}

    // MARK: - Availability

    /// Whether AI features can run right now: the device supports Apple Intelligence, it's turned
    /// on, the model finished downloading, and the app's current language is supported.
    ///
    /// Check it before showing any AI UI. It can change at runtime (for example, when the model
    /// finishes downloading), so read it when a screen appears instead of caching it app-wide.
    var isAvailable: Bool {
        guard case .available = model.availability else { return false }
        return supportsAppLanguage
    }

    /// Whether the model handles the language chosen in "Configurações Gerais".
    ///
    /// Uses ``LanguageManager`` instead of `Locale.current`, because the in-app language switch
    /// doesn't necessarily update `Locale.current`.
    private var supportsAppLanguage: Bool {
        let appLanguageCode = LanguageManager.shared.locale.language.languageCode
        return model.supportedLanguages.contains { $0.languageCode == appLanguageCode }
    }

    // MARK: - Instructions

    /// Which language the model's text output must be in.
    enum OutputLanguage {
        /// Text shown to people (checklists, summaries): the app's current language.
        case appLanguage
        /// Text that must stay exactly as the person typed it (for example, a product name).
        case sameAsInput
    }

    /// Builds session instructions: the locale and language rules first, then the feature's task.
    ///
    /// - Important: Never put text typed by people in instructions. The model follows
    ///   instructions over prompts, so user text here would allow prompt injection. User text
    ///   goes in the prompt only.
    func instructions(task: String, output: OutputLanguage) -> String {
        var lines: [String] = []

        // Apple's recommended exact phrase for locales other than U.S. English; it reduces
        // hallucinations in multilingual use. Apple suggests skipping it for English.
        switch LanguageManager.shared.current {
        case .portuguese: lines.append("The person's locale is pt_BR.")
        case .spanish: lines.append("The person's locale is es_419.")
        case .french: lines.append("The person's locale is fr_FR.")
        case .korean: lines.append("The person's locale is ko_KR.")
        case .japanese: lines.append("The person's locale is ja_JP.")
        case .english: break
        }

        switch output {
        case .appLanguage:
            switch LanguageManager.shared.current {
            case .portuguese: lines.append("You MUST respond in Brazilian Portuguese.")
            case .english: lines.append("You MUST respond in English.")
            case .spanish: lines.append("You MUST respond in Latin American Spanish.")
            case .french: lines.append("You MUST respond in French.")
            case .korean: lines.append("You MUST respond in Korean.")
            case .japanese: lines.append("You MUST respond in Japanese.")
            }
        case .sameAsInput:
            lines.append("Keep any text the person wrote in the same language and spelling they used. Do not translate it.")
        }

        lines.append(task)
        return lines.joined(separator: "\n")
    }

    // MARK: - Generation

    /// Runs one single-turn request that returns a `@Generable` type, or `nil` on any failure.
    ///
    /// A new session per request keeps calls independent (a session handles one request at a
    /// time) and keeps the context window small. Every error (guardrail violation, refusal,
    /// unsupported language, context overflow, cancellation) becomes `nil`, so callers fall back
    /// to the manual flow without showing an alert.
    ///
    /// - Parameters:
    ///   - type: The `@Generable` type to produce.
    ///   - prompt: The request, including any text the person typed.
    ///   - instructions: Built with ``instructions(task:output:)``.
    ///   - promptID: The versioned prompt name (see ``IntelligencePrompts``), used in debug logs.
    func generate<Content: Generable & Sendable>(
        _ type: Content.Type,
        prompt: String,
        instructions: String,
        promptID: String
    ) async -> Content? {
        guard isAvailable else { return nil }

        let session = LanguageModelSession(instructions: instructions)
        do {
            // Greedy sampling: filling in a form should give the same answer for the same input.
            let response = try await session.respond(
                to: prompt,
                generating: type,
                options: GenerationOptions(sampling: .greedy)
            )
            return response.content
        } catch {
            #if DEBUG
            if !(error is CancellationError) {
                print("[Intelligence] \(promptID) failed: \(error)")
            }
            #endif
            return nil
        }
    }
}

