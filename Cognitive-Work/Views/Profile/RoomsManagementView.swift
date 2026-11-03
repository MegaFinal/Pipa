//
//  RoomsManagementView.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 06/10/26.
//

import SwiftUI

/// Shows the house's rooms as textured cards and
/// lets the user create, edit and delete them.
///
/// - Tapping a card opens ``RoomFormSheet``, zooming out of the card.
/// - The trailing "+" card (or the toolbar "+") creates a room.
/// - "Editar" in the toolbar makes the cards wiggle and shows a delete badge on each one;
///   a long press offers the same actions in a context menu.
struct RoomsManagementView: View {
    @State private var viewModel: RoomsManagementViewModel
    
    @State private var roomBeingEdited: RoomModel?
    @State private var isCreatingRoom = false
    @State private var roomPendingDeletion: RoomModel?
    
    @State private var isEditing = false
    
    @State private var hasAppeared = false
    
    private let columns = [GridItem(spacing: 16), GridItem(spacing: 16)]
    
    init(house: HouseModel?) {
        _viewModel = State(initialValue: RoomsManagementViewModel(house: house))
    }
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                // MARK: - Title, then the loading grid or the rooms
                header
                
                if viewModel.isLoading && viewModel.rooms.isEmpty {
                    loadingGrid
                } else {
                    roomsGrid
                }
            }
            .padding(.bottom, 30)
        }
        // MARK: - Pull to refresh and title
        .refreshable {
            await viewModel.load()
        }
        .navigationTitle("Seus cômodos")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBar()
        // MARK: - "Editar" / "OK" and "+" buttons
        .toolbar {
            if !viewModel.rooms.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(isEditing ? "OK" : "Editar") {
                        HapticsManager.impact(.light)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isEditing.toggle()
                        }
                        VoiceOver.announce(isEditing
                            ? L10n.tr("Toque no ícone vermelho para excluir um cômodo.")
                            : L10n.tr("Toque em um cômodo para editá-lo ou no + para criar um novo."))
                    }
                    .fontWeight(isEditing ? .semibold : .regular)
                    .voiceControlNames(isEditing
                        ? [L10n.tr("OK"), L10n.tr("Concluído")]
                        : [L10n.tr("Editar"), L10n.tr("Editar cômodos")])
                }
            }
        }
        // MARK: - Loading (and leaving delete mode when there are no rooms)
        .task {
            await viewModel.load()
            hasAppeared = true
        }
        .onChange(of: viewModel.rooms.isEmpty) { _, isEmpty in
            if isEmpty { isEditing = false }
        }
        // MARK: - New room and edit room sheets
        .sheet(isPresented: $isCreatingRoom) {
            RoomFormSheet(room: nil) { name, color, symbol, pattern in
                let didSave = await viewModel.createRoom(name: name, color: color, symbol: symbol, pattern: pattern)
                // The sheet shows its own error, the screen's alert can't appear over it.
                if !didSave { viewModel.errorMessage = nil }
                return didSave
            }
        }
        .sheet(item: $roomBeingEdited) { room in
            RoomFormSheet(room: room) { name, color, symbol, pattern in
                let didSave = await viewModel.updateRoom(room, name: name, color: color, symbol: symbol, pattern: pattern)
                if !didSave { viewModel.errorMessage = nil }
                return didSave
            }
        }
        // MARK: - Delete confirmation and error alerts
        .alert(
            deletionTitle,
            isPresented: Binding(
                get: { roomPendingDeletion != nil },
                set: { if !$0 { roomPendingDeletion = nil } }
            ),
            presenting: roomPendingDeletion
        ) { room in
            Button("Cancelar", role: .cancel) {}
            Button("Excluir", role: .destructive) {
                Task {
                    if await viewModel.deleteRoom(room) {
                        HapticsManager.notify(.success)
                        VoiceOver.announce(L10n.tr("Cômodo excluído"))
                    } else {
                        HapticsManager.notify(.error)
                    }
                }
            }
        } message: { room in
            Text(deletionMessage(for: room))
        }
        .alert(
            "Algo deu errado",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        // MARK: - Deleting overlay
        .blockingOperation(isPresented: $viewModel.isDeleting, message: "Excluindo cômodo...")
    }
    
    // MARK: - Header
    
    /// The text above the grid (it changes in delete mode).
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isEditing
                 ? LocalizedStringKey("Toque no ícone vermelho para excluir um cômodo.")
                 : LocalizedStringKey("Toque em um cômodo para editá-lo ou no + para criar um novo."))
                .foregroundColor(.subTitleGray)
                .contentTransition(.opacity)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 20)
        .padding(.horizontal, 24)
    }
    
    // MARK: - Grid
    
    /// The room cards and the "Novo cômodo" card.
    private var roomsGrid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(Array(viewModel.rooms.enumerated()), id: \.element.id) { index, room in
                // MARK: Room cards
                RoomCard(
                    room: room,
                    choreCount: viewModel.choreCount(for: room),
                    isEditing: isEditing,
                    wiggleDirection: index.isMultiple(of: 2) ? 1 : -1,
                    onDelete: { askToDelete(room) },
                    onEdit: { roomBeingEdited = room }
                )
                .onTapGesture {
                    HapticsManager.selection()
                    roomBeingEdited = room
                }
                .contextMenu {
                    Button {
                        roomBeingEdited = room
                    } label: {
                        Label("Editar", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        askToDelete(room)
                    } label: {
                        Label("Excluir", systemImage: "trash")
                    }
                }
                .staggeredEntrance(index: index, isVisible: hasAppeared)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            
            // MARK: "Novo cômodo" card
            AddRoomCard()
                .onTapGesture {
                    HapticsManager.selection()
                    isEditing = false
                    isCreatingRoom = true
                }
                .accessibilityAction {
                    isEditing = false
                    isCreatingRoom = true
                }
                .opacity(isEditing ? 0.4 : 1)
                .allowsHitTesting(!isEditing)
                // Not tappable in delete mode, so VoiceOver skips it too.
                .accessibilityHidden(isEditing)
                .staggeredEntrance(index: viewModel.rooms.count, isVisible: hasAppeared)
        }
        .padding(.horizontal)
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: viewModel.rooms.map(\.recordID))
    }
    
    /// Pulsing placeholders shown while the rooms load for the first time.
    private var loadingGrid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(0..<4, id: \.self) { index in
                PulsingPlaceholder(delay: Double(index) * 0.1)
            }
        }
        .padding(.horizontal)
        .accessibilityElement(children: .ignore)
        .voiceOverLabel(L10n.tr("Carregando cômodos"))
    }
    
    // MARK: - Deletion
    
    /// Asks the user to confirm deleting a room.
    private func askToDelete(_ room: RoomModel) {
        HapticsManager.notify(.warning)
        roomPendingDeletion = room
    }
    
    /// The delete alert's title: "Excluir \"<room>\"?".
    private var deletionTitle: String {
        guard let roomPendingDeletion else { return "" }
        return L10n.tr("Excluir \"\(roomPendingDeletion.name.localizedDefault)\"?")
    }
    
    /// The delete alert's message, saying how many chores go with the room.
    private func deletionMessage(for room: RoomModel) -> String {
        let count = viewModel.choreCount(for: room)
        switch count {
        case 0:
            return L10n.tr("Esta ação não pode ser desfeita.")
        case 1:
            return L10n.tr("A tarefa deste cômodo também será excluída. Esta ação não pode ser desfeita.")
        default:
            return L10n.tr("As \(count) tarefas deste cômodo também serão excluídas. Esta ação não pode ser desfeita.")
        }
    }
}

