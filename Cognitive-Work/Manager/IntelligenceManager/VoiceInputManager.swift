//
//  VoiceInputManager.swift
//  Cognitive-Work
//
//  Created by anshu Li on 19/10/26.
//

import Foundation
import Speech
import AVFoundation

@Observable
final class VoiceInputManager {

    /// Whether the microphone is recording right now.
    private(set) var isListening = false

    /// Whether the language model for speech is being downloaded (first use of a language).
    private(set) var isPreparing = false

    /// Whether the last words are still being turned into text after recording stopped.
    private(set) var isFinishing = false

    /// Recording, preparing or finishing: the text isn't final yet.
    var isBusy: Bool { isListening || isPreparing || isFinishing }

    /// What has been recognized so far in the current recording.
    private(set) var transcript = ""

    /// Why the last attempt failed, ready to show under the field.
    private(set) var errorMessage: String?

    @ObservationIgnored private let audioEngine = AVAudioEngine()

    // SpeechAnalyzer path
    @ObservationIgnored private var analyzer: SpeechAnalyzer?
    @ObservationIgnored private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    @ObservationIgnored private var resultsTask: Task<Void, Never>?
    /// Phrases the analyzer already finalized; the phrase still being heard is added after them.
    @ObservationIgnored private var finalizedText = ""

    // SFSpeechRecognizer fallback
    @ObservationIgnored private var legacyRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var legacyTask: SFSpeechRecognitionTask?

    // MARK: - Recording

    /// Asks for permission if needed, then starts recording and recognizing.
    ///
    /// Listens in the app's language (``LanguageManager/current``): recognizers need the language
    /// up front, and the person is expected to speak the language they chose for the app.
    ///
    /// - Parameter contextualStrings: Words likely to be said that the recognizer may not know,
    ///   such as the housemates' names ("Anshu"), so they're recognized correctly.
    func start(contextualStrings: [String]) async {
        guard !isBusy else { return }
        errorMessage = nil
        transcript = ""
        finalizedText = ""

        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = L10n.tr("Permita o microfone e o reconhecimento de fala nos Ajustes.")
            return
        }

        do {
            try startAudioSession()
        } catch {
            errorMessage = L10n.tr("Não foi possível usar o microfone.")
            return
        }

