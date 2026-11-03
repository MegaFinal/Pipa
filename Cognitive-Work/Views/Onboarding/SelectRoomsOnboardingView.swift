//
//  FourthOnboardingView.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 19/08/26.
//

import SwiftUI

/// The step where the user picks which rooms their house has.
///
/// The rooms (``OnboardingViewModel/availableRooms``) are shown as a two-column grid of
/// ``OnboardingRoomCard`` items:
/// - Tapping a card selects or unselects it.
/// - A long press opens ``RoomQuantityEditor`` to set how many rooms of that type exist and their names.
/// - The "add" card opens ``NewRoomSheet`` to create a custom room.
///
/// "Continuar" saves the chosen rooms with ``OnboardingViewModel/saveSelectedRooms()``.
struct SelectRoomsOnboardingView: View {

    // MARK: - Properties

    /// State shared by every step of the flow.
    @Binding var viewModel: OnboardingViewModel
    
    /// Whether the sheet for creating a custom room is currently presented
    @State private var isShowingCustomRoomSheet = false
    
    /// The room type whose quantity and names are being edited (after a long press), or `nil`.
    @State private var editingRoomID: UUID?
    
    /// The card being pressed right now, so it can shrink under the finger while the long
    /// press builds up.
    @State private var pressingRoomID: UUID?
    
    /// The editor's current height, measured so it can be flipped above its card when it
    /// wouldn't fit below.
    @State private var editorHeight: CGFloat = 0
    
    /// The two-column grid layout used to display room cards
    let columns = [GridItem(), GridItem()]

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // MARK: - Title and description
                OnboardingHeader(
                    title: "Defina os cômodos",
                    description: "Escolha os ambientes presentes na sua residência, aperte e segure para editar seus nomes e quantidades."
                )
                
