//
//  ShopSuggestionsRow.swift
//  Cognitive-Work
//
//  Created by anshu Li on 20/10/26.
//

import SwiftUI

/// "Pode estar faltando" inside the list: the suggestions of one category, each as an AI card
/// at the end of that category's card (the same look as the chore checklist's suggestions:
/// dashed purple box on the AI tint, "Adicionar" on the right). Tapping "Adicionar" adds the
/// product (see ``ShopListSuggestionViewModel``); a long press hides it for now. Nothing is
/// ever added on its own.
struct ShopSuggestionCards: View {

    var model: ShopListSuggestionViewModel
    /// The category whose suggestions to show; `nil` shows every suggestion.
    var category: ShopItemCategory?
    /// When set, only the suggestions with these ids (the leftover box).
    var onlyIDs: Set<String>? = nil

    @State private var addingID: String?

    private var suggestions: [ShopListSuggestion] {
        model.suggestions.filter { suggestion in
            (category.map { suggestion.category == $0 } ?? true)
                && (onlyIDs.map { $0.contains(suggestion.id) } ?? true)
        }
    }

    var body: some View {
        if !suggestions.isEmpty {
            VStack(spacing: 8) {
                if category != nil {
                    ShopDottedDivider()
                        .padding(.vertical, 4)
                }
                ForEach(suggestions) { suggestion in
                    card(for: suggestion)
                }
            }
            .padding(.top, 12)
            .animation(.snappy, value: suggestions.map(\.id))
        }

    }

    private func card(for suggestion: ShopListSuggestion) -> some View {
        HStack(spacing: 10) {
            // Why it's suggested: bought regularly (clock) or goes with the list (sparkles).
            Image(systemName: icon(for: suggestion.kind))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.chorePurple)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.black)

                // How much would be added ("2 quilogramas", "1 unidade"), in black, a bit smaller.
                Text(amountText(for: suggestion))
                    .font(.system(size: 13))
                    .foregroundStyle(.black)
            }

            Spacer(minLength: 8)

            Button {
                Task { await add(suggestion) }
            } label: {
                Group {
                    if addingID == suggestion.id {
                        ProgressView()
                            .tint(.white)
                            .controlSize(.small)
                    } else {
                        Text("Adicionar")
                    }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.chorePurple.opacity(0.7), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(addingID != nil)
            .voiceOverLabel(L10n.tr("Adicionar \(suggestion.name)"))
            .voiceOverHint(reason(for: suggestion.kind))
            .voiceControlNames([L10n.tr("Adicionar \(suggestion.name)"), suggestion.name])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.aiOpacity, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.chorePurple, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        )
        .contextMenu {
            Button {
                withAnimation(.snappy) { model.dismiss(suggestion) }
            } label: {
                Label(L10n.tr("Não sugerir agora"), systemImage: "eye.slash")
            }
        }
        .accessibilityAction(named: Text(verbatim: L10n.tr("Não sugerir agora"))) {
            withAnimation(.snappy) { model.dismiss(suggestion) }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func icon(for kind: ShopListSuggestion.Kind) -> String {
        switch kind {
        case .usual: return "clock.arrow.circlepath"
        case .goesWithList: return "sparkles"
        }
    }

    private func amountText(for suggestion: ShopListSuggestion) -> String {
        "\(suggestion.quantity) \(suggestion.unit.getDisplayName(for: Double(suggestion.quantity)))"
    }

    /// Why it's suggested, read by VoiceOver (no longer shown on the card).
    private func reason(for kind: ShopListSuggestion.Kind) -> String {
        switch kind {
        case .usual(let days): return L10n.tr("Costuma entrar na lista a cada \(days) dias.")
        case .goesWithList: return L10n.tr("Combina com o que está na lista.")
        }
    }

    private func add(_ suggestion: ShopListSuggestion) async {
        addingID = suggestion.id
        defer { addingID = nil }
        if await model.add(suggestion) {
            HapticsManager.notify(.success)
            VoiceOver.announce(L10n.tr("\(suggestion.name) adicionado"))
        } else {
            HapticsManager.notify(.error)
        }
    }
}

/// Suggestions whose category has no card in the list yet (nothing of that category to buy):
/// shown under the list in their own box, titled "Pode estar faltando".
struct ShopSuggestionsLeftoverBox: View {

    var model: ShopListSuggestionViewModel
    /// Categories that already have a card in the list (their suggestions show there).
    var shownCategories: Set<ShopItemCategory>

    var body: some View {
        let leftover = model.suggestions.filter { !shownCategories.contains($0.category) }
        if !leftover.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Label {
                    Text("Pode estar faltando")
                } icon: {
                    Image(systemName: "sparkles")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.subTitleGray)
                .accessibilityAddTraits(.isHeader)

                ShopSuggestionCards(model: model, category: nil, onlyIDs: Set(leftover.map(\.id)))
            }
            .transition(.opacity)
        }
    }
}
