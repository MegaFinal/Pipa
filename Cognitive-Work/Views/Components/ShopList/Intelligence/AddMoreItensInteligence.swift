//
//  AddMoreShoppingListInteligence.swift
//  Cognitive-Work
//
//  Created by anshu Li on 19/10/26.
//

import SwiftUI

/// Adds several shopping items at once with the on-device model.
///
/// Two steps in one sheet: the person writes or dictates the items (one per line), then reviews
/// the cards the model made and unticks any it got wrong. Nothing is saved until they confirm,
/// and saving goes through ``ShopListViewModel/addSuggestedItems(_:)``, so validation and points
/// are the same as adding by hand.
struct AddMoreItensInteligence: View {

    var viewModel: ShopListViewModel

    @Environment(\.dismiss) private var dismiss

    /// What the person typed or dictated.
    @State private var text = ""
    /// The items the model found; `nil` while still on the writing step.
    @State private var suggestions: [ShopItemSuggestion]?
    /// Positions in ``suggestions`` the person keeps (all of them by default).
    @State private var included: Set<Int> = []
    @State private var isGenerating = false
    @State private var isSaving = false
    /// Shown under the text field (nothing found) or above the button (a save failed).
    @State private var errorText: String?
    @FocusState private var isTextFocused: Bool
    /// Speech for the writing step; each recording adds a line to the list.
    @State private var voice = VoiceInputManager()
    /// The suggestion being edited in ``ShopListItemFormView`` (its position in ``suggestions``).
    @State private var editing: EditingDraft?

    // Repeated items: suggestions that are the same product as one already on the list.
    /// The item already on the list, by position in ``suggestions``.
    @State private var duplicates: [Int: ShopListItem] = [:]
    /// Positions whose quantity is added to that existing item instead of creating a new card.
    @State private var merging: Set<Int> = []
    /// Whether the check is still running; adding waits for it, so nothing slips through.
    @State private var isCheckingDuplicates = false
    @State private var duplicateCheck: Task<Void, Never>?

    /// Identifies the suggestion opened for editing, for `.sheet(item:)`.
    private struct EditingDraft: Identifiable {
        let id: Int
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let suggestions {
                    review(suggestions)
                } else {
                    writing
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGray6).ignoresSafeArea())
            .navigationTitle("Adicionar com IA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .disabled(isSaving)
                    .voiceOverLabel(L10n.tr("Cancelar"))
                    .voiceControlNames([L10n.tr("Fechar"), L10n.tr("Cancelar")])
                }

