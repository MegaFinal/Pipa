//
//  AudioIntelligentSheet.swift
//  Cognitive-Work
//
//  Created by anshu Li on 19/10/26.
//

import SwiftUI

/// The AI prompt of ``ShopListItemFormView``: the person types or says the item, sees the text,
/// fixes it if the recognizer misheard, and only then confirms.
struct ItemIntelligentSheet: View {

    /// What will be sent to the model; spoken words replace it live.
    @Binding var text: String

    /// Words the speech recognizer should expect, such as the housemates' names.
    var contextualStrings: [String]

    /// Called when the person confirms the text.
    var onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var voice = VoiceInputManager()
    @FocusState private var isTextFocused: Bool

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("Descreva o item, a quantidade, o preço e para quem é.")
                    .font(.system(size: 15))
                    .foregroundStyle(.subTitleGray)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // The text the person confirms: typed, or filled in live while they speak.
                TextField("Ex.: 2kg de arroz, R$ 25, eu e Ana", text: $text, axis: .vertical)
                    .lineLimit(2...5)
                    .font(.system(size: 17))
                    .focused($isTextFocused)
                    // Locked while speech is still turning into text.
                    .disabled(voice.isBusy)
                    .padding(16)
                    .background(
                        Color(.systemGray6).opacity(0.5),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                    )
                    .voiceOverLabel(L10n.tr("Descreva o item, a quantidade, o preço e para quem é."))

                // Mic and errors (listens in the app's language); shared with the list page's AI sheet.
                VoiceControlButton(
                    text: $text,
                    voice: voice,
                    contextualStrings: contextualStrings,
                    onStart: { isTextFocused = false }
                )

                Spacer(minLength: 0)

                Button {
                    voice.stop()
                    onConfirm()
                    dismiss()
                } label: {
                    Text("Preencher")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent)
                .tint(.black)
                .disabled(trimmedText.count < 3 || voice.isBusy)
            }
            .padding(22)
            .navigationTitle("Preencher com IA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .voiceOverLabel(L10n.tr("Cancelar"))
                    .voiceControlNames([L10n.tr("Fechar"), L10n.tr("Cancelar")])
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