// MARK: - Room card

/// A room as a textured card in its color, with its icon, name and chore count — the same
/// visual language as the onboarding room cards.
private struct RoomCard: View {
    /// The room shown.
    let room: RoomModel
    /// How many chores the room has.
    let choreCount: Int
    /// Whether delete mode is on (wiggle and delete badge).
    let isEditing: Bool
    /// 1 or -1, so neighbouring cards wiggle in opposite directions.
    let wiggleDirection: Double
    /// Asks to delete the room.
    let onDelete: () -> Void
    /// Opens the edit sheet; used as the card's VoiceOver default action.
    var onEdit: (() -> Void)? = nil
    
    /// Flips back and forth to make the card wiggle.
    @State private var isWiggling = false
    
    /// How far the card tilts while wiggling (0 when not in delete mode).
    private var wiggleAmplitude: Double {
        isEditing ? 1.6 * wiggleDirection : 0
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // MARK: - Card (wiggling in delete mode)
            card
                .rotationEffect(.degrees(isWiggling ? wiggleAmplitude : -wiggleAmplitude))
                .animation(
                    isEditing
                    ? .easeInOut(duration: 0.13).repeatForever(autoreverses: true)
                    : .easeOut(duration: 0.15),
                    value: isWiggling
                )
                .onAppear { isWiggling = isEditing }
                .onChange(of: isEditing) { _, editing in
                    isWiggling = editing
                }
            
            // MARK: - Delete badge
            if isEditing {
                Button(action: onDelete) {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(.red, in: Circle())
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                }
                .buttonStyle(.plain)
                .offset(x: -8, y: -8)
                .transition(.scale.combined(with: .opacity))
                .voiceOverLabel(L10n.tr("Excluir \(room.name.localizedDefault)"))
                .voiceControlNames([L10n.tr("Excluir \(room.name.localizedDefault)"), L10n.tr("Excluir"), L10n.tr("Apagar")])
            }
        }
    }
    
    /// The textured card: icon, name and the chore count tag.
    private var card: some View {
        ZStack {
            VStack(spacing: 14) {
                SymbolImage(name: room.symbol)
                    .frame(width: 84, height: 84)
                    .accessibilityHidden(true)
                
                Text(room.name.localizedDefault)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            
            Text(choreCountText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.black.opacity(0.75))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.white.opacity(0.85), in: Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(10)
                .contentTransition(.numericText())
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background(RoomTextureBackground(room: room))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.25), radius: 6.85, x: 0, y: 4)
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            HapticsManager.selection()
            onEdit?()
        }
        // Alternative to the context menu / delete badge.
        .accessibilityAction(named: Text(L10n.tr("Excluir"))) {
            onDelete()
        }
        // Voice Control: "Toque em Quarto" / "Mostrar ações para Quarto", not the chore count.
        .voiceControlNames([room.name.localizedDefault, L10n.tr("Editar \(room.name.localizedDefault)")])
    }
    
    /// "Nenhuma tarefa", "1 tarefa" or "N tarefas".
    private var choreCountText: String {
        switch choreCount {
        case 0: L10n.tr("Nenhuma tarefa")
        case 1: L10n.tr("1 tarefa")
        default: L10n.tr("\(choreCount) tarefas")
        }
    }
}

