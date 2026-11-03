//
//  CreateAndEditChoreView.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 28/08/26.
//

import SwiftUI
import CloudKit

/// The sheet to create a new chore or edit an existing one, in two steps
struct CreateAndEditChoreView: View {

    init(originalModel: ChoreModel,
         availableHouseUsers: [UserModel],
         carouselViewModel: CarouselViewModel,
         targetAssignments: [RecurrentAssignmentModel] = []) {
        self._viewModel = State(initialValue: CreateAndEditChoreViewModel(
            originalModel: originalModel,
            availableHouseUsers: availableHouseUsers,
            carouselViewModel: carouselViewModel,
            targetAssignments: targetAssignments
        ))
    }
    
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: CreateAndEditChoreViewModel
    @State private var showsScheduleStep = false
    @State private var showDeleteConfirmation = false
    @State private var isSubmitting = false
    @State private var showsCalendar = false
    /// Looking for an existing chore the new one repeats (before the second step).
    @State private var isCheckingDuplicate = false
    /// The existing chore the new one seems to repeat; shows the warning.
    @State private var duplicateChore: ChoreModel?
    /// The name the person chose to create anyway, so the warning isn't shown again for it.
    @State private var acceptedDuplicateName: String?
    /// The existing chore opened from the warning, to change it instead of creating a new one.
    @State private var existingToEdit: ChoreModel?

    // MARK: Apple Intelligence state
    // The name field also takes a description ("lavar a louça toda semana, eu e Ana"), typed or
    // spoken with the mic beside it, like the shopping item form. The AI fills room, frequency,
    // duration, priority and people; the person checks everything before saving.

    /// Whether the name field takes descriptions; set when the form appears (new chores only).
    @State private var canSuggest = false
    /// Speech-to-text for the mic beside the name (listens in the app's language).
    @State private var voice = VoiceInputManager()
    /// The description the form was filled from, typed in the name or spoken, shown above the
    /// name with ✨ and editable; Done reads it again.
    @State private var spokenText = ""
    @State private var lastReadSpoken = ""
    @FocusState private var isSpokenFocused: Bool
    @FocusState private var isNameFocused: Bool
    /// The name the AI last read or wrote, so leaving the field doesn't ask again.
    @State private var lastReadName = ""
    /// After the form was filled from a description, typing in the name only edits the name.
    @State private var didFillFromDescription = false
    /// What the AI would fill from the description being typed, shown as "Nome: …".
    @State private var preview: ChoreSuggestion?
    @State private var previewTask: Task<Void, Never>?
    @State private var isSuggesting = false
    /// Whether the running request reads speech; then a spinner shows beside the sentence.
    @State private var isReadingSpeech = false
    @State private var aiDidFail = false
    @State private var suggestionTask: Task<Void, Never>?
    /// Typical checklist steps for the chore's name, offered inside the checklist card.
    @State private var checklistIdeas: [String] = []
    /// The name (and room) the ideas were asked for, so they aren't asked again.
    @State private var checklistIdeasKey = ""
    @State private var checklistIdeasTask: Task<Void, Never>?

    /// Listening, reading, or the name still holds a whole description: "Próximo" waits.
    private var isReadingDescription: Bool {
        isSuggesting || voice.isBusy
            || viewModel.draft.name.trimmingCharacters(in: .whitespacesAndNewlines).count > TextLimits.choreName
    }
    
    /// Whether the form must ignore edits: still loading, saving or deleting.
    private var isFormLocked: Bool {
        !viewModel.isLoaded || isBusy
    }
    
    /// Saving or deleting.
    private var isBusy: Bool {
        isSubmitting || viewModel.isSaving || viewModel.isDeleting
    }
    
