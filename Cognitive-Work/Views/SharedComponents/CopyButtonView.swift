//
//  CopyButtonView.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 17/08/26.
//

import SwiftUI

/// Button that copies a string to the pasteboard and shows a temporary confirmation state.
///
/// Disabled and dimmed while ``textToCopy`` is `nil`.
///
/// > Warning: Temporary test implementation — **must be replaced**. Labels are hardcoded in
/// > Portuguese and the styling is inline rather than a reusable `ButtonStyle`.
struct CopyButtonView: View {

    // MARK: - Input

    /// Text placed on the pasteboard when tapped, or `nil` when nothing is available yet.
    let textToCopy: String?

    // MARK: - Constants

    /// How long the confirmation state stays visible after a copy.
    private static let feedbackDuration: Duration = .seconds(2)

    /// Opacity applied when the button is disabled.
    private static let disabledOpacity: Double = 0.5

    /// Corner radius of the button background.
    private static let cornerRadius: CGFloat = 8

    // MARK: - State

    /// `true` while the confirmation state is showing.
    @State private var isCopied = false

    // MARK: - Body

    var body: some View {
        Button {
            copyText()
        } label: {
            HStack {
                Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                Text(isCopied ? L10n.tr("Copiado") : (textToCopy ?? L10n.tr("Nenhum link ainda")))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .foregroundStyle(.white)
            .background(
                isCopied ? Color.green : Color.blue,
                in: .rect(cornerRadius: Self.cornerRadius)
            )
        }
        .buttonStyle(.plain)
        .disabled(textToCopy == nil)
        .opacity(textToCopy == nil ? Self.disabledOpacity : 1)
        .voiceOverLabel(textToCopy == nil ? L10n.tr("Nenhum link ainda") : L10n.tr("Copiar"))
        .voiceOverValue(isCopied ? L10n.tr("Copiado") : (textToCopy ?? ""))
        // Voice Control: the visible text is a URL nobody can say, so offer short words instead.
        .voiceControlNames([L10n.tr("Copiar"), L10n.tr("Copiar link"), L10n.tr("Compartilhar")])
    }

    // MARK: - Actions

    /// Copies ``textToCopy`` to the pasteboard and shows the confirmation for
    /// ``feedbackDuration``. Does nothing when there is no text.
    private func copyText() {
        guard let textToCopy else { return }
        UIPasteboard.general.string = textToCopy

        withAnimation { isCopied = true }
        VoiceOver.announce(L10n.tr("Copiado"))
        Task {
            try? await Task.sleep(for: Self.feedbackDuration)
            withAnimation { isCopied = false }
        }
    }
}

// MARK: - Preview

#Preview {
    CopyButtonView(textToCopy: "text to copy")
}
