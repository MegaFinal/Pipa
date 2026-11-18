//
//  SharedImportView.swift
//  Cognitive-Work
//
//  Created by anshu Li on 18/11/26.
//

import SwiftUI

/// The page a text shared from another app opens on (Share Extension → "Adicionar ao Pipa").
///
/// Same look and flow as "Adicionar com IA" and the receipt review: the shared text on top, then
/// one card per item, grouped in "Compras" and "Tarefas". The checkbox keeps or leaves out a
/// card, the rest of the card opens the usual form to fix it, and holding a card moves it to the
/// other group. Nothing is saved until the ✓.
///
/// Free: names and amounts (shopping) or names and days (chores), read by code. Premium: the
/// on-device model fills every field, marked with ✨.
struct SharedImportView: View {

    @State private var viewModel: SharedImportViewModel
    @Environment(\.dismiss) private var dismiss

    /// The shopping card open in ``ShopListItemFormView``.
    @State private var editingShop: SharedImportViewModel.ShopCard?
    /// The chore card open in ``CreateAndEditChoreView``.
    @State private var editingChore: SharedImportViewModel.ChoreCard?
    @State private var paywall: PremiumFeature?
    /// "Editar texto": the shared text in a text box, to fix it and read it again.
    @State private var isEditingText = false
    @FocusState private var isTextFocused: Bool

    init(entry: SharedInbox.Entry) {
        self._viewModel = State(initialValue: SharedImportViewModel(entry: entry))
    }

    private var isBusy: Bool {
        viewModel.isLoading || viewModel.isReading || viewModel.isSaving
    }