        let locale = LanguageManager.shared.current.locale
        do {
            try await startAnalyzer(locale: locale, contextualStrings: contextualStrings)
        } catch {
            // SpeechAnalyzer can't run here (device or language): use the older recognizer.
            tearDownAnalyzer()
            await startLegacy(locale: locale, contextualStrings: contextualStrings)
        }
    }

    /// Stops recording. The last words are still turned into text (``isFinishing``).
    func stop() {
        guard isListening else { return }
        stopAudio()
        isListening = false

        if let analyzer {
            isFinishing = true
            inputContinuation?.finish()
            inputContinuation = nil
            Task {
                // Finalizes what was heard, then ends the results stream (see `listen(to:)`).
                try? await analyzer.finalizeAndFinishThroughEndOfInput()
            }
        } else {
            legacyRequest?.endAudio()
            legacyRequest = nil
        }
    }

    /// Stops everything and drops results still on their way (the screen is closing).
    func cancel() {
        if isListening { stopAudio() }
        isListening = false
        isPreparing = false
        isFinishing = false
        tearDownAnalyzer()
        legacyRequest?.endAudio()
        legacyRequest = nil
        legacyTask?.cancel()
        legacyTask = nil
    }

    // MARK: - SpeechAnalyzer (iOS 26)

    /// Picks the best transcriber for `locale`, downloads its model if needed, and starts feeding
    /// it microphone audio. Throws when the device or the language isn't supported.
    private func startAnalyzer(locale: Locale, contextualStrings: [String]) async throws {
        let module: any SpeechModule
        if SpeechTranscriber.isAvailable,
           let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            // Newest model; progressive = text appears while the person is still speaking.
            let transcriber = SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
            module = transcriber
            resultsTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        self?.receive(String(result.text.characters), isFinal: result.isFinal)
                    }
                } catch {
                    self?.receiveFailure()
                }
                self?.resultsDidEnd()
            }
        } else if let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            // Short, live dictation: about a minute of audio, text while speaking, punctuation.
            let transcriber = DictationTranscriber(locale: supported, preset: .progressiveShortDictation)
            module = transcriber
            resultsTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        self?.receive(String(result.text.characters), isFinal: result.isFinal)
                    }
                } catch {
                    self?.receiveFailure()
                }
                self?.resultsDidEnd()
            }
        } else {
            throw VoiceInputError.unsupportedLanguage
        }

        // First use of a language: download its speech model (shared with other apps afterwards).
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            isPreparing = true
            defer { isPreparing = false }
            try await installation.downloadAndInstall()
        }

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw VoiceInputError.noAudioFormat
        }

        let analyzer = SpeechAnalyzer(modules: [module])
        let context = AnalysisContext()
        context.contextualStrings[.general] = contextualStrings
        try await analyzer.setContext(context)

        let (inputSequence, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        try await analyzer.start(inputSequence: inputSequence)
        self.analyzer = analyzer
        self.inputContinuation = continuation

        // The microphone's format rarely matches the model's, so convert every buffer.
        // (`AnalyzerInputConverter` would do this, but it needs iOS 27.)
        let inputNode = audioEngine.inputNode
        let microphoneFormat = inputNode.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: microphoneFormat, to: analyzerFormat) else {
            throw VoiceInputError.noAudioFormat
        }
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: microphoneFormat,
            block: Self.analyzerTapBlock(converter: converter, outputFormat: analyzerFormat, continuation: continuation)
        )
        audioEngine.prepare()
        try audioEngine.start()
        isListening = true
    }

    /// A phrase from the analyzer. Volatile phrases are replaced as the guess improves; final
    /// ones are kept and the next phrase is added after them.
    private func receive(_ text: String, isFinal: Bool) {
        if isFinal {
            finalizedText = Self.joined(finalizedText, text)
            transcript = finalizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            transcript = Self.joined(finalizedText, text).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func receiveFailure() {
        if isListening { stopAudio() }
        isListening = false
        if transcript.isEmpty {
            errorMessage = L10n.tr("Não entendi. Tente de novo.")
        }
    }

    /// The results stream ended: everything said is in ``transcript``.
    private func resultsDidEnd() {
        isFinishing = false
        analyzer = nil
        resultsTask = nil
    }

    private func tearDownAnalyzer() {
        inputContinuation?.finish()
        inputContinuation = nil
        resultsTask?.cancel()
        resultsTask = nil
        if let analyzer {
            Task { await analyzer.cancelAndFinishNow() }
        }
        analyzer = nil
    }

    /// Adds a phrase after the text so far, with a space between them when needed.
    private static func joined(_ text: String, _ phrase: String) -> String {
        guard !text.isEmpty, !phrase.isEmpty,
              !text.hasSuffix(" "), !phrase.hasPrefix(" ")
        else { return text + phrase }
        return text + " " + phrase
    }

    // MARK: - SFSpeechRecognizer fallback

    /// The iOS 10 recognizer, on device when the language allows it.
    private func startLegacy(locale: Locale, contextualStrings: [String]) async {
        guard await Self.requestSpeechAuthorization() else {
            errorMessage = L10n.tr("Permita o microfone e o reconhecimento de fala nos Ajustes.")
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            errorMessage = L10n.tr("Reconhecimento de fala indisponível agora.")
            return
        }

        do {
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            request.contextualStrings = contextualStrings
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
            legacyRequest = request

            let inputNode = audioEngine.inputNode
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(
                onBus: 0,
                bufferSize: 1024,
                format: inputNode.outputFormat(forBus: 0),
                block: Self.legacyTapBlock(appendingTo: request)
            )
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true

            legacyTask = recognizer.recognitionTask(
                with: request,
                resultHandler: Self.legacyResultHandler { [weak self] text, isFinal, didFail in
                    self?.receiveLegacy(text: text, isFinal: isFinal, didFail: didFail)
                }
            )
        } catch {
            stopAudio()
            isListening = false
            errorMessage = L10n.tr("Não foi possível usar o microfone.")
        }
    }

    private func receiveLegacy(text: String?, isFinal: Bool, didFail: Bool) {
        if let text, !text.isEmpty {
            transcript = text
        }
        guard isFinal || didFail else { return }

        // The recognizer ended by itself (silence, the one-minute limit, an error).
        if isListening { stop() }
        legacyTask = nil
        if didFail && transcript.isEmpty {
            errorMessage = L10n.tr("Não entendi. Tente de novo.")
        }
    }

    // MARK: - Audio

    private func startAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func stopAudio() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Off-main-thread helpers

    nonisolated private static func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Audio thread: converts each microphone buffer to the analyzer's format and queues it.
    nonisolated private static func analyzerTapBlock(
        converter: AVAudioConverter,
        outputFormat: AVAudioFormat,
        continuation: AsyncStream<AnalyzerInput>.Continuation
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            let ratio = outputFormat.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
            guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

            var didProvideInput = false
            var conversionError: NSError?
            let status = converter.convert(to: converted, error: &conversionError) { _, inputStatus in
                // Hand over this one buffer, then report that there's nothing more for now.
                if didProvideInput {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                didProvideInput = true
                inputStatus.pointee = .haveData
                return buffer
            }
            guard status != .error, converted.frameLength > 0 else { return }
            continuation.yield(AnalyzerInput(buffer: converted))
        }
    }

    /// Audio thread: hands buffers to the legacy request.
    nonisolated private static func legacyTapBlock(
        appendingTo request: SFSpeechAudioBufferRecognitionRequest
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            request.append(buffer)
        }
    }

    /// The legacy recognizer's handler: reads what it needs on the recognizer's queue, then hops
    /// to the main actor.
    nonisolated private static func legacyResultHandler(
        _ onUpdate: @escaping @MainActor @Sendable (String?, Bool, Bool) -> Void
    ) -> (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let didFail = error != nil
            Task { @MainActor in
                onUpdate(text, isFinal, didFail)
            }
        }
    }
}

/// Why the SpeechAnalyzer path couldn't start; the manager then falls back to SFSpeechRecognizer.
private enum VoiceInputError: Error {
    case unsupportedLanguage
    case noAudioFormat
}