/// The trailing card that creates a new room.
private struct AddRoomCard: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "plus")
                .font(.system(size: 40, weight: .light))
                .accessibilityHidden(true)
            Text("Novo cômodo")
                .fontWeight(.medium)
        }
        .foregroundStyle(.black.opacity(0.6))
        // Fill the whole square proposed by the grid — same size as ``RoomCard`` — instead of
        // shrinking to the icon and text, so the backgrounds below cover the full card.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white)
                .shadow(color: .black.opacity(0.25), radius: 6.85, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.black.opacity(0.15), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .padding(8)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .voiceControlNames([L10n.tr("Novo cômodo"), L10n.tr("Adicionar"), L10n.tr("Mais")])
    }
}

// MARK: - Entrance animation

private extension View {
    /// Rises and fades the view in, one grid cell after the other.
    func staggeredEntrance(index: Int, isVisible: Bool) -> some View {
        self
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 24)
            .scaleEffect(isVisible ? 1 : 0.92)
            .animation(
                .spring(response: 0.5, dampingFraction: 0.8).delay(Double(min(index, 10)) * 0.05),
                value: isVisible
            )
    }
}

// MARK: - Form sheet

/// Sheet used both to create a room (`room == nil`) and to edit an existing one.
///
/// The top of the sheet is the room's own texture, so the user sees the card change as they
/// pick a color, texture or icon. Default room types (Quarto, Cozinha…) have a fixed look, so
/// only their name can be changed; custom rooms can also pick a color, a texture and an icon.
///
/// Also used by the onboarding (see ``NewRoomSheet``), so both screens create rooms the same way.
struct RoomFormSheet: View {
    /// Closes the sheet.
    @Environment(\.dismiss) private var dismiss
    
    /// The room to edit, or `nil` to create one.
    let room: RoomModel?
    /// Persists the form. Returns `true` when the sheet can close.
    let onSave: @MainActor (_ name: String, _ color: RoomColor, _ symbol: String, _ pattern: RoomTexturePattern) async -> Bool
    
    /// The name being typed.
    @State private var name: String
    /// The color picked.
    @State private var selectedColor: RoomColor
    /// The icon picked.
    @State private var selectedSymbol: String
    /// The texture picked.
    @State private var selectedPattern: RoomTexturePattern
    /// `true` while saving.
    @State private var isSaving = false
    /// Shows the "couldn't save" message.
    @State private var didFailToSave = false
    /// Bumped on every save failure to shake the name field.
    @State private var failureCount = 0
    /// Focuses the name field when creating a room.
    @FocusState private var isNameFocused: Bool
    