                // MARK: - Room cards
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(viewModel.availableRooms) { roomDraft in
                        OnboardingRoomCard(
                            text: roomDraft.name,
                            symbol: roomDraft.symbol,
                            color: roomDraft.color,
                            pattern: roomDraft.texturePattern,
                            isSelected: roomDraft.isSelected,
                            quantity: roomDraft.quantity
                        )
                        // MARK: Tap to select
                        .onTapGesture {
                            if !viewModel.isLoading {
                                if roomDraft.isAddButton {
                                    isShowingCustomRoomSheet = true
                                } else {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        viewModel.toggleRoomSelection(id: roomDraft.id)
                                    }
                                }
                            }
                        }
                        // MARK: Long press to edit
                        // Long press opens the quantity/name editor for this room type. The card
                        // sinks while the finger is down, so the user sees something is happening.
                        .onLongPressGesture(minimumDuration: 0.25) {
                            guard !viewModel.isLoading, !roomDraft.isAddButton else { return }
                            startEditing(roomDraft)
                        } onPressingChanged: { isPressing in
                            guard !roomDraft.isAddButton || !isPressing else { return }
                            withAnimation(isPressing ? .easeOut(duration: 0.15) : .spring(response: 0.25, dampingFraction: 0.6)) {
                                pressingRoomID = isPressing ? roomDraft.id : nil
                            }
                        }
                        // MARK: Accessibility
                        // VoiceOver: one button per card; the long press becomes a named action.
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(roomAccessibilityLabel(roomDraft)))
                        .accessibilityAddTraits(.isButton)
                        .voiceOverTraits(.isSelected, when: roomDraft.isSelected && !roomDraft.isAddButton)
                        .voiceOverHint(roomDraft.isAddButton ? L10n.tr("Abre o formulário para criar um cômodo") : "")
                        .accessibilityAction {
                            guard !viewModel.isLoading else { return }
                            if roomDraft.isAddButton {
                                isShowingCustomRoomSheet = true
                            } else {
                                viewModel.toggleRoomSelection(id: roomDraft.id)
                            }
                        }
                        // Voice Control: "Toque em Quarto" / "Mostrar ações para Quarto" (the
                        // VoiceOver label also carries the quantity, which is awkward to say).
                        .voiceControlNames(roomInputLabels(roomDraft))
                        .accessibilityActions {
                            if !roomDraft.isAddButton {
                                Button(L10n.tr("Editar nomes e quantidade")) {
                                    guard !viewModel.isLoading else { return }
                                    startEditing(roomDraft)
                                }
                            }
                        }
                        // MARK: Pressed and editing looks, and the card's bounds for the editor
                        .scaleEffect(pressingRoomID == roomDraft.id ? 0.9 : 1)
                        .opacity(editingRoomID != nil && editingRoomID != roomDraft.id ? 0.55 : 1)
                        .anchorPreference(key: RoomCardBoundsKey.self, value: .bounds) {
                            [roomDraft.id: $0]
                        }
                    }
                }
                .padding(.horizontal)
                
                // MARK: - "Continuar" button
                OnboardingProgressButton(text: "Continuar", isLoading: viewModel.isLoading, isDisabled: !viewModel.hasSelectedRooms) {
                    Task {
                        await viewModel.saveSelectedRooms()
                        // `isLoading` is always false here, even on failure; check the error instead.
                        if viewModel.errorMessage == nil {
                            viewModel.goToNextView()
                        }
                  }
                }
            }
            Spacer()
        }
        // MARK: - Quantity editor popup over a dimmed background
        .overlayPreferenceValue(RoomCardBoundsKey.self) { cardBounds in
            if let editingRoomID,
               let index = viewModel.availableRooms.firstIndex(where: { $0.id == editingRoomID }) {
                GeometryReader { proxy in
                    let placement = editorPlacement(
                        cardFrame: cardBounds[editingRoomID].map { proxy[$0] },
                        in: proxy.size
                    )
                    
                    ZStack(alignment: .topLeading) {
                        Color.black.opacity(0.35)
                            .ignoresSafeArea()
                            .onTapGesture { stopEditing() }
                            // For VoiceOver the dimmed backdrop is the editor's "close" button,
                            // read after the editor's own controls.
                            .accessibilityElement()
                            .accessibilityLabel(Text(L10n.tr("Fechar editor")))
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { stopEditing() }
                            .voiceControlNames([L10n.tr("Fechar"), L10n.tr("Fechar editor"), L10n.tr("Cancelar")])
                            .accessibilitySortPriority(-1)
                        
                        // The card being edited is redrawn above the dim, lifted, so it stays
                        // bright and it is clear which room the editor belongs to.
                        if let cardFrame = cardBounds[editingRoomID].map({ proxy[$0] }) {
                            let room = viewModel.availableRooms[index]
                            OnboardingRoomCard(
                                text: room.name,
                                symbol: room.symbol,
                                color: room.color,
                                pattern: room.texturePattern,
                                isSelected: true,
                                quantity: room.quantity
                            )
                            .scaleEffect(1.06)
                            .shadow(color: room.color.uiColor.opacity(0.55), radius: 14, x: 0, y: 6)
                            .position(x: cardFrame.midX, y: cardFrame.midY)
                            .allowsHitTesting(false)
                            .transition(.scale(scale: 0.92).combined(with: .opacity))
                            .accessibilityHidden(true)
                        }
                        
                        RoomQuantityEditor(room: $viewModel.availableRooms[index])
                            .frame(width: placement.width)
                            .onGeometryChange(for: CGFloat.self) { geometry in
                                geometry.size.height
                            } action: { height in
                                editorHeight = height
                            }
                            .offset(x: placement.origin.x, y: placement.origin.y)
                            .transition(.scale(scale: 0.9, anchor: placement.anchor).combined(with: .opacity))
                    }
                    // A modal popup: VoiceOver stays inside, and the escape gesture closes it.
                    .accessibilityElement(children: .contain)
                    .accessibilityAddTraits(.isModal)
                    .accessibilityAction(.escape) { stopEditing() }
                }
                .transition(.opacity)
            }
        }
        // MARK: - New room sheet, back button and error alert
        .sheet(isPresented: $isShowingCustomRoomSheet) {
            NewRoomSheet()
                .environment(viewModel)
                .presentationDetents([.large])
        }
        .onboardingBackButton(viewModel: viewModel)
        .navigationBarBackButtonHidden()
        .alert("Não foi possível salvar os cômodos", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
    
    // MARK: - Editing
    
    /// Opens the editor for a room type, selecting it too: setting how many rooms of a type
    /// the house has
    private func startEditing(_ room: RoomDTO) {
        HapticsManager.impact(.medium)
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if !room.isSelected {
                viewModel.toggleRoomSelection(id: room.id)
            }
            editingRoomID = room.id
        }
        VoiceOver.screenChanged()
    }
    
    /// What VoiceOver reads for a room card: its name and, when there's more than one, how many.
    private func roomAccessibilityLabel(_ room: RoomDTO) -> String {
        if room.isAddButton { return L10n.tr("Adicionar cômodo") }
        let name = room.name.localizedDefault
        return room.quantity > 1 ? L10n.tr("\(name), \(room.quantity) cômodos") : name
    }
    
    /// Short names Voice Control users can say for a room card: the visible name first.
    private func roomInputLabels(_ room: RoomDTO) -> [String] {
        let name = room.name.localizedDefault
        if room.isAddButton { return [name, L10n.tr("Adicionar cômodo"), L10n.tr("Adicionar")] }
        return [name]
    }
    
    /// Where the editor goes: under the card (or above it when it doesn't fit), on the card's side.
    private func editorPlacement(cardFrame: CGRect?, in size: CGSize) -> EditorPlacement {
        let margin: CGFloat = 16
        let gap: CGFloat = 8
        let width = min(size.width - margin * 2, 320)
        
        guard let cardFrame else {
            return EditorPlacement(
                origin: CGPoint(x: (size.width - width) / 2, y: max(margin, (size.height - editorHeight) / 2)),
                width: width,
                anchor: .center
            )
        }
        
        let isRightColumn = cardFrame.midX > size.width / 2
        let x = isRightColumn ? size.width - margin - width : margin
        
        var y = cardFrame.maxY + gap
        var opensBelow = true
        
        if y + editorHeight > size.height - margin {
            let above = cardFrame.minY - gap - editorHeight
            if above >= margin {
                y = above
                opensBelow = false
            } else {
                y = max(margin, size.height - margin - editorHeight)
            }
        }
        
        // Grows out of the corner closest to the card.
        let anchor: UnitPoint
        switch (isRightColumn, opensBelow) {
        case (true, true): anchor = .topTrailing
        case (false, true): anchor = .topLeading
        case (true, false): anchor = .bottomTrailing
        case (false, false): anchor = .bottomLeading
        }
        
        return EditorPlacement(origin: CGPoint(x: x, y: y), width: width, anchor: anchor)
    }
    
    /// Closes the editor (and the keyboard).
    private func stopEditing() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        
        withAnimation(.easeOut(duration: 0.2)) {
            editingRoomID = nil
        }
        VoiceOver.screenChanged()
    }
}

