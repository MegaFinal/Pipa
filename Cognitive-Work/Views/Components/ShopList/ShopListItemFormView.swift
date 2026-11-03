//
//  ShopListItemFormView.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 08/10/26.
//

import SwiftUI
import CloudKit

/// Which action ``ShopListItemFormView`` performs on confirm.
enum ShopListItemFormMode {
    /// Adds a new item.
    case create
    /// Edits (or deletes) this item.
    case edit(ShopListItem)
    /// edited values back through `onConfirm` and saves nothing.
    case draft(ShopItemSuggestion, onConfirm: (ShopItemSuggestion) -> Void)
}

/// The sheet used to add a shopping item or edit an existing one: name, category, quantity and
/// unit, an optional price and who it's for. When editing it can also delete the item.
struct ShopListItemFormView: View {

    /// Whether it creates a new item or edits one.
    var mode: ShopListItemFormMode
    /// The members that can be picked as who the item is for.
    var availableUsers: [UserModel]
    /// The signed-in member, saved as who added the item.
    var currentUser: UserModel?
    /// Saves and deletes the item.
    var viewModel: ShopListViewModel

    /// Closes the sheet.
    @Environment(\.dismiss) private var dismiss

    /// The item's name being typed.
    @State private var name: String = ""
    /// The chosen category.
    @State private var category: ShopItemCategory = .default
    /// How many.
    @State private var quantity: Int = 1
    /// The unit (unit, kg, liter, ...).
    @State private var unitMeasurement: UnitMeasurement = .unit
    /// The price per unit as typed (optional).
    @State private var valueText: String = ""
    /// Who the item is for (they split the cost).
    @State private var relatedUsers: [UserModel] = []
    /// `true` while saving or deleting (locks the form).
    @State private var isSaving = false
    /// Error shown when saving or deleting fails.
    @State private var saveErrorMessage: String?
    /// Shows the "delete item?" dialog.
    @State private var isConfirmingDelete = false
    /// A pending item that looks like the same product as the new one; asks whether to add to
    /// its quantity instead of creating a second card.
    @State private var duplicate: ShopListItem?
    /// Focuses the name field when adding a new item.
    @FocusState private var isNameFocused: Bool

    // MARK: Apple Intelligence state

    // The name field also takes a description ("2kg de arroz 10 reais para mim"), typed or
    // spoken with the mic beside it. When the person finishes, the AI fills the form and the
    // field keeps just the name; what they said shows above it, like Calendar's quick add.

    /// Fields the form can pre-fill from an AI suggestion.
    private enum SuggestedField {
        case category, quantity, unit, price, consumers
    }

    /// Whether the AI button shows in this form; set once when it appears (create mode only).
    @State private var canSuggest = false
    /// The Premium paywall, when a free house taps the AI button.
    @State private var paywall: PremiumFeature?
    /// The last suggestion applied; fields still holding its values show the sparkles icon.
    @State private var suggestion: ShopItemSuggestion?
    /// What the person typed or said, once the AI filled the form from it (not shown; it stops
    /// the "Nome: …" preview while the name is being edited afterwards).
    @State private var describedInput: String?
    /// The name the AI last read or wrote, so leaving the field doesn't ask again for it.
    @State private var lastReadName = ""
    /// What the AI would fill from the description being typed, shown as "Nome: …" under it.
    @State private var preview: ShopItemSuggestion?
    /// The pending preview request, restarted after each keystroke pause.
    @State private var previewTask: Task<Void, Never>?
    /// Whether the running AI request reads what was spoken; then a small spinner shows beside
    /// the spoken sentence (the mic itself never spins).
    @State private var isReadingSpeech = false
    /// The description the form was filled from, typed in the name or spoken, shown above the
    /// name with ✨ and editable. Done (or Return) on it asks the AI to fill the form again.
    @State private var spokenText = ""
    /// The sentence the AI last read, so it isn't read twice.
    @State private var lastReadSpoken = ""
    /// Focus of the spoken sentence's field.
    @FocusState private var isSpokenFocused: Bool
    /// Speech-to-text for the mic beside the name field (listens in the app's language).
    @State private var voice = VoiceInputManager()
    /// Whether a request is running; the button shows a spinner meanwhile.
    @State private var isSuggesting = false
    /// Whether the last request returned nothing; shows a hint to fill in by hand.
    @State private var aiDidFail = false
    /// The running request, cancelled if the sheet closes.
    @State private var suggestionTask: Task<Void, Never>?