    private var roomColor: Color {
        (viewModel.draft.room?.color ?? .blue).uiColor
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            detailsStep
                .navigationDestination(isPresented: $showsScheduleStep) {
                    scheduleStep
                }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.groupedBackground)
        .interactiveDismissDisabled(isBusy)
        // MARK: - Loading and reacting to visibility and frequency changes
        .task {
            await viewModel.load()
            canSuggest = viewModel.canSuggest
        }
        // New checklist ideas when the chore's name or room settles.
        .onChange(of: checklistIdeasTrigger) { _, _ in
            scheduleChecklistIdeas()
        }
        // Spoken words show above the name as they're recognized; when the person stops, the
        // AI reads the sentence.
        .onChange(of: voice.transcript) { _, spoken in
            if !spoken.isEmpty { spokenText = spoken }
        }
        .onChange(of: voice.isBusy) { wasBusy, isBusy in
            guard wasBusy, !isBusy else { return }
            readSpoken()
        }
        .onDisappear {
            suggestionTask?.cancel()
            previewTask?.cancel()
            checklistIdeasTask?.cancel()
            voice.cancel()
        }
        .onChange(of: viewModel.draft.isPublic) { _, isPublic in
            viewModel.visibilityDidChange(isPublic: isPublic)
        }
        .onChange(of: viewModel.draft.frequency) { _, _ in
            viewModel.frequencyDidChange()
        }
        // MARK: - Delete alert, error alert and deleting overlay
        .alert("Excluir Tarefa?", isPresented: $showDeleteConfirmation) {
            Button("Cancelar", role: .cancel) {}
            Button("Excluir", role: .destructive) {
                Task {
                    if await viewModel.delete() {
                        dismiss()
                    }
                }
            }
        } message: {
            Text("Se esta tarefa for recorrente, apenas esta ocorrência será excluída — as demais continuam como estão. Essa ação é permanente.")
        }
        .alert(
            viewModel.alert?.title ?? "",
            isPresented: Binding(
                get: { viewModel.alert != nil },
                set: { if !$0 { viewModel.alert = nil } }
            ),
            presenting: viewModel.alert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
        .blockingOperation(
            isPresented: Binding(get: { viewModel.isDeleting }, set: { _ in }),
            message: "Excluindo tarefa..."
        )
    }
    
    // MARK: - Step 1: details
    
    /// Photo, name, room, description and checklist.
    private var detailsStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                roomSymbol
                