    /// Six columns for the icon grid.
    private let symbolColumns = Array(repeating: GridItem(spacing: 12), count: 6)
    
    /// Creates the sheet.
    /// - Parameters:
    ///   - room: The room to edit, or `nil` to create one.
    ///   - onSave: Saves the form. Returns `true` when the sheet can close.
    init(room: RoomModel?, onSave: @escaping @MainActor (_ name: String, _ color: RoomColor, _ symbol: String, _ pattern: RoomTexturePattern) async -> Bool) {
        self.room = room
        self.onSave = onSave
        _name = State(initialValue: room?.name ?? "")
        _selectedColor = State(initialValue: room?.color ?? .purple)
        _selectedSymbol = State(initialValue: room?.symbol ?? RoomsManagementViewModel.customRoomSymbol)
        _selectedPattern = State(initialValue: room?.texturePattern ?? .fallback)
    }
    
    /// Whether it edits an existing room.
    private var isEditingRoom: Bool { room != nil }
    
    /// Default room types (Quarto, Cozinha…) can only change their name.
    private var isLookLocked: Bool {
        guard let room else { return false }
        return RoomsManagementViewModel.isDefaultType(room)
    }
    
    /// The texture shown everywhere in the sheet: the picked one, or the fallback when the
    /// picked color has no image of it.
    private var pattern: RoomTexturePattern {
        selectedPattern.resolved(for: selectedColor)
    }
    