    /// Editing a suggestion from the AI review: shows like editing, but nothing is saved here.
    private var isDraft: Bool {
        if case .draft = mode { return true }
        return false
    }

    /// Whether the sheet edits an existing item.
    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    /// The AI is listening to or reading a description, or the field still holds one longer
    /// than a name: saving waits until the form is filled.
    private var isReadingDescription: Bool {
        isSuggesting || voice.isBusy || trimmedName.count > TextLimits.shopItemName
    }

    /// The name without spaces at the ends.
    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Required fields still empty or invalid; the confirm button stays disabled until none is.
    private var missingFields: [ShopItemField] {
        ShopListViewModel.missingFields(
            name: name,
            quantity: quantity,
            unitMeasurement: unitMeasurement,
            category: category,
            relatedUsers: relatedUsers
        )
    }

    /// Whether a price above zero was typed.
    private var hasPrice: Bool {
        (Double(valueText.replacingOccurrences(of: ",", with: ".")) ?? 0) > 0
    }

    /// Points saving a new item will earn (the same figure ``ShopListViewModel`` awards).
    private var previewPoints: Int {
        ShopListViewModel.creationScore(
            beneficiaries: relatedUsers.count,
            hasPrice: hasPrice
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    // MARK: - Form sections
                    header

                    validationWarning

                    categoryCard

                    // Follows the category: its light color (the same light tone as the orange
                    // used before, for food).
                    RoundedRectangle(cornerRadius: 5)
                        .foregroundStyle(category.softColor)
                        .animation(.snappy, value: category)
                        .frame(height: 5)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)

                    // Same as above for quantity and unit.
                    section("Quantidade", isSuggested: isSuggested(.quantity) || isSuggested(.unit)) {
                        quantityCard
                    }

                    section("Valor (opcional)", isSuggested: isSuggested(.price)) {
                        priceField
                    }

                    section("Responsável", isSuggested: isSuggested(.consumers)) {
                        // White card on the grey page, like quantity and price.
                        VStack(alignment: .leading, spacing: 10) {
                            ResponsibleUserPicker(availableUsers: availableUsers, selectedUsers: $relatedUsers)
                            // How much each person pays, computed in code with the same equal
                            // split as the debts screen.
                            if let shareText {
                                Text(shareText)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.subTitleGray)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            Color.white,
                            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                        )
                    }

                    if isEditing {
                        deleteButton
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGray6).ignoresSafeArea())
            .navigationTitle(isEditing || isDraft ? "Editar item" : "Novo item")
            .navigationBarTitleDisplayMode(.inline)
            // MARK: - Toolbar: close and confirm
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

                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button {
                            Task { await save() }
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12))
                                .bold()
                                .foregroundColor(.white)
                        }
                        .tint(.blue)
                        .buttonStyle(.glassProminent)
                        .disabled(!missingFields.isEmpty || isReadingDescription)
                        .voiceOverLabel(isEditing || isDraft ? L10n.tr("Salvar") : L10n.tr("Adicionar item"))
                        .voiceControlNames(isEditing || isDraft
                            ? [L10n.tr("Confirmar"), L10n.tr("Salvar"), L10n.tr("OK")]
                            : [L10n.tr("Confirmar"), L10n.tr("Adicionar item"), L10n.tr("OK")])
                        .voiceOverHint(missingFields.first?.warning ?? "")
                    }
                }
            }
            .disabled(isSaving)
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGray6))
        .interactiveDismissDisabled(isSaving)
        // MARK: - Loading, VoiceOver warnings, delete dialog and error alert
        .task {
            populateFromMode()
            // No keyboard on open: the person taps the name (or the mic) when ready.
            // AI button only when creating, and only if the model can run here.
            canSuggest = !isEditing && !isDraft && viewModel.canSuggestItemDetails
        }
        // No request keeps running after the sheet closes.
        .onDisappear {
            suggestionTask?.cancel()
            previewTask?.cancel()
            voice.cancel()
        }
        // Spoken words show above the name as they're recognized (the name field is left
        // alone); when the person stops, the AI reads the sentence and fills the form.
        .onChange(of: voice.transcript) { _, spoken in
            if !spoken.isEmpty { spokenText = spoken }
        }
        .onChange(of: voice.isBusy) { wasBusy, isBusy in
            guard wasBusy, !isBusy else { return }
            readSpoken()
        }
        .premiumPaywall($paywall)
        .dismissKeyboardOnTap()
        .onChange(of: visibleWarning) { _, warning in
            if let warning { VoiceOver.announce(warning) }
        }
        // Same product already on the list: add to its quantity, or add a separate item anyway.
        .confirmationDialog(
            duplicateTitle,
            isPresented: Binding(
                get: { duplicate != nil },
                set: { if !$0 { duplicate = nil } }
            ),
            titleVisibility: .visible,
            presenting: duplicate
        ) { existing in
            if existing.unitMeasurement == unitMeasurement {
                Button(L10n.tr("Somar à quantidade (\(existing.quantity) → \(existing.quantity + quantity))")) {
                    Task { await addToExisting(existing) }
                }
            }
            Button(L10n.tr("Adicionar mesmo assim")) {
                Task { await save(checkingDuplicates: false) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: { existing in
            Text(duplicateMessage(for: existing))
        }
        .confirmationDialog("Excluir item?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Excluir item", role: .destructive) {
                Task { await deleteItem() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Essa ação não pode ser desfeita.")
        }
        .alert(
            "Não foi possível salvar",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "")
        }
    }

    // MARK: - Sections

    /// The category's icon beside the name field, like the chore editor's header. The field also
    /// takes a whole description ("2kg de arroz 10 reais para mim"): while typing, a grey pill
    /// previews the name the AI would keep (like Reminders' quick add); once applied, the field
    /// keeps just the name, which can still be edited.
    private var header: some View {
        HStack(spacing: 18) {
            SymbolImage(name: category.symbol)
                .frame(width: 64, height: 64)
                .foregroundStyle(category.color)
                .padding(.leading, 6)
                .accessibilityHidden(true)
            
            // Leading, so the hint under the field starts where the name starts.
            VStack(alignment: .leading) {
                HStack{
                    VStack(spacing: 2) {
                        // What was said, above the name; it can be corrected and read again.
                        if !spokenText.isEmpty || isSpokenFocused || voice.isBusy {
                            spokenLine
                        }

                        TextField(
                            "",
                            text: $name,
                            prompt: Text("Nome do item").foregroundStyle(.black)
                        )
                        .font(.system(size: 28))
                        .bold()
                        // A description is longer than a name; the AI shortens it to the name
                        // limit. Without AI, the usual limit applies while typing.
                        .characterLimit(canSuggest ? TextLimits.shopItemDescription : TextLimits.shopItemName, text: $name)
                        .submitLabel(.done)
                        .focused($isNameFocused)
                        .disabled(voice.isBusy)
                        // Done on the keyboard, or leaving the field, reads what was typed.
                        .onSubmit { readDescription() }
                        .onChange(of: isNameFocused) { _, isFocused in
                            if !isFocused { readDescription() }
                        }
                        .onChange(of: name) { _, newName in
                            // Clearing the name drops the old description above it.
                            if newName.isEmpty { describedInput = nil }
                            schedulePreview()
                        }
                        .voiceOverLabel(L10n.tr("Nome do item"))
                        .voiceControlNames([L10n.tr("Nome do item"), L10n.tr("Nome")])
                        
                        Capsule()
                            .frame(height: 1.5)
                            .foregroundStyle(.gray.opacity(0.5))
                            .accessibilityHidden(true)

                        // While typing a description: the name the AI would keep. Tap (or Done)
                        // to use it.
                        if let preview, describedInput == nil {
                            previewPill(preview)
                                .padding(.top, 6)
                        }
                        
                        if let voiceError = voice.errorMessage {
                            Text(voiceError)
                                .font(.system(size: 13))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Shown when the AI couldn't fill in the item; the form stays as it was.
                        if aiDidFail {
                            Text("Não foi possível preencher. Preencha manualmente.")
                                .font(.system(size: 13))
                                .foregroundStyle(.subTitleGray)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    
                    if canSuggest {
                        micButton
                    }
                }
                
                // Only when the AI can fill the form from a description.
                if canSuggest {
                    Label {
                        Text("Descreva o que gostaria de comprar e preenchemos automaticamente.")
                    } icon: {
                        Image(systemName: "sparkles")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(.subTitleGray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .animation(.snappy, value: category)
        .animation(.snappy, value: aiDidFail)
        .animation(.snappy, value: describedInput)
        .animation(.snappy, value: preview?.name)
        .animation(.snappy, value: spokenText.isEmpty)
    }

    /// "Nome: Arroz" under a description being typed; tapping it fills the form now.
    private func previewPill(_ preview: ShopItemSuggestion) -> some View {
        Button {
//<<<<<<< HEAD
//            guard PremiumManager.shared.allows(.shopAI) else {
//                paywall = .shopAI
//                return
//            }
//            aiInput = trimmedName
//            aiDidFail = false
//            isShowingAIPrompt = true
//=======
            lastReadName = trimmedName
            applySuggestion(preview)
        } label: {
            Text(L10n.tr("Nome: \(preview.name)"))
                .font(.system(size: 15))
                .foregroundStyle(.subTitleGray)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white, in: Capsule()) // White, so it shows on the grey page.
        }
        .buttonStyle(.plain)
        .transition(.opacity)
        .voiceOverHint(L10n.tr("Toque para preencher o formulário."))
    }

    /// The mic beside the name: tap to say the item, tap again to stop. What was said goes
    /// into the field, then the AI fills the form from it. Red while recording.
    private var micButton: some View {
        Button {
            HapticsManager.selection()
            if voice.isListening {
                voice.stop()
            } else if !voice.isBusy {
                // Closing the keyboard shouldn't send the half-typed name: speech is read instead.
                lastReadName = trimmedName
                isNameFocused = false
                isSpokenFocused = false
                spokenText = ""
                lastReadSpoken = ""
                aiDidFail = false
                Task { await voice.start(contextualStrings: availableUsers.map(\.name)) }
            }
//
        } label: {
            Group {
                // The mic never spins; progress shows beside the spoken sentence instead.
                Image(systemName: voice.isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(voice.isListening ? Color.white : .black)
                    .symbolEffect(.pulse, isActive: voice.isListening)
            }
            .frame(width: 44, height: 44)
            .background(Circle().fill(voice.isListening ? Color.red : Color.clear))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .disabled(isSuggesting || voice.isPreparing || voice.isFinishing)
        .voiceOverLabel(voice.isListening ? L10n.tr("Parar de ouvir") : L10n.tr("Falar"))
        .voiceControlNames(voice.isListening
            ? [L10n.tr("Parar"), L10n.tr("Parar de ouvir")]
            : [L10n.tr("Falar"), L10n.tr("Microfone")])
    }

    /// The spoken sentence above the name, small and grey but editable. Return or Done reads it
    /// again; a small spinner shows while the speech is being transcribed or read by the AI.
    private var spokenLine: some View {
        HStack(alignment: .center, spacing: 6) {
            Group {
                if voice.isPreparing || voice.isFinishing || (isSuggesting && isReadingSpeech) {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    // ✨ for any description, typed or spoken.
                    Image(systemName: "sparkles")
                        .font(.system(size: 13))
                        .foregroundStyle(.subTitleGray)
                        .symbolEffect(.variableColor.iterative, isActive: voice.isListening)
                }
            }
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)

            TextField(L10n.tr("Ouvindo"), text: $spokenText, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(.subTitleGray)
                .lineLimit(1...3)
                .submitLabel(.done)
                .focused($isSpokenFocused)
                .disabled(voice.isBusy)
                // A vertical field puts Return in the text: treat it as Done instead.
                .onChange(of: spokenText) { _, newText in
                    guard newText.contains("\n") else { return }
                    spokenText = newText.replacingOccurrences(of: "\n", with: "")
                    isSpokenFocused = false
                }
                .onChange(of: isSpokenFocused) { _, isFocused in
                    if !isFocused { readSpoken() }
                }
                .voiceOverLabel(L10n.tr("O que você descreveu"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }

    /// Asks the AI to fill the form from the spoken sentence (as spoken or as corrected), once
    /// per text.
    private func readSpoken() {
        let input = spokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSuggest, !voice.isBusy, !input.isEmpty, input != lastReadSpoken else { return }
        lastReadSpoken = input
        aiDidFail = false
        requestSuggestion(for: input)
        isReadingSpeech = true
    }

    /// The warning on screen, if any; VoiceOver announces it whenever it appears or changes.
    private var visibleWarning: String? {
        trimmedName.isEmpty ? nil : missingFields.first?.warning
    }

    /// Explains why the confirm button is disabled, near the top so it shows without scrolling.
    /// Like the chore form, it names one thing at a time and waits for the name first.
    @ViewBuilder
    private var validationWarning: some View {
        if let warning = visibleWarning {
            Text(warning)
                .font(.system(size: 13))
                .foregroundColor(.red)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// A titled block of the form.
    ///
    /// Changed: `isSuggested` shows a sparkles icon next to the title while the block holds
    /// values pre-filled by the on-device model.
    private func section<Content: View>(
        _ title: LocalizedStringKey,
        isSuggested: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 15))
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)

                if isSuggested {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.subTitleGray)
                        .transition(.opacity)
                        .voiceOverLabel(L10n.tr("Sugerido automaticamente"))
                }
            }
            .animation(.snappy, value: isSuggested)

            content()
        }
    }

    /// Stepper and unit menu on one soft card.
    private var quantityCard: some View {
        VStack(spacing: 16) {
            QuantityStepper(
                value: $quantity,
                valueDescription: { ShopListViewModel.accessibilityQuantity($0, unit: unitMeasurement) }
            )
            .frame(maxWidth: .infinity)

            Divider()

            HStack {
                (Text("Unidade"))
                    .font(.system(size: 15))
                    .fontWeight(.semibold)

                Spacer()

                Menu {
                    Picker("Unidade", selection: $unitMeasurement) {
                        ForEach(UnitMeasurement.allCases.filter { $0 != .undefined }) { unit in
                            Text(unit.getDisplayName(for: Double(quantity))).tag(unit)
                        }
                    }
                } label: {
                    HStack {
                        // A dot in the category's color, then the choice (no capsule around it).
                        menuValue(unitMeasurement.getDisplayName(for: Double(quantity)).capitalized(with: L10n.locale))

                        Image(systemName: "chevron.up.chevron.down")
                            .foregroundColor(.black)
                            .imageScale(.small)
                    }
                    .fixedSize()
                }
                .voiceOverLabel(L10n.tr("Unidade"))
                .voiceOverValue(unitMeasurement.getDisplayName(for: Double(quantity)))
                .voiceControlNames([
                    L10n.tr("Unidade"),
                    unitMeasurement.getDisplayName(for: Double(quantity)).capitalized(with: L10n.locale)
                ])
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            Color.white,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }

    /// Category as a menu row in a white card, the same pattern as "Unidade" in ``quantityCard``.
    /// Sparkles beside the label mark a category the AI filled in.
    private var categoryCard: some View {
        HStack {
            HStack(spacing: 6) {
                Text("Categoria")
                    .font(.system(size: 15))
                    .fontWeight(.semibold)

                if isSuggested(.category) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.subTitleGray)
                        .transition(.opacity)
                        .voiceOverLabel(L10n.tr("Sugerido automaticamente"))
                }
            }
            .animation(.snappy, value: isSuggested(.category))

            Spacer()

            Menu {
                Picker("Categoria", selection: $category) {
                    ForEach(ShopItemCategory.allCases) { option in
                        // Black icons: menus drew the template assets white.
                        Label {
                            Text(option.displayName)
                        } icon: {
                            Image(uiImage: Self.menuIcon(option.symbol))
                        }
                        .tag(option)
                    }
                }
            } label: {
                HStack {
                    // A dot in the category's color, then the choice (no capsule around it).
                    menuValue(category.displayName)

                    Image(systemName: "chevron.up.chevron.down")
                        .foregroundColor(.black)
                        .imageScale(.small)
                }
                .fixedSize()
            }
            .voiceOverLabel(L10n.tr("Categoria"))
            .voiceOverValue(category.displayName)
            .voiceControlNames([L10n.tr("Categoria"), category.displayName])
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            Color.white,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }

    /// A category icon for the menu, drawn black. Category icons are image assets now (see
    /// ``SymbolImage``), and "house" is still an SF Symbol, so it takes whichever exists. Menus
    /// ignore SwiftUI colors, so the color is baked into the image.
    private static func menuIcon(_ name: String) -> UIImage {
        let image = UIImage(named: name) ?? UIImage(systemName: name) ?? UIImage()
        return image.withTintColor(.black, renderingMode: .alwaysOriginal)
    }

    /// What a menu row shows as its value: a small dot in the category's color, then the text.
    private func menuValue(_ text: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(category.color)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)

            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(.black)
        }
        .animation(.snappy, value: category)
    }

    /// The price field.
    private var priceField: some View {
            TextField(pricePlaceholder, text: $valueText)
                .priceInput(text: $valueText)
                .font(.system(size: 17))
                .voiceOverLabel(L10n.tr("Preço por unidade"))
                .voiceOverValue(ShopListViewModel.accessibilityPrice(valueText))
                // Voice Control: "Toque em Preço", then dictate the value.
                .voiceControlNames([L10n.tr("Preço por unidade"), L10n.tr("Preço"), L10n.tr("Valor")])

        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            Color.white,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }

    /// The "Excluir item" button (edit mode only).
    private var deleteButton: some View {
        Button(role: .destructive) {
            isConfirmingDelete = true
        } label: {
            Label("Excluir item", systemImage: "trash")
                .fontWeight(.semibold)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .voiceControlNames([L10n.tr("Excluir item"), L10n.tr("Excluir")])
        .disabled(isSaving)
    }

    // MARK: - Apple Intelligence
    // Added: everything in this section pre-fills the form from the on-device model. Nothing is
    // saved until the person taps confirm, and any failure simply leaves the form as it is.

    /// Whether `field` still shows the value the AI filled in. Once the person changes it, the
    /// value differs and the sparkles icon goes away.
    private func isSuggested(_ field: SuggestedField) -> Bool {
        guard let suggestion else { return false }
        switch field {
        case .category: return category == suggestion.category
        case .quantity: return quantity == suggestion.quantity
        case .unit: return unitMeasurement == suggestion.unit
        case .price:
            guard let unitPrice = suggestion.unitPrice else { return false }
            return valueText == ShopListViewModel.priceInputText(for: unitPrice)
        case .consumers:
            guard let consumers = suggestion.consumers else { return false }
            return Set(relatedUsers.map(\.id)) == Set(consumers.map(\.id))
        }
    }

    /// "R$ 12,50 por pessoa": the item's total split equally between the people it's for, rounded
    /// to cents like ``DebtCalculator``. `nil` without a price or without anyone selected.
    private var shareText: String? {
        ShopListViewModel.shareText(
            unitPrice: ShopListViewModel.parsePrice(valueText),
            quantity: quantity,
            consumerCount: relatedUsers.count
        )
    }

    /// Sends what the person typed in the AI prompt to the on-device model.
    /// Asks the AI to fill the form from what is in the name field, once per text: nothing
    /// happens if it's empty or it's the name the AI already read or wrote.
    ///
    /// - Returns: Whether a request started.
    @discardableResult
    private func readDescription() -> Bool {
        let input = trimmedName
        guard canSuggest, !voice.isBusy, !input.isEmpty, input != lastReadName else { return false }
        lastReadName = input
        aiDidFail = false

        // The preview already read this exact text: use it instead of asking again.
        if let preview, preview.input == input {
            applySuggestion(preview)
            return false
        }
        isReadingSpeech = false // Typed by default; the speech path sets it back right after.
        requestSuggestion(for: input)
        return true
    }

    /// After a short pause in typing, asks the AI what it would fill, to show "Nome: …".
    /// Only for descriptions (two words or more) typed before the form was filled from one.
    private func schedulePreview() {
        previewTask?.cancel()
        preview = nil
        let input = trimmedName
        guard canSuggest, isNameFocused, describedInput == nil, !voice.isBusy,
              input != lastReadName,
              input.split(separator: " ").count >= 2
        else { return }

        previewTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(800))
            } catch {
                return // Still typing.
            }
            let result = await viewModel.suggestItemDetails(
                for: input,
                housemates: availableUsers,
                currentUser: currentUser,
                selectedConsumers: relatedUsers
            )
            guard !Task.isCancelled, let result, input == trimmedName else { return }
            // Worth showing only when the AI took something out of the text.
            if result.name.localizedCaseInsensitiveCompare(input) != .orderedSame {
                preview = result
            }
        }
    }

    private func requestSuggestion(for input: String) {
        suggestionTask?.cancel()
        previewTask?.cancel()
        isSuggesting = true
        suggestionTask = Task {
            defer {
                // A request replaced by a newer one leaves the newer one's state alone.
                if !Task.isCancelled {
                    isSuggesting = false
                    isReadingSpeech = false
                }
            }

            let result = await viewModel.suggestItemDetails(
                for: input,
                housemates: availableUsers,
                currentUser: currentUser,
                selectedConsumers: relatedUsers
            )
            guard !Task.isCancelled else { return }

            if let result {
                applySuggestion(result)
            } else {
                aiDidFail = true
                // Typed: keep what they wrote, cut to the name limit so the item can still be
                // saved. Spoken: the sentence stays above and the name is left as it was.
                if !isReadingSpeech {
                    name = String(input.prefix(TextLimits.shopItemName))
                    lastReadName = name
                }
                VoiceOver.announce(L10n.tr("Não foi possível preencher. Preencha manualmente."))
            }
        }
    }

    /// Fills name, category, quantity and unit, plus price and people when the person mentioned
    /// them. The person asked for it with the button, so those fields are replaced; they can still
    /// change any of them before saving.
    private func applySuggestion(_ result: ShopItemSuggestion) {
        suggestion = result
        previewTask?.cancel()
        preview = nil
        withAnimation(.snappy) {
            // Kept only when the AI changed the name (see `describedInput`).
            describedInput = result.name.isEmpty || result.name == result.input ? nil : result.input
            if !result.name.isEmpty { name = result.name }
            lastReadName = name
            // The sentence (typed or spoken) moves above the name, where it can be edited and
            // read again; only when the AI changed it, so "Arroz" alone isn't repeated there.
            if !result.name.isEmpty, result.name != result.input {
                spokenText = result.input
                lastReadSpoken = result.input
            }
            category = result.category
            quantity = result.quantity
            unitMeasurement = result.unit
            if let unitPrice = result.unitPrice {
                valueText = ShopListViewModel.priceInputText(for: unitPrice)
            }
            if let consumers = result.consumers {
                relatedUsers = consumers
            }
        }
        HapticsManager.notify(.success)
    }

    // MARK: - Actions

    /// Currency placeholder in the app's language/region format (e.g. "R$ 0,00").
    private var pricePlaceholder: String {
        L10n.tr("Preço por unidade (R$ 0,00)")
    }

    /// Seeds the form's local state from the item being edited.
    private func populateFromMode() {
        // A draft from the AI review fills the form with the suggestion's values. People not
        // mentioned show as the whole house, the same default the review uses when saving.
        if case .draft(let suggestion, _) = mode {
            name = suggestion.name
            category = suggestion.category
            quantity = suggestion.quantity
            unitMeasurement = suggestion.unit
            relatedUsers = suggestion.consumers ?? availableUsers
            if let unitPrice = suggestion.unitPrice {
                valueText = ShopListViewModel.priceInputText(for: unitPrice)
            }
            return
        }

        guard case .edit(let item) = mode else { return }
        name = item.name
        category = item.category
        quantity = item.quantity
        unitMeasurement = item.unitMeasurement == .undefined ? .unit : item.unitMeasurement
        relatedUsers = item.relatedUsers(in: availableUsers)
        if let value = item.value {
            valueText = ShopListViewModel.priceInputText(for: value)
        }
    }

    /// Saves the item; closes the sheet on success or shows the error.
    ///
    /// - Parameter checkingDuplicates: When creating, first look for the same product already on
    ///   the list (``ShopListViewModel/duplicateItem(named:)``). `false` after the person chose
    ///   "add anyway".
    private func save(checkingDuplicates: Bool = true) async {
        // A draft goes back to the AI review with the edited values; nothing reaches CloudKit yet.
        if case .draft(let original, let onConfirm) = mode {
            let price = ShopListViewModel.parsePrice(valueText) ?? 0
            onConfirm(ShopItemSuggestion(
                input: original.input,
                name: trimmedName,
                quantity: quantity,
                unit: unitMeasurement,
                category: category,
                unitPrice: price > 0 ? price : nil,
                consumers: relatedUsers
            ))
            HapticsManager.notify(.success)
            dismiss()
            return
        }

        isSaving = true
        defer { isSaving = false }

        // New item: check first whether the same product is already waiting to be bought.
        if checkingDuplicates, case .create = mode,
           let existing = await viewModel.duplicateItem(named: trimmedName) {
            duplicate = existing
            return
        }

        let existingItem: ShopListItem? = {
            if case .edit(let item) = mode { return item }
            return nil
        }()

        let success = await viewModel.saveItem(
            existingItem,
            name: trimmedName,
            valueText: valueText,
            quantity: quantity,
            unitMeasurement: unitMeasurement,
            category: category,
            relatedUsers: relatedUsers,
            addedBy: currentUser
        )

        if success {
            HapticsManager.notify(.success)
            dismiss()
        } else {
            saveErrorMessage = viewModel.errorMessage ?? L10n.tr("Tente novamente.")
        }
    }

    /// Adds this form's quantity to the item already on the list instead of creating a new one.
    private func addToExisting(_ existing: ShopListItem) async {
        isSaving = true
        defer { isSaving = false }

        // The people chosen here join the existing item's split if they aren't in it yet.
        if await viewModel.merge(into: existing, adding: quantity, consumers: relatedUsers) {
            HapticsManager.notify(.success)
            VoiceOver.announce(L10n.tr("Quantidade atualizada"))
            dismiss()
        } else {
            saveErrorMessage = viewModel.errorMessage ?? L10n.tr("Tente novamente.")
        }
    }

    /// Explains the choice, and who will join the split when quantities are added.
    private func duplicateMessage(for existing: ShopListItem) -> String {
        guard existing.unitMeasurement == unitMeasurement else {
            return L10n.tr("O item que já está na lista usa outra unidade.")
        }
        let joining = viewModel.newConsumers(relatedUsers, for: existing)
        guard !joining.isEmpty else {
            return L10n.tr("Você pode somar a quantidade ao item que já está na lista.")
        }
        return L10n.tr("Você pode somar a quantidade ao item que já está na lista.")
            + "\n"
            + L10n.tr("Também entram na divisão: \(joining.map(\.name).joined(separator: ", "))")
    }

    /// "“leite” is already on the list".
    private var duplicateTitle: String {
        guard let duplicate else { return "" }
        return L10n.tr("Já tem “\(duplicate.name)” na lista")
    }

    /// Deletes the item; closes the sheet on success or shows the error.
    private func deleteItem() async {
        guard case .edit(let item) = mode else { return }
        isSaving = true
        defer { isSaving = false }

        if await viewModel.deleteItem(item) {
            HapticsManager.notify(.warning)
            dismiss()
        } else {
            saveErrorMessage = viewModel.errorMessage ?? L10n.tr("Tente novamente.")
        }
    }
}

// MARK: - Previews

#Preview("Novo item") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            ShopListItemFormView(
                mode: .create,
                availableUsers: ShopListPreviewData.users,
                currentUser: ShopListPreviewData.jones,
                viewModel: ShopListPreviewData.populatedViewModel
            )
        }
}