    var body: some View {
        Group {
            if case .receipt(let review) = viewModel.mode {
                // A shared receipt or order: the same review as scanning one from "Pendências",
                // already read.
                ReceiptReviewView(viewModel: review, shopList: viewModel.shopList)
            } else {
                NavigationStack {
                    Group {
                        if viewModel.isLoading {
                            ProgressView()
                                .voiceOverLabel(L10n.tr("Carregando sua casa..."))
                        } else if case .locked = viewModel.mode {
                            lockedFiles
                        } else if isEditingText {
                            textEditor
                        } else {
                            review
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGray6).ignoresSafeArea())
                    .navigationTitle("Adicionar ao Pipa")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { toolbar }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGray6))
        .interactiveDismissDisabled(viewModel.isSaving)
        .premiumPaywall($paywall)
        .task { await viewModel.start() }
        // Bought Premium here: read the photos, or the text again with the AI.
        .onChange(of: PremiumManager.shared.isPremium) { _, isPremium in
            guard isPremium, !viewModel.isLoading else { return }
            if viewModel.entry.hasFiles {
                Task { await viewModel.readFiles() }
            } else if viewModel.usesAI {
                Task { await viewModel.read() }
            }
        }
        .onDisappear {
            // The tabs hold their own copies of the house: reload them if anything was added.
            if viewModel.didSaveAnything {
                NotificationCenter.default.post(name: .cloudKitDidChange, object: nil)
            }
            // The shared photos are no longer needed (the entry already left the inbox).
            SharedInbox.deleteFiles(of: viewModel.entry)
        }
        .sheet(item: $editingShop) { card in
            ShopListItemFormView(
                mode: .draft(draft(for: card), onConfirm: { edited in
                    viewModel.replace(card.id, with: edited)
                }),
                availableUsers: viewModel.shopList.houseUsers,
                currentUser: viewModel.shopList.currentUser,
                viewModel: viewModel.shopList
            )
        }
        // The usual chore form, filling this card only: ✓ comes back here, nothing is saved yet.
        .sheet(item: $editingChore) { card in
            CreateAndEditChoreView(
                importing: card.activeForm,
                sourceLine: card.isFromAI && !card.usesExisting ? card.line : nil,
                onDone: { viewModel.choreEdited(card.id) }
            )
        }
    }

    /// What the item form opens with. Free cards open with nobody picked as responsible (the
    /// form would otherwise pick the whole house), so ✓ there waits until the person chooses.
    private func draft(for card: SharedImportViewModel.ShopCard) -> ShopItemSuggestion {
        guard card.needsPeople else { return card.suggestion }
        let suggestion = card.suggestion
        return ShopItemSuggestion(
            input: suggestion.input,
            name: suggestion.name,
            quantity: suggestion.quantity,
            unit: suggestion.unit,
            category: suggestion.category,
            totalPrice: suggestion.totalPrice,
            consumers: []
        )
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .disabled(viewModel.isSaving)
            .voiceOverLabel(L10n.tr("Cancelar"))
            .voiceControlNames([L10n.tr("Fechar"), L10n.tr("Cancelar")])
        }

        ToolbarItem(placement: .confirmationAction) {
            if isEditingText {
                // Reads the edited text again (same arrow as "Adicionar com IA").
                Button {
                    isTextFocused = false
                    withAnimation(.snappy) { isEditingText = false }
                    Task { await viewModel.read() }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .bold()
                        .foregroundColor(.white)
                }
                .tint(.blue)
                .buttonStyle(.glassProminent)
                .disabled(viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .voiceOverLabel(L10n.tr("Gerar itens"))
                .voiceControlNames([L10n.tr("Gerar itens"), L10n.tr("Próximo"), L10n.tr("Continuar")])
            } else if viewModel.isSaving {
                ProgressView()
            } else if case .locked = viewModel.mode {
                // Nothing to add before Premium.
                EmptyView()
            } else {
                Button {
                    Task {
                        if await viewModel.save() {
                            HapticsManager.notify(.success)
                            dismiss()
                        } else {
                            HapticsManager.notify(.error)
                            if let errorText = viewModel.errorText { VoiceOver.announce(errorText) }
                        }
                    }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12))
                        .bold()
                        .foregroundColor(.white)
                }
                .tint(.blue)
                .buttonStyle(.glassProminent)
                .disabled(!viewModel.canConfirm || isBusy)
                .voiceOverLabel(L10n.tr("Adicionar itens (\(viewModel.includedCount))"))
                .voiceControlNames([L10n.tr("Adicionar"), L10n.tr("Confirmar"), L10n.tr("OK")])
            }
        }

        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("OK") { isTextFocused = false }
                .fontWeight(.semibold)
        }
    }

    // MARK: - Photos on the free plan

    /// Photos and PDFs shared on the free plan: what they'd become, and the way to Premium.
    private var lockedFiles: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                thumbnailStrip(height: 120)

                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text("Importar fotos e PDFs")
                        PremiumBadge()
                    }
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.titleGray)

                    Text("Com o Premium, o Pipa lê notas fiscais e receitas: os produtos da nota vão para a lista e as despesas, e os ingredientes da receita viram itens de compra.")
                        .font(.system(size: 15))
                        .foregroundStyle(.subTitleGray)
                        .multilineTextAlignment(.center)
                }
                .accessibilityElement(children: .combine)

                Button {
                    HapticsManager.selection()
                    paywall = .receiptScan
                } label: {
                    Text("Conhecer o Premium")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(.blue)
                .voiceControlNames([L10n.tr("Conhecer o Premium"), L10n.tr("Premium")])
            }
            .padding(22)
        }
    }

    /// The shared photos, side by side.
    private func thumbnailStrip(height: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(viewModel.thumbnails.enumerated()), id: \.offset) { _, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: height * 0.75, height: height)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .accessibilityLabel(Text("Fotos compartilhadas"))
    }

    // MARK: - Editing the text

    private var textEditor: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                Text("Corrija o texto e toque na seta para ler de novo. Um item por linha.")
                    .font(.system(size: 15))
                    .foregroundStyle(.subTitleGray)

                TextEditor(text: $viewModel.text)
                    .scrollContentBackground(.hidden)
                    .focused($isTextFocused)
                    .font(.system(size: 17))
                    .frame(minHeight: 220)
                    .padding(12)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .voiceOverLabel(L10n.tr("Texto compartilhado"))
            }
            .padding(22)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { isTextFocused = true }
    }

    // MARK: - Review

    private var review: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // Photos: only their pictures until a recipe's ingredients are read.
                if !viewModel.entry.hasFiles || viewModel.isRecipe {
                    sharedTextCard
                } else if !viewModel.thumbnails.isEmpty {
                    thumbnailStrip(height: 120)
                }

                // Free plan on a device that can run the model: what the AI would add.
                if !viewModel.usesAI && PremiumAIHint.isNeeded {
                    PremiumAIHint(paywall: $paywall)
                        .padding(.horizontal, 4)
                }

                if viewModel.isReading {
                    HStack(spacing: 8) {
                        ProgressView()
                        if viewModel.entry.hasFiles && !viewModel.isRecipe {
                            Text("Lendo a foto…")
                        } else {
                            Text(viewModel.usesAI ? LocalizedStringKey("Lendo o texto com IA…") : LocalizedStringKey("Lendo o texto…"))
                                .font(.system(size: 13))
                                .foregroundStyle(.subTitleGray)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else {
                    if let errorText = viewModel.errorText {
                        Text(errorText)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .padding(.horizontal, 4)
                    }

                    if !viewModel.shopCards.isEmpty {
                        sectionHeader("Compras", systemImage: "basket")
                        ForEach(viewModel.shopCards) { card in
                            shopRow(card)
                        }
                    }

                    if !viewModel.choreCards.isEmpty {
                        sectionHeader("Tarefas", systemImage: "checklist")
                        ForEach(viewModel.choreCards) { card in
                            choreRow(card)
                        }
                    }

                    // What's left before ✓ turns on.
                    if viewModel.hasIncompleteCards {
                        Label("Toque nos cards para preencher o que está em laranja.", systemImage: "exclamationmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }

                    if !viewModel.isEmpty {
                        Text("Toque e segure um card para movê-lo entre compras e tarefas.")
                            .font(.system(size: 13))
                            .foregroundStyle(.subTitleGray)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                }
            }
            .padding(22)
        }
    }

    /// The text as it was shared (or a recipe photo's ingredients), a few lines of it, with
    /// "Editar texto" to fix it.
    private var sharedTextCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !viewModel.thumbnails.isEmpty {
                thumbnailStrip(height: 64)
            }

            HStack(spacing: 6) {
                if viewModel.didReadWithAI {
                    Image(systemName: "sparkles")
                        .accessibilityHidden(true)
                }
                if viewModel.isRecipe {
                    Text("Ingredientes da receita")
                } else {
                    Text("Texto compartilhado")
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.subTitleGray)

            Text(viewModel.text)
                .font(.system(size: 15))
                .foregroundStyle(.titleGray)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                HapticsManager.selection()
                withAnimation(.snappy) { isEditingText = true }
            } label: {
                Label("Editar texto", systemImage: "pencil.line")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.titleGray)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func sectionHeader(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.titleGray)
            .padding(.top, 8)
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Shopping card

    /// Same card as "Adicionar com IA": checkbox, category tile, name, amount, category, people.
    private func shopRow(_ card: SharedImportViewModel.ShopCard) -> some View {
        let suggestion = card.suggestion
        let category = suggestion.category
        let consumers = suggestion.consumers ?? viewModel.shopList.houseUsers
        // No category yet: a neutral tile instead of "Outros".
        let tileColor = card.needsCategory ? Color.gray : category.color

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                checkbox(isOn: card.isIncluded, color: tileColor, name: suggestion.name) {
                    viewModel.toggle(card.id)
                }

                Button {
                    HapticsManager.selection()
                    editingShop = card
                } label: {
                    HStack(spacing: 12) {
                        SymbolImage(name: card.needsCategory ? "tag" : category.symbol)
                            .foregroundStyle(tileColor)
                            .frame(width: 32, height: 32)
                            .frame(width: 51, height: 56)
                            .background(
                                card.needsCategory ? Color.gray.opacity(0.12) : category.softColor.opacity(0.45),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 3) {
                            name(suggestion.name, isFromAI: card.isFromAI)
                            infoLine("dumbbell.fill", amountText(for: suggestion))
                            if card.needsCategory {
                                missingLine("tag.fill", L10n.tr("Escolher categoria"))
                            } else {
                                infoLine("tag.fill", category.displayName)
                            }
                            if card.needsPeople {
                                missingLine("person.2.fill", L10n.tr("Escolher responsável"))
                            } else {
                                infoLine("person.2.fill", peopleText(for: suggestion, consumers: consumers))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        chevron
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .voiceOverHint(L10n.tr("Toque duas vezes para editar."))
                .voiceControlNames([L10n.tr("Editar \(suggestion.name)")])
            }

            if let existing = card.duplicate {
                shopDuplicateBar(card, existing: existing)
            }
        }
        .modifier(CardStyle(isIncluded: card.isIncluded))
        .contextMenu {
            Button {
                Task { await viewModel.moveToChores(card.id) }
            } label: {
                Label("Mover para tarefas", systemImage: "checklist")
            }
        }
        .accessibilityAction(named: Text("Mover para tarefas")) {
            Task { await viewModel.moveToChores(card.id) }
        }
    }

    /// "Já está na lista": add to that item's quantity or keep a new one (same units only).
    private func shopDuplicateBar(_ card: SharedImportViewModel.ShopCard, existing: ShopListItem) -> some View {
        let suggestion = card.suggestion
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
                    Picker(selection: Binding(
                        get: { card.addsToDuplicate },
                        set: { viewModel.setAddsToDuplicate(card.id, $0) }
                    )) {
                        Text(L10n.tr("Adicionar como novo item")).tag(false)
                        Text(L10n.tr("Somar à quantidade (\(existing.quantity) → \(existing.quantity + suggestion.quantity))")).tag(true)
                    } label: {
                        EmptyView()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(card.addsToDuplicate ? L10n.tr("Somar") : L10n.tr("Novo item"))
                        Image(systemName: "chevron.up.chevron.down")
                            .imageScale(.small)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.titleGray)
                }
                .voiceOverLabel(L10n.tr("Item repetido"))
                .voiceOverValue(card.addsToDuplicate ? L10n.tr("Somar") : L10n.tr("Novo item"))
            }
        }
    }

    // MARK: - Chore card

    /// Checkbox, room tile, name, room and day. What's missing shows in orange; tapping the card
    /// opens the chore form to fill it, and ✓ there comes back here.
    private func choreRow(_ card: SharedImportViewModel.ChoreCard) -> some View {
        let roomColor = card.room?.color.uiColor ?? Color.gray

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                checkbox(isOn: card.isIncluded, color: roomColor, name: card.name) {
                    viewModel.toggleChore(card.id)
                }

                Button {
                    HapticsManager.selection()
                    editingChore = card
                } label: {
                    HStack(spacing: 12) {
                        SymbolImage(name: card.room?.symbol ?? "house")
                            .foregroundStyle(roomColor)
                            .frame(width: 32, height: 32)
                            .frame(width: 51, height: 56)
                            .background(
                                card.room.map { $0.color.lowOpacityColor.opacity(0.45) } ?? Color.gray.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 3) {
                            name(card.name, isFromAI: card.isFromAI && !card.usesExisting)
                            if let room = card.room {
                                infoLine("door.left.hand.open", room.name.localizedDefault)
                            } else {
                                missingLine("door.left.hand.open", L10n.tr("Escolher cômodo"))
                            }
                            if let day = dayText(for: card) {
                                infoLine(card.frequency == .none ? "calendar" : "repeat", day)
                            } else {
                                missingLine("calendar", L10n.tr("Escolher dia"))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        chevron
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .voiceOverHint(L10n.tr("Toque duas vezes para editar."))
                .voiceControlNames([L10n.tr("Editar \(card.name)")])
            }

            if let existing = card.duplicate {
                choreDuplicateBar(card, existing: existing)
            }
        }
        .modifier(CardStyle(isIncluded: card.isIncluded))
        .contextMenu {
            Button {
                Task { await viewModel.moveToShopping(card.id) }
            } label: {
                Label("Mover para compras", systemImage: "basket")
            }
        }
        .accessibilityAction(named: Text("Mover para compras")) {
            Task { await viewModel.moveToShopping(card.id) }
        }
    }

    /// "Já existe": keep a new chore, or change the existing one instead (its form opens from the
    /// card's arrow). Same menu as a repeated shopping item.
    private func choreDuplicateBar(_ card: SharedImportViewModel.ChoreCard, existing: ChoreModel) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.orange)
                .frame(width: 44)
                .accessibilityHidden(true)

            Text(L10n.tr("Já existe: \(existing.name)"))
                .font(.system(size: 13))
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                Picker(selection: Binding(
                    get: { card.usesExisting },
                    set: { usesExisting in
                        HapticsManager.selection()
                        Task { await viewModel.setUsesExisting(card.id, usesExisting) }
                    }
                )) {
                    Text(L10n.tr("Criar nova tarefa")).tag(false)
                    Text(L10n.tr("Editar a tarefa existente")).tag(true)
                } label: {
                    EmptyView()
                }
            } label: {
                HStack(spacing: 3) {
                    Text(card.usesExisting ? L10n.tr("Existente") : L10n.tr("Nova"))
                    Image(systemName: "chevron.up.chevron.down")
                        .imageScale(.small)
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.titleGray)
            }
            .voiceOverLabel(L10n.tr("Tarefa repetida"))
            .voiceOverValue(card.usesExisting ? L10n.tr("Existente") : L10n.tr("Nova"))
        }
    }

    // MARK: - Pieces

    private func checkbox(isOn: Bool, color: Color, name: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticsManager.selection()
            action()
        } label: {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 24))
                .foregroundStyle(isOn ? color : Color.gray.opacity(0.5))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .voiceOverLabel(L10n.tr("Incluir \(name)"))
        .voiceOverTraits(.isSelected, when: isOn)
        .voiceControlNames([L10n.tr("Incluir \(name)")])
    }

    /// The name, with ✨ when the AI wrote it.
    private func name(_ text: String, isFromAI: Bool) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.titleGray)
            if isFromAI {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(.subTitleGray)
                    .accessibilityLabel(L10n.tr("Preenchido pela IA"))
            }
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.subTitleGray)
            .accessibilityHidden(true)
    }

    /// A small grey line with its icon in front.
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

    /// A field still to fill, in orange ("Escolher categoria").
    private func missingLine(_ systemImage: String, _ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 11))
                .frame(width: 16)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.orange)
    }

    /// "2 quilogramas · R$ 25,00" (the price only when one was said).
    private func amountText(for suggestion: ShopItemSuggestion) -> String {
        var parts = ["\(suggestion.quantity) \(suggestion.unit.getDisplayName(for: Double(suggestion.quantity)))"]
        if let totalPrice = suggestion.totalPrice {
            let format = FloatingPointFormatStyle<Double>.Currency(code: "BRL").locale(L10n.locale)
            parts.append(totalPrice.formatted(format))
        }
        return parts.joined(separator: " · ")
    }

    /// "Ana, Bruno", or "Todos" for the whole house (said, or nobody named).
    private func peopleText(for suggestion: ShopItemSuggestion, consumers: [UserModel]) -> String {
        let house = Set(viewModel.shopList.houseUsers.map(\.id))
        let isEveryone = suggestion.consumers == nil
            || (!house.isEmpty && Set(consumers.map(\.id)) == house)
        return isEveryone ? L10n.tr("Todos") : consumers.map(\.name).joined(separator: ", ")
    }

    /// The day for a one-time chore ("Hoje", "Amanhã", "sáb., 22 de nov."), how often for a
    /// repeating one ("Semanal · desde sáb., 22 de nov.", "Todos os dias"); `nil` when the day
    /// is still missing.
    private func dayText(for card: SharedImportViewModel.ChoreCard) -> String? {
        if card.frequency == .daily { return L10n.tr("Todos os dias") }
        guard let date = card.date else {
            // An existing chore keeps its own schedule.
            return card.usesExisting ? card.frequency.displayName.capitalized(with: L10n.locale) : nil
        }
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(date) {
            day = L10n.tr("Hoje")
        } else if calendar.isDateInTomorrow(date) {
            day = L10n.tr("Amanhã")
        } else {
            day = date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(L10n.locale))
        }
        guard card.frequency != .none else { return day }
        let repeats = card.frequency.displayName.capitalized(with: L10n.locale)
        return L10n.tr("\(repeats) · desde \(day)")
    }
}

/// White rounded card, faded when left out (same as "Adicionar com IA").
private struct CardStyle: ViewModifier {
    let isIncluded: Bool

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 12)
            .padding(.leading, 6)
            .padding(.trailing, 14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .opacity(isIncluded ? 1 : 0.5)
    }
}