                // MARK: Name
                VStack(alignment: .leading, spacing: 14) {
                    Text("Nome da tarefa")
                        .font(.title2.bold())
                        .accessibilityHidden(true)
                    
                    // What was said, above the name; it can be corrected and read again.
                    if canSuggest && (!spokenText.isEmpty || isSpokenFocused || voice.isBusy) {
                        // Flush with the title, like the hint below.
                        spokenLine
                    }

                    HStack(spacing: 10) {
                        TextField("", text: $viewModel.draft.name, prompt: Text("Adicione o nome da tarefa"))
                            .characterLimit(
                                canSuggest ? TextLimits.choreNameDescription : TextLimits.choreName,
                                text: $viewModel.draft.name
                            )
                            .submitLabel(.done)
                            .focused($isNameFocused)
                            .onSubmit { readTypedName() }
                            .onChange(of: isNameFocused) { _, isFocused in
                                if !isFocused { readTypedName() }
                            }
                            .onChange(of: viewModel.draft.name) { _, newName in
                                if newName.isEmpty { didFillFromDescription = false }
                                schedulePreview()
                            }
                            .voiceOverLabel(L10n.tr("Nome da tarefa"))
                            .voiceControlNames([L10n.tr("Nome da tarefa"), L10n.tr("Nome")])
                            .formField(in: Capsule())

                        if canSuggest {
                            micButton
                        }
                    }

                    // While typing a description: the name the AI would keep. Tap (or Done) to use it.
                    if let preview, !didFillFromDescription {
                        previewPill(preview)
                    }

                    if let voiceError = voice.errorMessage {
                        Text(voiceError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if aiDidFail {
                        Text("Não foi possível preencher. Preencha manualmente.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    // Only when the name field takes descriptions.
                    if canSuggest {
                        Label {
                            Text("Descreva a tarefa, quando se repete e quem faz, e preenchemos o resto.")
                        } icon: {
                            Image(systemName: "sparkles")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        // Starts where the title starts; wrapped lines stay left-aligned.
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .animation(.snappy, value: preview?.name)
                .animation(.snappy, value: aiDidFail)
                .animation(.snappy, value: spokenText.isEmpty)
                
                // MARK: Room and the line in its color
                VStack(alignment: .leading, spacing: 6) {
                    roomRow
                        .formField(in: Capsule())
                    
                    if viewModel.showsMissingRoomWarning {
                        warning("Escolha um cômodo para confirmar a tarefa.")
                            .padding(.horizontal, 20)
                    }
                }
                
                Capsule()
                    .fill(roomColor)
                    .frame(height: 4)
                    .accessibilityHidden(true)
                
                // MARK: Description
                VStack(alignment: .leading, spacing: 10) {
                    // ✨ while it holds what the AI took from the description.
                    suggestedTitle("Detalhes", isSuggested: viewModel.isDescriptionSuggested)
                    
                    TextField("Descrição da tarefa", text: $viewModel.draft.description, axis: .vertical)
                        .characterLimit(TextLimits.choreDescription, text: $viewModel.draft.description)
                        .voiceControlNames([L10n.tr("Descrição da tarefa"), L10n.tr("Detalhes")])
                        .formField(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                
                // MARK: Checklist
                VStack(alignment: .leading, spacing: 10) {
                    // ✨ while it has steps the AI added.
                    suggestedTitle("Checklist", isSuggested: viewModel.hasSuggestedChecklistItems)
                    
                    // The suggested steps sit inside the checklist card, under its rows, each in
                    // a dashed purple box with "Adicionar"; never added on their own.
                    VStack(alignment: .leading, spacing: 8) {
                        CheckListCreateAndEdit(localChecklist: $viewModel.draft.checklist)

                        ForEach(visibleChecklistIdeas, id: \.self) { idea in
                            checklistIdeaRow(idea)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, visibleChecklistIdeas.isEmpty ? 0 : 16)
                    .background(.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                }
                .animation(.snappy, value: visibleChecklistIdeas)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
            .disabled(isFormLocked)
            .opacity(isFormLocked ? 0.5 : 1)
        }
        .background(Color.groupedBackground)
        .dismissKeyboardOnTap()
        // MARK: - Loading spinner
        .overlay {
            if !viewModel.isLoaded {
                ProgressView()
                    .controlSize(.large)
                    .voiceOverLabel(L10n.tr("Carregando"))
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .close) { dismiss() }
                    .disabled(isBusy)
            }
            
            ToolbarItem(placement: .confirmationAction) {
                // A spinner while looking for a chore that already exists.
                if isCheckingDuplicate {
                    ProgressView()
                } else {
                    Button {
                        Task { await goToScheduleStep() }
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.blue)
                    .disabled(!viewModel.isLoaded || !viewModel.hasValidName || !viewModel.hasRoom || isReadingDescription)
                    .voiceOverLabel(L10n.tr("Próximo"))
                    .voiceControlNames([L10n.tr("Próximo"), L10n.tr("Continuar")])
                }
            }
        }
        // The new chore seems to repeat one the house already has: say which, and let the person
        // go on anyway or go back and change it.
        .confirmationDialog(
            duplicateTitle,
            isPresented: Binding(
                get: { duplicateChore != nil },
                set: { if !$0 { duplicateChore = nil } }
            ),
            titleVisibility: .visible,
            presenting: duplicateChore
        ) { existing in
            // Change the chore the house already has; this new one is dropped.
            Button(L10n.tr("Editar a tarefa existente")) {
                existingToEdit = existing
            }
            Button(L10n.tr("Criar mesmo assim")) {
                acceptedDuplicateName = viewModel.draft.name
                showsScheduleStep = true
            }
            Button("Cancelar", role: .cancel) {}
        } message: { existing in
            Text(duplicateMessage(for: existing))
        }
        // The existing chore's editor, on top of this form. When it closes, this new-chore form
        // closes too: the person chose to change that chore instead.
        .sheet(item: $existingToEdit, onDismiss: { dismiss() }) { existing in
            CreateAndEditChoreView(
                originalModel: existing,
                availableHouseUsers: viewModel.carouselForEditing.userModels,
                carouselViewModel: viewModel.carouselForEditing
            )
        }
    }

    // MARK: - Repeated chore

    /// Before the second step, a new chore is checked against the house's chores (only once per
    /// name, so "Criar mesmo assim" isn't asked again).
    private func goToScheduleStep() async {
        let name = viewModel.draft.name
        guard viewModel.mode == .create, name != acceptedDuplicateName else {
            showsScheduleStep = true
            return
        }
        isCheckingDuplicate = true
        let existing = await viewModel.existingDuplicate()
        isCheckingDuplicate = false

        if let existing {
            HapticsManager.notify(.warning)
            duplicateChore = existing
        } else {
            showsScheduleStep = true
        }
    }

    /// "Já existe “Lavar a louça”".
    private var duplicateTitle: String {
        guard let duplicateChore else { return "" }
        return L10n.tr("Já existe “\(duplicateChore.name)”")
    }

    /// Where the existing chore is and how often it repeats.
    private func duplicateMessage(for existing: ChoreModel) -> String {
        let summary = viewModel.summary(of: existing)
        let base = L10n.tr("Parece que a casa já tem essa tarefa.")
        return summary.isEmpty ? base : base + "\n" + summary
    }
    
    /// "Cômodo" with a menu of the house's rooms.
    private var roomRow: some View {
        let roomName = viewModel.draft.room?.name.localizedDefault.capitalized(with: L10n.locale)
            ?? L10n.tr("Sem Cômodo")
        
        return ChoreAttributeMenuRow(
            title: "Cômodo",
            value: roomName,
            color: roomColor,
            isSuggested: viewModel.isSuggested(.room)
        ) {
            Picker("Cômodo", selection: handPicked(\.room, .room)) {
                ForEach(viewModel.availableRooms, id: \.self) { room in
                    ChoreMenuOption(
                        title: room.name.localizedDefault.capitalized(with: L10n.locale),
                        color: room.color.uiColor
                    )
                    .tag(RoomModel?(room))
                }
            }
        }
    }
    
    // MARK: - Step 2: schedule
    
    /// Priority, duration, frequency and date; who is responsible; sharing with the house.
    private var scheduleStep: some View {
        List {
            // MARK: Room symbol
            Section {
                roomSymbol
            }
            .listRowBackground(Color.clear)
            // No extra padding around the symbol.
            .listRowInsets(EdgeInsets())
            
            // MARK: Attributes and date
            Section {
                attributeRows
                
                if viewModel.showsDateSection {
                    dateRow
                }
            } footer: {
                if viewModel.showsMissingDateWarning {
                    warning("Escolha uma data para confirmar a tarefa.")
                }
            }
            
            // MARK: Responsible members
            Section {
                ResponsibleUserPicker(
                    availableUsers: viewModel.selectableResponsibleUsers,
                    selectedUsers: handPicked(\.responsibleUsers, .responsible)
                )
                .padding(.vertical, 6)
            } header: {
                HStack(spacing: 6) {
                    sectionTitle("Responsáveis")
                    if viewModel.isSuggested(.responsible) {
                        Image(systemName: "sparkles")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .voiceOverLabel(L10n.tr("Sugerido automaticamente"))
                    }
                }
            }
            
            // MARK: Sharing with the house
            Section {
                Toggle(isOn: $viewModel.draft.isPublic) {
                    Text("Dividir com a casa?")
                        .fontWeight(.semibold)
                }
                .tint(.green)
                .voiceControlNames([L10n.tr("Dividir com a casa?"), L10n.tr("Dividir")])
            } footer: {
                Text("Ao dividir, qualquer morador pode receber essa tarefa. Sem dividir, ela fica apenas com quem você selecionou e não aparece para os outros moradores da casa.")
                    .italic()
            }
            
            // MARK: Delete (editing only)
            if viewModel.showsDeleteButton {
                Section {
                    deleteButton
                }
            }
        }
        .scrollContentBackground(.hidden)
        // The list's default top margin left a gap under the navigation bar.
        .contentMargins(.top, 0, for: .scrollContent)
        .background(Color.groupedBackground)
        .disabled(isFormLocked)
        .navigationTitle(viewModel.draft.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isBusy)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                confirmButton
            }
        }
    }
    
    /// Priority, duration and frequency menus.
    @ViewBuilder
    private var attributeRows: some View {
        let draft = viewModel.draft
        
        ChoreAttributeMenuRow(
            title: "Prioridade",
            value: draft.priorityTag.displayName.firstLetterCapitalized,
            color: draft.priorityTag.color,
            isSuggested: viewModel.isSuggested(.priority) // ✨ when the AI filled it
        ) {
            Picker("Prioridade", selection: handPicked(\.priorityTag, .priority)) {
                ForEach(PriorityTag.allCases.filter { $0 != .undefined }, id: \.self) { tag in
                    ChoreMenuOption(title: tag.displayName.firstLetterCapitalized, color: tag.color)
                        .tag(tag)
                }
            }
        }
        
        let tier = ChoreDurationTier.from(minutes: draft.duration)
        ChoreAttributeMenuRow(
            title: "Duração",
            value: tier.displayText.firstLetterCapitalized,
            color: tier.color,
            isSuggested: viewModel.isSuggested(.duration)
        ) {
            Picker("Duração", selection: durationTierBinding) {
                ForEach(ChoreDurationTier.allCases.filter { $0 != .undefined }, id: \.self) { tier in
                    ChoreMenuOption(title: tier.displayText.firstLetterCapitalized, color: tier.color)
                        .tag(tier)
                }
            }
        }
        
        ChoreAttributeMenuRow(
            title: "Frequência",
            value: draft.frequency.displayName.firstLetterCapitalized,
            color: draft.frequency.color,
            isSuggested: viewModel.isSuggested(.frequency)
        ) {
            Picker("Frequência", selection: handPicked(\.frequency, .frequency)) {
                ForEach(Recurrence.allCases.filter { $0 != .undefined }, id: \.self) { frequency in
                    ChoreMenuOption(title: frequency.displayName.firstLetterCapitalized, color: frequency.color)
                        .tag(frequency)
                }
            }
        }
    }
    
    @ViewBuilder
    private var confirmButton: some View {
        if isSubmitting || viewModel.isSaving {
            ProgressView()
                .voiceOverLabel(L10n.tr("Salvando"))
        } else {
            Button {
                isSubmitting = true
                Task {
                    if await viewModel.confirm() {
                        HapticsManager.notify(.success)
                        dismiss()
                    } else {
                        isSubmitting = false
                    }
                }
            } label: {
                Image(systemName: "checkmark")
            }
            .buttonStyle(.glassProminent)
            .tint(.blue)
            .disabled(!viewModel.canConfirm)
            .voiceOverLabel(L10n.tr("Confirmar"))
            .voiceControlNames([L10n.tr("Confirmar"), L10n.tr("Salvar"), L10n.tr("OK")])
        }
    }
    
    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            Text("Excluir Tarefa")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .disabled(isBusy)
        .voiceControlNames([L10n.tr("Excluir Tarefa"), L10n.tr("Excluir")])
    }
    
    // MARK: - Room symbol
    
    private var roomSymbol: some View {
        SymbolImage(name: viewModel.draft.room?.symbol ?? "kite")
            .foregroundStyle(roomColor)
            .frame(width: width * 0.4, height: height * 0.14)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
    
    // MARK: - Date
    
    /// "Calendário" with the picked date in a gray pill; tapping it opens the calendar.
    private var dateRow: some View {
        HStack {
            // ✨ while the date is the day said in the description.
            HStack(spacing: 6) {
                Text("Calendário")
                    .fontWeight(.semibold)
                if viewModel.isSuggested(.date) {
                    Image(systemName: "sparkles")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .voiceOverLabel(L10n.tr("Sugerido automaticamente"))
                }
            }
            
            Spacer()
            
            Button {
                showsCalendar = true
            } label: {
                Text(selectedDateText)
                    .foregroundStyle(viewModel.selectedDate == nil ? Color.secondary : Color.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray5), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.tr("Calendário"))
            .accessibilityValue(selectedDateText)
            .popover(isPresented: $showsCalendar) {
                CustomCalendar(
                    // Picking a day by hand keeps a later description from changing it.
                    selectedDate: Binding(
                        get: { viewModel.selectedDate },
                        set: {
                            viewModel.selectedDate = $0
                            viewModel.markChosenByHand(.date)
                        }
                    ),
                    window: viewModel.dateWindow,
                    opacityForDay: { viewModel.loadOpacity(on: $0) },
                    earliestSelectable: viewModel.earliestSelectableDay
                )
                .padding()
                .frame(width: 340)
                .presentationCompactAdaptation(.popover)
            }
        }
        .onChange(of: viewModel.selectedDate) { _, date in
            if date != nil { showsCalendar = false }
        }
    }
    
    private var selectedDateText: String {
        guard let date = viewModel.selectedDate else { return L10n.tr("Escolher data") }
        return date.formatted(.dateTime.day().month(.abbreviated).year().locale(L10n.locale))
    }
    
    private var durationTierBinding: Binding<ChoreDurationTier> {
        Binding(
            get: { ChoreDurationTier.from(minutes: viewModel.draft.duration) },
            set: {
                viewModel.draft.duration = $0.minutes
                viewModel.markChosenByHand(.duration)
            }
        )
    }
    
    // MARK: - Apple Intelligence

    /// A binding to a draft field that also records the person chose it, so a later
    /// description doesn't overwrite it.
    private func handPicked<Value>(
        _ keyPath: ReferenceWritableKeyPath<ChoreDTO, Value>,
        _ field: CreateAndEditChoreViewModel.SuggestedField
    ) -> Binding<Value> {
        Binding(
            get: { viewModel.draft[keyPath: keyPath] },
            set: {
                viewModel.draft[keyPath: keyPath] = $0
                viewModel.markChosenByHand(field)
            }
        )
    }

    /// Tap to speak, tap again to stop. Red while recording; it never spins (progress shows
    /// beside the spoken sentence).
    private var micButton: some View {
        Button {
            HapticsManager.selection()
            if voice.isListening {
                voice.stop()
            } else if !voice.isBusy {
                // Closing the keyboard shouldn't send the half-typed name: speech is read instead.
                lastReadName = viewModel.draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                isNameFocused = false
                isSpokenFocused = false
                spokenText = ""
                lastReadSpoken = ""
                aiDidFail = false
                Task { await voice.start(contextualStrings: viewModel.availableHouseUsers.map(\.name)) }
            }
        } label: {
            Image(systemName: voice.isListening ? "stop.fill" : "mic.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(voice.isListening ? Color.white : .black)
                .symbolEffect(.pulse, isActive: voice.isListening)
                .frame(width: 48, height: 48)
                .background(Circle().fill(voice.isListening ? Color.red : Color.white))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isSuggesting || voice.isPreparing || voice.isFinishing)
        .voiceOverLabel(voice.isListening ? L10n.tr("Parar de ouvir") : L10n.tr("Falar"))
        .voiceControlNames(voice.isListening
            ? [L10n.tr("Parar"), L10n.tr("Parar de ouvir")]
            : [L10n.tr("Falar"), L10n.tr("Microfone")])
    }

    /// The spoken sentence above the name: grey, editable, on one line with its icon. The icon
    /// slot shows a spinner while the speech is transcribed or read by the AI.
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
                        .foregroundStyle(.secondary)
                        .symbolEffect(.variableColor.iterative, isActive: voice.isListening)
                }
            }
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)

            TextField(L10n.tr("Ouvindo"), text: $spokenText, axis: .vertical)
                .font(.subheadline)
                .foregroundStyle(.secondary)
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

    /// "Nome: Lavar a louça" under a description being typed; tapping it fills the form now.
    private func previewPill(_ suggestion: ChoreSuggestion) -> some View {
        Button {
            lastReadName = viewModel.draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            apply(suggestion)
        } label: {
            Text(L10n.tr("Nome: \(suggestion.name)"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white, in: Capsule())
        }
        .buttonStyle(.plain)
        .transition(.opacity)
        .voiceOverHint(L10n.tr("Toque para preencher o formulário."))
    }

    private func suggestedTitle(_ title: LocalizedStringKey, isSuggested: Bool) -> some View {
        HStack(spacing: 6) {
            sectionTitle(title)
            if isSuggested {
                Image(systemName: "sparkles")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
                    .voiceOverLabel(L10n.tr("Sugerido automaticamente"))
            }
        }
        .animation(.snappy, value: isSuggested)
    }

    // MARK: Checklist ideas

    /// What the ideas depend on: the chore's name and room.
    private var checklistIdeasTrigger: String {
        "\(viewModel.draft.name)|\(viewModel.draft.room?.name ?? "")"
    }

    /// Ideas not already on the checklist; none once the person typed items of their own.
    private var visibleChecklistIdeas: [String] {
        guard canSuggest, !viewModel.hasHandWrittenChecklistItems else { return [] }
        let listed = Set(viewModel.draft.checklist.map { IntelligenceManager.foldedKey($0.name) })
        return checklistIdeas.filter { !listed.contains(IntelligenceManager.foldedKey($0)) }
    }

    /// Asks for ideas a moment after the name stops changing, once the name is a real name (not
    /// a description still being read).
    private func scheduleChecklistIdeas() {
        checklistIdeasTask?.cancel()
        let name = viewModel.draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = checklistIdeasTrigger
        guard canSuggest, !name.isEmpty, name.count <= TextLimits.choreName,
              key != checklistIdeasKey
        else { return }

        checklistIdeasTask = Task {
            do {
                try await Task.sleep(for: .seconds(1.2))
            } catch {
                return // Still typing.
            }
            // Wait for a description to be read first: its name is the one that counts.
            guard !isReadingDescription else { return }
            let ideas = await viewModel.checklistIdeas()
            guard !Task.isCancelled, key == checklistIdeasTrigger, let ideas else { return }
            checklistIdeasKey = key
            checklistIdeas = ideas
        }
    }

    /// One suggested step inside the checklist card: a dashed purple box on the AI tint, the
    /// step on the left and a purple "Adicionar" capsule on the right that adds it.
    private func checklistIdeaRow(_ idea: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .bold()
                .foregroundStyle(Color.black)
                .accessibilityHidden(true)

            Text(idea)
                .bold()
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer(minLength: 8)

            Button {
                HapticsManager.selection()
                withAnimation(.snappy) {
                    viewModel.addChecklistIdea(idea)
                }
                VoiceOver.announce(L10n.tr("\(idea) adicionado"))
            } label: {
                Text("Adicionar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.chorePurple.opacity(0.7), in: Capsule())
            }
            .buttonStyle(.plain)
            .voiceOverLabel(L10n.tr("Adicionar \(idea)"))
            .voiceControlNames([L10n.tr("Adicionar \(idea)"), idea])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.aiOpacity, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.chorePurple, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// Reads what was typed in the name, once per text.
    private func readTypedName() {
        let input = viewModel.draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSuggest, !voice.isBusy, !input.isEmpty, input != lastReadName else { return }
        lastReadName = input
        aiDidFail = false
        // The preview already read this exact text: use it instead of asking again.
        if let preview, preview.input == input {
            apply(preview)
            return
        }
        requestSuggestion(for: input, fromSpeech: false)
    }

    /// Reads the spoken sentence (as spoken or as corrected), once per text.
    private func readSpoken() {
        let input = spokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSuggest, !voice.isBusy, !input.isEmpty, input != lastReadSpoken else { return }
        lastReadSpoken = input
        aiDidFail = false
        requestSuggestion(for: input, fromSpeech: true)
    }

    /// After a short pause in typing, asks the AI what it would fill, to show "Nome: …".
    /// Only for descriptions of two words or more, before the form was filled from one.
    private func schedulePreview() {
        previewTask?.cancel()
        preview = nil
        let input = viewModel.draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSuggest, isNameFocused, !didFillFromDescription, !voice.isBusy,
              input != lastReadName,
              input.split(separator: " ").count >= 2
        else { return }

        previewTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(800))
            } catch {
                return // Still typing.
            }
            let result = await viewModel.suggestChore(for: input)
            let current = viewModel.draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !Task.isCancelled, let result, input == current else { return }
            // Worth showing only when the AI took something out of the text.
            if result.name.localizedCaseInsensitiveCompare(input) != .orderedSame {
                preview = result
            }
        }
    }

    private func requestSuggestion(for input: String, fromSpeech: Bool) {
        suggestionTask?.cancel()
        previewTask?.cancel()
        isSuggesting = true
        isReadingSpeech = fromSpeech
        suggestionTask = Task {
            defer {
                // A request replaced by a newer one leaves the newer one's state alone.
                if !Task.isCancelled {
                    isSuggesting = false
                    isReadingSpeech = false
                }
            }
            let result = await viewModel.suggestChore(for: input)
            guard !Task.isCancelled else { return }
            if let result {
                apply(result)
            } else {
                aiDidFail = true
                VoiceOver.announce(L10n.tr("Não foi possível preencher. Preencha manualmente."))
                // Typed: keep it, cut to the name limit so the chore can still go on. Spoken: the
                // sentence stays above and the name is left as it was.
                if !fromSpeech {
                    viewModel.draft.name = String(input.prefix(TextLimits.choreName))
                    lastReadName = viewModel.draft.name
                }
            }
        }
    }

    private func apply(_ suggestion: ChoreSuggestion) {
        previewTask?.cancel()
        preview = nil
        withAnimation(.snappy) {
            viewModel.apply(suggestion)
        }
        lastReadName = viewModel.draft.name
        didFillFromDescription = suggestion.name != suggestion.input
        // The sentence (typed or spoken) moves above the name, where it can be edited and read
        // again; only when the AI changed it, so a plain name isn't repeated there.
        if didFillFromDescription {
            spokenText = suggestion.input
            lastReadSpoken = suggestion.input
        }
        HapticsManager.notify(.success)
    }

    // MARK: - Helpers
    
    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }
    
    private func warning(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.red)
    }
}

// MARK: - Form field style

private extension String {
    var firstLetterCapitalized: String {
        prefix(1).uppercased(with: L10n.locale) + dropFirst()
    }
}

private extension View {
    func formField<S: Shape>(in shape: S) -> some View {
        padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: shape)
    }
}

#Preview("Edição") {
    let house = CKRecord.Reference(recordID: CKRecord.ID(recordName: "preview-house"), action: .none)
    let user = UserModel(
        name: "Ana",
        tier: .tier1,
        house: house,
        recordID: CKRecord.ID(recordName: "preview-user-Ana"),
        ownerRecordName: "preview-owner-Ana"
    )
    let chore = ChoreModel(
        name: "Lavar a louça",
        description: "Pratos, copos e panelas.",
        dueDate: Calendar.current.date(byAdding: .day, value: 2, to: Date()),
        frequency: .weekly,
        duration: 30,
        isPublic: true,
        priorityTag: .high
    )
    chore.recordID = CKRecord.ID(recordName: "preview-chore")
    
    return CreateAndEditChoreView(
        originalModel: chore,
        availableHouseUsers: [user],
        carouselViewModel: CarouselViewModel()
    )
}