    /// The name without spaces at the ends.
    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }
    
    /// Whether the name is reserved for the house-wide room.
    private var isReservedName: Bool {
        RoomsManagementViewModel.isReservedName(trimmedName)
    }
    
    /// Whether the form can be saved.
    private var canSave: Bool {
        !trimmedName.isEmpty && !isReservedName && !isSaving
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    // MARK: - Preview, name, and look pickers (locked for default rooms)
                    hero
                    nameField
                    
                    if isLookLocked {
                        Label("A cor, o grafismo e o ícone dos cômodos padrão não podem ser alterados.", systemImage: "lock.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    } else {
                        colorPicker
                        symbolPicker
                        patternPicker
                    }
                }
                .padding(.bottom, 30)
            }
            .ignoresSafeArea(edges: .top)
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle(isEditingRoom ? "Editar Cômodo" : "Novo Cômodo")
            .navigationBarTitleDisplayMode(.inline)
            // MARK: - Cancel and save buttons
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .voiceOverLabel(L10n.tr("Cancelar"))
                    .voiceControlNames([L10n.tr("Fechar"), L10n.tr("Cancelar")])
                    .disabled(isSaving)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .voiceOverLabel(L10n.tr("Salvando"))
                    } else {
                        Button {
                            save()
                        } label: {
                            Image(systemName: "checkmark")
                        }
                        .voiceOverLabel(L10n.tr("Salvar"))
                        .voiceControlNames([L10n.tr("Confirmar"), L10n.tr("Salvar"), L10n.tr("OK")])
                        .disabled(!canSave)
                    }
                }
            }
            .dismissKeyboardOnTap()
            .interactiveDismissDisabled(isSaving)
            .onAppear {
                if !isEditingRoom { isNameFocused = true }
            }
        }
    }
    
    // MARK: - Hero
    
    /// The room's texture across the top of the sheet, with its icon on a floating card.
    private var hero: some View {
        ZStack {
            RoomTextureBackground(color: selectedColor, pattern: pattern, zoom: 3)
                .id("\(selectedColor.rawValue).\(pattern.rawValue)")
                .transition(.opacity)
            
            SymbolImage(name: selectedSymbol)
                .foregroundStyle(.white)
                .frame(width: 96, height: 96)
                .id(selectedSymbol)
                .transition(.opacity)
                .frame(width: 140, height: 140)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(selectedColor.uiColor)
                        .shadow(color: .black.opacity(0.25), radius: 6.85, x: 0, y: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(0.6), lineWidth: 2)
                )
                .padding(.top, 50)
        }
        .frame(height: 260)
        .frame(maxWidth: .infinity)
        .clipped()
        .animation(.easeInOut(duration: 0.3), value: selectedColor)
        .animation(.easeInOut(duration: 0.3), value: pattern)
        // One summary of the live preview instead of an unlabeled icon.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.tr("Pré-visualização do cômodo: \(ProfileAccessibility.symbolName(selectedSymbol)), \(selectedColor.voiceOverName), \(pattern.displayName)"))
        .accessibilityAddTraits(.isImage)
    }
    
    // MARK: - Name
    
    /// The big name field with its underline and error messages; shakes when saving fails.
    private var nameField: some View {
        VStack(spacing: 6) {
            TextField("Nome do Cômodo", text: $name)
                .characterLimit(TextLimits.roomName, text: $name)
                .focused($isNameFocused)
                .submitLabel(.done)
                .voiceControlNames([L10n.tr("Nome do Cômodo"), L10n.tr("Nome")])
                .font(.system(size: 34))
                .bold()
                .multilineTextAlignment(.center)
            
            Capsule()
                .fill(isNameFocused ? selectedColor.uiColor : Color.primary.opacity(0.8))
                .frame(height: isNameFocused ? 3 : 1)
                .animation(.easeInOut(duration: 0.2), value: isNameFocused)
            
            Group {
                if isReservedName {
                    Text("Este nome é reservado para tarefas da casa toda.")
                } else if didFailToSave {
                    Text("Não foi possível salvar o cômodo. Verifique sua conexão e tente novamente.")
                }
            }
            .font(.footnote)
            .foregroundStyle(.red)
            .multilineTextAlignment(.center)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
        .padding(.horizontal, 40)
        .modifier(ShakeEffect(shakes: CGFloat(failureCount)))
        .animation(.linear(duration: 0.4), value: failureCount)
        .animation(.easeInOut(duration: 0.2), value: isReservedName)
        .animation(.easeInOut(duration: 0.2), value: didFailToSave)
        .onChange(of: isReservedName) { _, isReserved in
            if isReserved {
                VoiceOver.announce(L10n.tr("Este nome é reservado para tarefas da casa toda."))
            }
        }
    }
    
    // MARK: - Color
    
    /// One textured circle per room color.
    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Cor")
            
            HStack(spacing: 0) {
                ForEach(RoomColor.allCases) { color in
                    ColorSwatch(color: color, isSelected: selectedColor == color) {
                        HapticsManager.selection()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                            selectedColor = color
                            // Keep what's saved equal to what's shown when this color lacks
                            // the picked texture.
                            selectedPattern = selectedPattern.resolved(for: color)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 24)
    }
    
    // MARK: - Pattern
    
    /// One textured tile per pattern, in the selected color. Patterns the asset catalog
    /// doesn't have in that color are shown disabled.
    private var patternPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Grafismo")
            
            HStack(spacing: 10) {
                ForEach(RoomTexturePattern.allCases, id: \.self) { option in
                    PatternSwatch(
                        color: selectedColor,
                        pattern: option,
                        isSelected: pattern == option,
                        isAvailable: option.isAvailable(for: selectedColor)
                    ) {
                        HapticsManager.selection()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                            selectedPattern = option
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 24)
    }
    
    // MARK: - Symbol
    
    /// The grid of icons a custom room can use.
    private var symbolPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Ícone")
            
            LazyVGrid(columns: symbolColumns, spacing: 12) {
                ForEach(RoomsManagementViewModel.customRoomSymbols, id: \.self) { symbol in
                    let isSelected = selectedSymbol == symbol
                    
                    SymbolImage(name: symbol)
                        // Wide glyphs shrink to fit instead of overflowing.
                        .frame(width: 36, height: 36)
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        // Fill the whole grid cell as a square so the circle behind is full size.
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .background(
                            Circle()
                                .fill(isSelected ? selectedColor.uiColor : Color.gray.opacity(0.12))
                        )
                        .scaleEffect(isSelected ? 1.08 : 1)
                        .contentShape(Circle())
                        .onTapGesture {
                            HapticsManager.selection()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                                selectedSymbol = symbol
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .voiceOverLabel(ProfileAccessibility.symbolName(symbol))
                        .voiceControlNames([ProfileAccessibility.symbolName(symbol)])
                        .accessibilityAddTraits(.isButton)
                        .voiceOverTraits(.isSelected, when: isSelected)
                        .accessibilityAction {
                            HapticsManager.selection()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                                selectedSymbol = symbol
                            }
                        }
                }
            }
        }
        .padding(.horizontal, 24)
    }
    
    /// A section's bold title.
    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 20, weight: .bold))
            .accessibilityAddTraits(.isHeader)
    }
    
    // MARK: - Save
    
    /// Saves the form; closes the sheet on success, or shakes and shows the error.
    private func save() {
        guard !isSaving else { return }
        isNameFocused = false
        Task { @MainActor in
            isSaving = true
            didFailToSave = false
            let didSave = await onSave(trimmedName, selectedColor, selectedSymbol, pattern)
            isSaving = false
            
            if didSave {
                HapticsManager.notify(.success)
                dismiss()
            } else {
                HapticsManager.notify(.error)
                didFailToSave = true
                failureCount += 1
                VoiceOver.announce(L10n.tr("Não foi possível salvar o cômodo. Verifique sua conexão e tente novamente."))
            }
        }
    }
}