// MARK: - Editor placement

/// Where ``RoomQuantityEditor`` is drawn, relative to the screen's top-leading corner.
private struct EditorPlacement {
    /// The editor's top-leading corner.
    var origin: CGPoint
    /// The editor's width.
    var width: CGFloat
    /// The corner it scales in from.
    var anchor: UnitPoint
}

/// Each room card's bounds, keyed by ``RoomDTO/id``, so the editor can open right under the
/// card being edited.
private struct RoomCardBoundsKey: PreferenceKey {
    /// No bounds yet.
    static let defaultValue: [UUID: Anchor<CGRect>] = [:]
    
    /// Merges the bounds of every card.
    static func reduce(value: inout [UUID: Anchor<CGRect>], nextValue: () -> [UUID: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, latest in latest }
    }
}

// MARK: - Private subviews

/// A selectable card for one room type: its icon and name.
///
/// Unselected it is white with black content; selected it takes the room's color and texture
/// with white content. When the house has more than one room of the type, a "×N" badge shows.
///
/// Selection is handled by the parent view.
private struct OnboardingRoomCard: View {
    
    /// The room's name.
    var text: String
    /// The room's SF Symbol.
    var symbol: String
    /// The room's color (when selected).
    var color: RoomColor
    /// The room's texture (when selected).
    var pattern: RoomTexturePattern
    /// Whether the room is selected.
    var isSelected: Bool = false
    
    /// How many rooms of this type were set with a long press; shown as a badge above one.
    var quantity: Int = 1
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // MARK: - Card and "×N" badge
            content
            
            if quantity > 1 {
                Text("×\(quantity)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isSelected ? color.uiColor : .black)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(.white, in: Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
                    .offset(x: -8, y: 8)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: quantity)
    }
    
    /// The icon and name over the card's background.
    private var content: some View {
        ZStack {
            SymbolImage(name: symbol)
                .frame(width: width * 0.25, height: height * 0.12)
                .padding(.bottom, 20)
                .foregroundColor(isSelected ? .white : .black)
            
            Text(L10n.tr(key: text))
                .fontWeight(.medium)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 20)
                .foregroundColor(isSelected ? .white : .black)
        }
        .frame(width: width * 0.42, height: height * 0.2)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .foregroundColor(isSelected ? color.uiColor : .white)
                .shadow(color: .black.opacity(0.25), radius: 6.85, x: 0, y: 4)
                .overlay {
                    if isSelected {
                        RoomTextureBackground(color: color, pattern: pattern)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
        )
    }
}

/// The card shown on a long press over a room type: how many rooms of that type the house
/// has, and each one's name.
private struct RoomQuantityEditor: View {
    
    /// The room type being edited.
    @Binding var room: RoomDTO
    
    /// The name field being edited.
    @FocusState private var focusedInstance: UUID?
    