                if suggestions == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        if isGenerating {
                            ProgressView()
                        } else {
                            Button {
                                Task { await generate() }
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .bold()
                                    .foregroundColor(.white)
                            }
                            .tint(.blue)
                            .buttonStyle(.glassProminent)
                            .disabled(trimmedText.count < 3 || voice.isBusy)
                            .voiceOverLabel(L10n.tr("Gerar itens"))
                            .voiceControlNames([L10n.tr("Gerar itens"), L10n.tr("Próximo"), L10n.tr("Continuar")])
                        }
                    }
                } else if let suggestions {
                    // Review step: "Adicionar itens" is the blue checkmark at the top right,
                    // like confirming the single-item form.
                    ToolbarItem(placement: .confirmationAction) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Button {
                                Task { await save(suggestions) }
                            } label: {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12))
                                    .bold()
                                    .foregroundColor(.white)
                            }
                            .tint(.blue)
                            .buttonStyle(.glassProminent)
                            .disabled(included.isEmpty || isCheckingDuplicates)
                            .voiceOverLabel(L10n.tr("Adicionar itens (\(included.count))"))
                            .voiceControlNames([L10n.tr("Adicionar"), L10n.tr("Confirmar"), L10n.tr("OK")])
                        }
                    }
                }

                // Closes the keyboard from the text box (Return adds a new line there).
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") { isTextFocused = false }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGray6))
        .interactiveDismissDisabled(isSaving)
        // The arrow on a card opens the usual item form; confirming replaces that suggestion.
        .sheet(item: $editing) { draft in
            if let suggestions, suggestions.indices.contains(draft.id) {
                ShopListItemFormView(
                    mode: .draft(suggestions[draft.id], onConfirm: { edited in
                        self.suggestions?[draft.id] = edited
                        included.insert(draft.id)
                        // The name may have changed: look for a repeated item again.
                        recheckDuplicate(at: draft.id, for: edited)
                    }),
                    availableUsers: viewModel.houseUsers,
                    currentUser: viewModel.currentUser,
                    viewModel: viewModel
                )
            }
        }
    }

    // MARK: - Step 1: writing

    /// Scrolls with the keyboard up, so the hint at the top stays reachable.
    private var writing: some View {
        ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: 24) {
            Text("Descreva o que deseja adicionar na sua lista, com quantidade, preço(opcional) e quem irá consumir.")
                .font(.system(size: 15))
                .foregroundStyle(.subTitleGray)

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Ex.:\n2kg de arroz, R$ 25, eu e Ana\ndetergente para todos\n1 L de leite")
                        .foregroundStyle(.gray.opacity(0.6))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .accessibilityHidden(true)
                }

                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .focused($isTextFocused)
                    // Locked while speech is still turning into text.
                    .disabled(voice.isBusy)
                    // Same words as the hint above it.
                    .voiceOverLabel(L10n.tr("Descreva o que deseja adicionar na sua lista, com quantidade, preço(opcional) e quem irá consumir."))
            }
            .font(.system(size: 17))
            .frame(minHeight: 180)
            .padding(12)
            .background(
                Color.white,
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )

            if let errorText {
                Text(errorText)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
            }
            
            Text("Ou")
                .font(.system(size: 13))
                .fontWeight(.semibold)
                .foregroundStyle(.subTitleGray)
                .frame(maxWidth: .infinity, alignment: .center)

            // Say the items instead of typing; each recording becomes a new line, and the text
            // can still be fixed before generating the cards.
            VoiceControlButton(
                text: $text,
                voice: voice,
                contextualStrings: viewModel.houseUsers.map(\.name),
                appendsToText: true,
                onStart: { isTextFocused = false }
            )
        }
        .padding(22)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Step 2: review

    private func review(_ suggestions: [ShopItemSuggestion]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Revise os itens antes de adicionar.")
                .font(.system(size: 15))
                .foregroundStyle(.subTitleGray)
                .padding(.horizontal, 22)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                        reviewRow(
                            suggestion,
                            duplicate: duplicates[index],
                            isMerging: merging.contains(index),
                            setMerging: { shouldMerge in
                                HapticsManager.selection()
                                if shouldMerge { merging.insert(index) } else { merging.remove(index) }
                            },
                            isIncluded: included.contains(index),
                            toggle: {
                                HapticsManager.selection()
                                if included.contains(index) {
                                    included.remove(index)
                                } else {
                                    included.insert(index)
                                }
                            },
                            edit: {
                                HapticsManager.selection()
                                editing = EditingDraft(id: index)
                            }
                        )
                    }
                }
                .padding(.horizontal, 22)

                // Right under the list (not pinned to the bottom): status, then "Editar texto".
                VStack(spacing: 12) {
                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                    }
                    if isCheckingDuplicates {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Procurando itens repetidos…")
                                .font(.system(size: 13))
                                .foregroundStyle(.subTitleGray)
                        }
                    }
                    
                    // Back to the text, kept as typed, to fix it and try again.
                    Button {
                        errorText = nil
                        resetDuplicates()
                        withAnimation(.snappy) { self.suggestions = nil }
                    } label: {
                        Label("Editar texto", systemImage: "pencil.line")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.titleGray)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 22)
                .padding(.horizontal, 22)
            }
        }
        .padding(.top, 22)
    }

    /// One proposed item. The checkbox in front includes or leaves it out; the rest of the card,
    /// with the arrow at the end, opens it in the item form to fix anything before adding.
    private func reviewRow(
        _ suggestion: ShopItemSuggestion,
        duplicate: ShopListItem?,
        isMerging: Bool,
        setMerging: @escaping (Bool) -> Void,
        isIncluded: Bool,
        toggle: @escaping () -> Void,
        edit: @escaping () -> Void
    ) -> some View {
        // Same default as saving: no one mentioned means the whole house.
        let consumers = suggestion.consumers ?? viewModel.houseUsers
        let category = suggestion.category

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button(action: toggle) {
                    Image(systemName: isIncluded ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24))
                        .foregroundStyle(isIncluded ? category.color : Color.gray.opacity(0.5))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .voiceOverLabel(L10n.tr("Incluir \(suggestion.name)"))
                .voiceOverTraits(.isSelected, when: isIncluded)
                .voiceControlNames([L10n.tr("Incluir \(suggestion.name)")])

                Button(action: edit) {
                    HStack(spacing: 12) {
                        // Category icons are image assets now; SymbolImage also handles SF Symbols.
                        SymbolImage(name: category.symbol)
                            .foregroundStyle(category.color)
                            .frame(width: 32, height: 32)
                            .frame(width: 51, height: 56)
                            .background(
                                category.softColor.opacity(0.45),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(suggestion.name)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.titleGray)
                            
                            // One line each, with an icon: amount (and price), category, people.
                            infoLine("dumbbell.fill", amountText(for: suggestion))
                            infoLine("tag.fill", category.displayName)
                            infoLine("person.2.fill", peopleText(for: suggestion, consumers: consumers))

                            if let share = ShopListViewModel.shareText(
                                unitPrice: suggestion.unitPrice,
                                quantity: suggestion.quantity,
                                consumerCount: consumers.count
                            ) {
                                Text(share)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.titleGray)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.subTitleGray)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .voiceOverHint(L10n.tr("Toque duas vezes para editar."))
                .voiceControlNames([L10n.tr("Editar \(suggestion.name)")])
            }

            if let duplicate {
                duplicateBar(for: suggestion, existing: duplicate, isMerging: isMerging, setMerging: setMerging)
            }
        }
        .padding(.vertical, 12)
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .background(
            Color.white,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .opacity(isIncluded ? 1 : 0.5)
    }

    /// Says the product is already on the list and lets the person add to that item's quantity
    /// or keep a separate card. Adding quantities only works in the same unit.
    private func duplicateBar(
        for suggestion: ShopItemSuggestion,
        existing: ShopListItem,
        isMerging: Bool,
        setMerging: @escaping (Bool) -> Void
    ) -> some View {
        let sameUnit = existing.unitMeasurement == suggestion.unit
        let existingText = "\(existing.name) · \(existing.quantity) \(existing.unitMeasurement.getDisplayName(for: Double(existing.quantity)))"

        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.orange)
                .frame(width: 44)
                .accessibilityHidden(true)

            Text(sameUnit
                 ? L10n.tr("Já está na lista: \(existingText)")
                 : L10n.tr("Já está na lista, em outra unidade: \(existingText)"))
                .font(.system(size: 13))
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)

            if sameUnit {
                Menu {
                    // Plain options in a picker: only the chosen one gets the system checkmark,
                    // so it's clear which is picked (icons on both made them look alike).
                    Picker(selection: Binding(get: { isMerging }, set: { setMerging($0) })) {
                        Text(L10n.tr("Adicionar como novo item")).tag(false)
                        Text(L10n.tr("Somar à quantidade (\(existing.quantity) → \(existing.quantity + suggestion.quantity))")).tag(true)
                    } label: {
                        EmptyView()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(isMerging ? L10n.tr("Somar") : L10n.tr("Novo item"))
                        Image(systemName: "chevron.up.chevron.down")
                            .imageScale(.small)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.titleGray)
                }
                .voiceOverLabel(L10n.tr("Item repetido"))
                .voiceOverValue(isMerging ? L10n.tr("Somar") : L10n.tr("Novo item"))
            }
        }
    }

    /// A small grey line with its icon in front ("􀝾 2 quilogramas").
    private func infoLine(_ systemImage: String, _ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 11))
                .frame(width: 16)
        }
        .font(.system(size: 13))
        .foregroundStyle(.subTitleGray)
    }

    /// "2 quilogramas · R$ 25,00" (the price only when one was said).
    private func amountText(for suggestion: ShopItemSuggestion) -> String {
        var parts = ["\(suggestion.quantity) \(suggestion.unit.getDisplayName(for: Double(suggestion.quantity)))"]
        if let unitPrice = suggestion.unitPrice {
            let format = FloatingPointFormatStyle<Double>.Currency(code: "BRL").locale(L10n.locale)
            parts.append((unitPrice * Double(suggestion.quantity)).formatted(format))
        }
        return parts.joined(separator: " · ")
    }

    /// "Ana, Bruno", or "Todos" when it's for the whole house (said, or nobody named, which is
    /// the default when saving).
    private func peopleText(for suggestion: ShopItemSuggestion, consumers: [UserModel]) -> String {
        let house = Set(viewModel.houseUsers.map(\.id))
        let isEveryone = suggestion.consumers == nil
            || (!house.isEmpty && Set(consumers.map(\.id)) == house)
        return isEveryone ? L10n.tr("Todos") : consumers.map(\.name).joined(separator: ", ")
    }

    // MARK: - Actions

    /// Asks the model for the items; on success moves to the review step with all of them ticked.
    private func generate() async {
        isGenerating = true
        errorText = nil
        isTextFocused = false
        defer { isGenerating = false }

        guard let result = await viewModel.suggestItems(from: trimmedText), !result.isEmpty else {
            let message = L10n.tr("Nenhum item encontrado. Tente escrever de outro jeito.")
            errorText = message
            VoiceOver.announce(message)
            HapticsManager.notify(.error)
            return
        }

        withAnimation(.snappy) {
            included = Set(result.indices)
            suggestions = result
        }
        HapticsManager.notify(.success)
        checkDuplicates(in: result)
    }

    /// Looks for each suggestion among the items still to buy (``ShopListViewModel/duplicateItem(named:)``).
    /// Cards are shown right away and marked as the answers come in. When the units match, the
    /// default is to add to the existing quantity, so the list doesn't end up with two cards.
    private func checkDuplicates(in list: [ShopItemSuggestion]) {
        resetDuplicates()
        isCheckingDuplicates = true
        duplicateCheck = Task {
            defer { isCheckingDuplicates = false }
            for index in list.indices {
                let existing = await viewModel.duplicateItem(named: list[index].name)
                guard !Task.isCancelled else { return }
                setDuplicate(existing, at: index, for: list[index])
            }
        }
    }

    /// Checks one suggestion again after it was edited.
    private func recheckDuplicate(at index: Int, for suggestion: ShopItemSuggestion) {
        Task {
            let existing = await viewModel.duplicateItem(named: suggestion.name)
            guard suggestions?.indices.contains(index) == true else { return }
            setDuplicate(existing, at: index, for: suggestion)
        }
    }

    private func setDuplicate(_ existing: ShopListItem?, at index: Int, for suggestion: ShopItemSuggestion) {
        withAnimation(.snappy) {
            duplicates[index] = existing
            // "Novo item" by default; the person picks "Somar" in the menu if they want it.
            merging.remove(index)
        }
    }

    private func resetDuplicates() {
        duplicateCheck?.cancel()
        duplicateCheck = nil
        isCheckingDuplicates = false
        duplicates = [:]
        merging = []
    }

    /// Saves the ticked items: repeated ones set to "add up" go into the existing item, the rest
    /// become new items. Stops at the first failure; the ones already saved leave the list, so
    /// trying again never adds them twice.
    private func save(_ all: [ShopItemSuggestion]) async {
        isSaving = true
        errorText = nil
        defer { isSaving = false }

        let chosenIndices = all.indices.filter { included.contains($0) }
        var savedIndices = Set<Int>()
        for index in chosenIndices {
            let suggestion = all[index]
            let success: Bool
            if merging.contains(index), let existing = duplicates[index] {
                // People named for this entry join the existing item's split; "not said" adds no one.
                success = await viewModel.merge(
                    into: existing,
                    adding: suggestion.quantity,
                    consumers: suggestion.consumers ?? []
                )
            } else {
                success = await viewModel.addSuggestedItems([suggestion]) == 1
            }
            guard success else { break }
            savedIndices.insert(index)
        }

        if savedIndices.count == chosenIndices.count {
            HapticsManager.notify(.success)
            dismiss()
            return
        }

        // Keep only what wasn't saved, moving each card's state to its new position.
        let remaining = all.indices.filter { !savedIndices.contains($0) }
        var newIncluded = Set<Int>()
        var newDuplicates: [Int: ShopListItem] = [:]
        var newMerging = Set<Int>()
        for (newIndex, oldIndex) in remaining.enumerated() {
            if included.contains(oldIndex) { newIncluded.insert(newIndex) }
            if let existing = duplicates[oldIndex] { newDuplicates[newIndex] = existing }
            if merging.contains(oldIndex) { newMerging.insert(newIndex) }
        }
        suggestions = remaining.map { all[$0] }
        included = newIncluded
        duplicates = newDuplicates
        merging = newMerging
        errorText = viewModel.errorMessage ?? L10n.tr("Tente novamente.")
        viewModel.clearError()
        HapticsManager.notify(.error)
    }
}