/// Horizontal shake used when saving fails. Animating `shakes` by 1 plays one shake.
nonisolated private struct ShakeEffect: GeometryEffect {
    /// How many shakes have played (animated).
    var shakes: CGFloat
    
    /// Lets SwiftUI animate `shakes`.
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }
    
    /// Moves the view sideways following a sine wave.
    func effectValue(size: CGSize) -> ProjectionTransform {
        let offset = 10 * sin(shakes * .pi * 4)
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}

/// Gray card that pulses while the rooms load.
private struct PulsingPlaceholder: View {
    /// Seconds before this card starts pulsing (so they pulse one after the other).
    let delay: Double
    /// Flips to make the card pulse.
    @State private var isDimmed = false
    
    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.gray.opacity(0.15))
            .aspectRatio(1, contentMode: .fit)
            .opacity(isDimmed ? 0.4 : 1)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true).delay(delay), value: isDimmed)
            .onAppear { isDimmed = true }
    }
}

extension RoomTextureBackground {
    /// Same background with a different texture opacity.
    func withTextureOpacity(_ opacity: Double) -> Self {
        var copy = self
        copy.textureOpacity = opacity
        return copy
    }
}

/// A color option shown as a small textured circle of that color.
struct ColorSwatch: View {
    let color: RoomColor
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
            Circle()
            .foregroundColor(color.uiColor)
            .frame(width: 40, height: 40)
            .overlay {
                Circle()
                    .stroke(color.uiColor, lineWidth: 3)
                    .padding(-4)
                    .opacity(isSelected ? 1 : 0)
                    .scaleEffect(isSelected ? 1 : 0.7)
            }
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .scaleEffect(isSelected ? 1.1 : 1)
            .contentShape(Circle())
            .onTapGesture(perform: action)
            .accessibilityElement(children: .ignore)
            .voiceOverLabel(color.voiceOverName)
            .voiceControlNames([color.voiceOverName])
            .accessibilityAddTraits(.isButton)
            .voiceOverTraits(.isSelected, when: isSelected)
            .accessibilityAction { action() }
    }
}

/// A texture option: a rounded tile of the selected color with that texture, and its name.
struct PatternSwatch: View {
    /// The color of the tile.
    let color: RoomColor
    /// The texture shown.
    let pattern: RoomTexturePattern
    /// Whether this texture is picked.
    let isSelected: Bool
    /// Whether this texture exists in the color (otherwise it's faded and can't be picked).
    let isAvailable: Bool
    /// Picks this texture.
    let action: () -> Void
    
    var body: some View {
        VStack {
            RoomTextureBackground(color: color, pattern: pattern, zoom: 3.5)
                .withTextureOpacity(0.45)
//                .aspectRatio(1, contentMode: .fit)
                
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(color.uiColor, lineWidth: 3)
                        .padding(-4.5)
                        .opacity(isSelected ? 1 : 0)
                }
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .scaleEffect(isSelected ? 1.06 : 1)
                .frame(width: 50, height: 50)
        }
        .opacity(isAvailable ? 1 : 0.3)
        .contentShape(Rectangle())
        .onTapGesture {
            guard isAvailable else { return }
            action()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(pattern.displayName))
        .voiceControlNames([pattern.displayName])
        .accessibilityAddTraits(.isButton)
        .voiceOverTraits(.isSelected, when: isSelected)
        .voiceOverHint(isAvailable ? "" : L10n.tr("Indisponível nesta cor"))
        .accessibilityAction {
            guard isAvailable else { return }
            action()
        }
    }
}

#Preview("Cômodos") {
    NavigationStack {
        RoomsManagementView(house: HouseModel(name: "Casa", description: "Casa para o preview"))
    }
}

#Preview("Novo cômodo") {
    RoomFormSheet(room: nil) { _, _, _, _ in true }
}

#Preview("Editar cômodo padrão") {
    RoomFormSheet(room: RoomModel(name: "Cozinha", symbol: "cooktop", color: .yellow, kind: "Cozinha")) { _, _, _, _ in true }
}