    /// The most rooms of one type.
    private let maxQuantity = 10
    /// The longest room name.
    private let maxNameLength = TextLimits.roomName
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // MARK: - "Quantidade" and the stepper
            HStack {
                Text("Quantidade")
                    .font(.system(size: 22, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                
                Spacer()
                
                quantityStepper
            }
            
            // MARK: - One name field per room
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(room.instances.enumerated()), id: \.element.id) { index, instance in
                    nameRow(index: index, instance: instance)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 25))
        // Absorbs taps on the popup's empty areas so they don't reach the dimmed backdrop,
        // which closes the editor. Buttons and the text field still take priority.
        .contentShape(RoundedRectangle(cornerRadius: 25))
        .onTapGesture {}
        .onChange(of: focusedInstance) { _, _ in
            restoreDefaultForEmptyNames()
        }
    }
    
    // MARK: - Subviews
    
    /// The − / + buttons and the count.
    private var quantityStepper: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.snappy) { room.setQuantity(room.quantity - 1) }
            } label: {
                Image(systemName: "minus")
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(room.quantity > 1 ? Color.black : Color.gray.opacity(0.5))
            .disabled(room.quantity <= 1)
            
            Text("\(room.quantity)")
                .font(.system(size: 22, weight: .semibold))
                .frame(minWidth: 24)
            
            Button {
                withAnimation(.snappy) { room.setQuantity(room.quantity + 1) }
            } label: {
                Image(systemName: "plus")
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(room.quantity < maxQuantity ? Color.black : Color.gray.opacity(0.5))
            .disabled(room.quantity >= maxQuantity)
        }
        .font(.system(size: 22, weight: .medium))
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.06), in: Capsule())
        // VoiceOver: one adjustable element (swipe up/down) instead of two small buttons.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(L10n.tr("Quantidade de \(room.name.localizedDefault)")))
        .accessibilityValue(Text(verbatim: "\(room.quantity)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                guard room.quantity < maxQuantity else { return }
                withAnimation(.snappy) { room.setQuantity(room.quantity + 1) }
            case .decrement:
                guard room.quantity > 1 else { return }
                withAnimation(.snappy) { room.setQuantity(room.quantity - 1) }
            @unknown default:
                break
            }
        }
        // Voice Control can't swipe-adjust: "Mostrar ações para Quantidade" offers these.
        .voiceControlNames([L10n.tr("Quantidade"), L10n.tr("Quantidade de \(room.name.localizedDefault)")])
        .accessibilityAction(named: Text(L10n.tr("Aumentar"))) {
            guard room.quantity < maxQuantity else { return }
            withAnimation(.snappy) { room.setQuantity(room.quantity + 1) }
        }
        .accessibilityAction(named: Text(L10n.tr("Diminuir"))) {
            guard room.quantity > 1 else { return }
            withAnimation(.snappy) { room.setQuantity(room.quantity - 1) }
        }
    }
    
    /// One room's name field with its pencil button.
    private func nameRow(index: Int, instance: RoomInstanceDTO) -> some View {
        let name = nameBinding(at: index)
        
        return HStack(spacing: 0) {
            TextField(room.instanceName(at: index).localizedDefault, text: name)
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .focused($focusedInstance, equals: instance.id)
                .submitLabel(.done)
                .characterLimit(maxNameLength, text: name)
                .accessibilityLabel(Text(L10n.tr("Nome do cômodo \(index + 1)")))
                .voiceControlNames([room.instanceName(at: index).localizedDefault, L10n.tr("Nome do cômodo \(index + 1)")])
            
            // Tapping the pencil puts the cursor in this room's name field. The hit area is
            // larger than the icon so it is easy to tap.
            Button {
                HapticsManager.selection()
                focusedInstance = instance.id
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .voiceOverLabel(L10n.tr("Editar nome do cômodo \(index + 1)"))
            .voiceControlNames([L10n.tr("Editar nome do cômodo \(index + 1)"), L10n.tr("Editar")])
        }
    }
    
    // MARK: - Names
    
    /// Reads the room's current name; writing stores it as a custom name.
    ///
    /// What the user typed is returned exactly as typed. Only the untouched default name
    /// ("Quarto 2") is shown translated. Translating the typed text on every keystroke turned
    /// "qua" into "Wed" for people using the phone in English.
    private func nameBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                if room.instances.indices.contains(index), let customName = room.instances[index].customName {
                    return customName
                }
                return room.instanceName(at: index).localizedDefault
            },
            set: { newName in
                guard room.instances.indices.contains(index) else { return }
                room.instances[index].customName = newName
            }
        )
    }
    
    /// A name left empty goes back to the default one once the field loses focus.
    private func restoreDefaultForEmptyNames() {
        for index in room.instances.indices {
            let customName = room.instances[index].customName ?? ""
            if room.instances[index].customName != nil,
               customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                room.instances[index].customName = nil
            }
        }
    }
}

#Preview {
    @Previewable @State var viewModel = OnboardingViewModel()
    return SelectRoomsOnboardingView(viewModel: $viewModel)
}
