//
//  VoiceControlButton.swift
//  Cognitive-Work
//
//  Created by anshu Li on 19/10/26.
//

import SwiftUI

/// The voice part of the AI prompts: the mic button and any error. It listens in the app's
/// language (see ``VoiceInputManager/start(contextualStrings:)``).
/// Shared by ``ItemIntelligentSheet`` (one item) and ``AddMoreItensInteligence`` (several), so
/// both work the same way. The spoken text goes into `text` live; the person still checks it and
/// confirms with the sheet's own button.
struct VoiceControlButton: View {

    /// The prompt's text field.
    @Binding var text: String

    /// Owned by the sheet, so it can lock its own controls while ``VoiceInputManager/isBusy``.
    var voice: VoiceInputManager

    /// Words the speech recognizer should expect, such as the housemates' names.
    var contextualStrings: [String]

    /// One item: speaking replaces the text. A list: each recording adds a new line after what's
    /// already there, so items can be said one at a time.
    var appendsToText = false

    /// Called right before recording starts (for example, to close the keyboard).
    var onStart: () -> Void = {}

    /// The text before this recording, kept when ``appendsToText`` is on.
    @State private var textBeforeRecording = ""

    var body: some View {
        VStack(spacing: 14) {
            micButton

            if let error = voice.errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        // Spoken words fill the field as they're recognized.
        .onChange(of: voice.transcript) { _, spoken in
            guard !spoken.isEmpty else { return }
            if appendsToText && !textBeforeRecording.isEmpty {
                text = textBeforeRecording + "\n" + spoken
            } else {
                text = spoken
            }
        }
        .onChange(of: voice.isListening) { _, isListening in
            VoiceOver.announce(isListening ? L10n.tr("Ouvindo") : text)
        }
        .onDisappear {
            voice.cancel()
        }
    }

    /// What the mic button is doing right now.
    private var micCaption: String {
        if voice.isPreparing { return L10n.tr("Baixando o modelo de voz…") }
        if voice.isListening { return L10n.tr("Ouvindo… toque para parar") }
        if voice.isFinishing { return L10n.tr("Transcrevendo…") }
        return L10n.tr("Toque para falar")
    }

    /// Tap to start talking, tap again to stop. Red while recording, like the system recorder.
    private var micButton: some View {
        Button {
            HapticsManager.selection()
            if voice.isListening {
                voice.stop()
            } else if !voice.isBusy {
                onStart()
                textBeforeRecording = text.trimmingCharacters(in: .whitespacesAndNewlines)
                Task { await voice.start(contextualStrings: contextualStrings) }
            }
        } label: {
            VStack(spacing: 24) {
                Group {
                    if voice.isPreparing || voice.isFinishing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: voice.isListening ? "stop.fill" : "mic.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.white)
                            .symbolEffect(.pulse, isActive: voice.isListening)
                    }
                }
                .frame(width: 64, height: 64)
                .background(Circle().fill(voice.isListening ? Color.red : Color.black))

                Text(micCaption)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.subTitleGray)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .voiceOverLabel(voice.isListening ? L10n.tr("Parar de ouvir") : L10n.tr("Falar"))
        .voiceControlNames(voice.isListening
            ? [L10n.tr("Parar"), L10n.tr("Parar de ouvir")]
            : [L10n.tr("Falar"), L10n.tr("Microfone")])
    }
}

