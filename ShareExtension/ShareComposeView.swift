//
//  ShareComposeView.swift
//  ShareExtension
//
//  Created by anshu Li on 18/11/26.
//

import SwiftUI

/// The share sheet's page: the shared text in an editable box, to check it before sending it to
/// Pipa. Same look as Pipa's "Adicionar com IA" page (grey background, white rounded box, ✕ on
/// the left and the blue ✓ on the right).
struct ShareComposeView: View {

    /// What happened after ✓.
    enum SendResult {
        /// Stored, and Pipa is opening.
        case openingApp
        /// Stored, but Pipa couldn't be opened from here: it shows the text next time.
        case savedForLater
        /// Not stored (the App Group isn't available).
        case failed
    }

    let initialText: String
    let onCancel: () -> Void
    let onSend: (String) -> SendResult

    @State private var text: String
    @State private var result: SendResult?
    @FocusState private var isFocused: Bool

    init(initialText: String, onCancel: @escaping () -> Void, onSend: @escaping (String) -> SendResult) {
        self.initialText = initialText
        self.onCancel = onCancel
        self.onSend = onSend
        self._text = State(initialValue: initialText)
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let result, result != .failed {
                    sent(result)
                } else {
                    editor
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGray6).ignoresSafeArea())
            .navigationTitle("Adicionar ao Pipa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Text("Cancelar"))
                }
                if result == nil || result == .failed {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            isFocused = false
                            withAnimation(.snappy) { result = onSend(trimmed) }
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12))
                                .bold()
                                .foregroundColor(.white)
                        }
                        .tint(.blue)
                        .buttonStyle(.glassProminent)
                        .disabled(trimmed.isEmpty)
                        .accessibilityLabel(Text("Enviar ao Pipa"))
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") { isFocused = false }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Checking the text

    private var editor: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                Text("Confira o texto. No Pipa, ele vira itens de compra e tarefas para você revisar.")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.subtitle)

                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Ex.:\n2kg de arroz\ndetergente\nlavar a louça amanhã")
                            .foregroundStyle(.gray.opacity(0.6))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .accessibilityHidden(true)
                    }
                    TextEditor(text: $text)
                        .scrollContentBackground(.hidden)
                        .focused($isFocused)
                        .foregroundStyle(Palette.title)
                        .accessibilityLabel(Text("Texto compartilhado"))
                }
                .font(.system(size: 17))
                .frame(minHeight: 220)
                .padding(12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                if result == .failed {
                    Text("Não foi possível enviar ao Pipa. Abra o app e tente de novo.")
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                }
            }
            .padding(22)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Sent

    private func sent(_ result: SendResult) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: result == .openingApp)
                .accessibilityHidden(true)

            Text("Enviado ao Pipa")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Palette.title)

            Text(result == .openingApp
                 ? LocalizedStringKey("Abrindo o Pipa para você revisar…")
                 : LocalizedStringKey("Abra o Pipa para revisar os itens."))
                .font(.system(size: 15))
                .foregroundStyle(Palette.subtitle)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .accessibilityElement(children: .combine)
    }
}

/// Pipa's text colors (the extension doesn't have the app's asset catalog).
private enum Palette {
    /// `titleGray`.
    static let title = Color(.displayP3, red: 0.239, green: 0.239, blue: 0.239)
    /// `subTitleGray`.
    static let subtitle = Color(.displayP3, red: 0.541, green: 0.541, blue: 0.555)
}

#Preview {
    ShareComposeView(
        initialText: "Lista do mercado:\n- 2kg arroz\n- leite\n- lavar a louça amanhã",
        onCancel: {},
        onSend: { _ in .openingApp }
    )
}
