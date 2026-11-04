//
//  TermsOfUseView.swift
//  Cognitive-Work
//

import SwiftUI

/// The Terms of Use, presented like Apple's own: a full-height sheet that can't be swiped away,
/// "Discordar" on the left, "Concordar" on the right and a confirmation before accepting.
/// Rendering only; the decision lives in ``TermsViewModel``.
struct TermsOfUseView: View {

    /// The terms and the user's decision.
    @Bindable var viewModel: TermsViewModel

    var body: some View {
        NavigationStack {
            // MARK: - Header and sections
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    ForEach(viewModel.terms.sections) { section in
                        sectionView(section)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle(viewModel.title)
            .navigationBarTitleDisplayMode(.inline)
            // MARK: - "Discordar" / "Concordar"
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discordar") {
                        viewModel.decline()
                    }
                    .accessibilityHint(Text(L10n.tr("Recusa os termos e fecha o acesso ao app")))
                    .voiceControlNames([L10n.tr("Discordar"), L10n.tr("Recusar")])
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Concordar") {
                        viewModel.requestAcceptance()
                    }
                    .fontWeight(.semibold)
                    .accessibilityHint(Text(L10n.tr("Pede uma confirmação antes de aceitar")))
                    .voiceControlNames([L10n.tr("Concordar"), L10n.tr("Aceitar")])
                }
            }
            // MARK: - Confirmation before accepting
            .alert(viewModel.confirmationTitle, isPresented: $viewModel.isConfirmingAcceptance) {
                Button("Cancelar", role: .cancel) {}
                Button("Concordar") {
                    viewModel.accept()
                }
            } message: {
                Text(viewModel.confirmationMessage)
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Pieces

    /// The app icon, the title and the version line.
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image("loadingIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)

            Text(viewModel.title)
                .font(.system(size: 30, weight: .bold))
                .accessibilityAddTraits(.isHeader)

            Text(viewModel.subtitle)
                .font(.system(size: 15))
                .foregroundStyle(.subTitleGray)
        }
    }

    /// One numbered section: its title and paragraphs.
    private func sectionView(_ section: TermsOfUse.Section) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = section.title {
                Text(verbatim: title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.black)
                    .accessibilityAddTraits(.isHeader)
            }

            ForEach(section.paragraphs, id: \.self) { paragraph in
                paragraphView(paragraph)
            }
        }
    }

    /// One paragraph, styled by kind: text, list item, definition or link.
    @ViewBuilder
    private func paragraphView(_ paragraph: TermsOfUse.Paragraph) -> some View {
        switch paragraph {
        case .body(let text):
            Text(verbatim: text)
                .bodyStyle()

        case .item(let text):
            Text(verbatim: text)
                .bodyStyle()
                .padding(.leading, 16)

        case .definition(let term, let text):
            (Text(verbatim: term + ": ").bold() + Text(verbatim: text))
                .bodyStyle()

        case .link(let label, let value, let url):
            HStack(spacing: 0) {
                Text(verbatim: label + ": ").bold()
                if let destination = URL(string: url) {
                    Link(value, destination: destination)
                } else {
                    Text(verbatim: value)
                }
            }
            // "E-mail: contato@…" read as one element (still opens the link).
            .accessibilityElement(children: .combine)
            // Voice Control: "Toque em E-mail" rather than the whole address.
            .voiceControlNames([label, value])
            .bodyStyle()
        }
    }
}

private extension View {
    /// The text style of the terms' paragraphs.
    func bodyStyle() -> some View {
        self
            .font(.system(size: 15))
            .foregroundStyle(.titleGray)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Termos") {
    Color.white
        .sheet(isPresented: .constant(true)) {
            TermsOfUseView(viewModel: TermsViewModel(defaults: UserDefaults(suiteName: "preview-terms")!))
        }
}
