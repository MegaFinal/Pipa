//
//  OnboardingNewChoreSheet.swift
//  Cognitive-Work
//

import SwiftUI
import CloudKit

/// Sheet for creating a chore that isn't in the default list, during onboarding.
///
/// Presented from ``SelectChoresOnboardingView``. Nothing is saved here: the new chore comes
/// back through `onCreate` already marked, and is persisted with the selected default chores
/// by ``OnboardingViewModel/createDefaultChores()`` when the step is confirmed.
struct OnboardingNewChoreSheet: View {
    /// Closes the sheet.
    @Environment(\.dismiss) private var dismiss
    
    /// Rooms the chore can belong to.
    let rooms: [RoomModel]
    
    /// Called with the new chore (already linked to its room) when the user confirms.
    let onCreate: (ChoreDTO, RoomModel) -> Void
    
    /// The chore being filled in.
    @State private var draft = ChoreDTO()
    /// The room picked for the chore.
    @State private var selectedRoomID: RoomModel.ID?
    /// Focus of the name field.
    @FocusState private var isNameFocused: Bool
    
    /// - Parameters:
    ///   - rooms: Rooms the chore can belong to.
    ///   - initialRoom: Room picked when the sheet opens (the one being browsed).
    ///   - onCreate: Receives the new chore and its room.
    init(rooms: [RoomModel], initialRoom: RoomModel?, onCreate: @escaping (ChoreDTO, RoomModel) -> Void) {
        self.rooms = rooms
        self.onCreate = onCreate
        _selectedRoomID = State(initialValue: initialRoom?.id ?? rooms.first?.id)
    }
    
    /// The room picked, or `nil`.
    private var selectedRoom: RoomModel? {
        rooms.first { $0.id == selectedRoomID }
    }
    
    /// The name without spaces at the ends.
    private var trimmedName: String {
        draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Whether the chore can be created (it has a name and a room).
    private var canCreate: Bool {
        !trimmedName.isEmpty && selectedRoom != nil
    }
    
    
    /// The selected room's color drives the whole sheet, like the room cards do elsewhere.
    private var accent: RoomColor {
        selectedRoom?.color ?? .orange
    }
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    // MARK: - Title, room card, attributes and description
                    titleBlock
                    heroCard
                    attributesCard
                    descriptionCard
                }
                .padding(.horizontal, 22)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            // MARK: - "Criar tarefa" button pinned to the bottom
            .safeAreaInset(edge: .bottom) { createButton }
            // MARK: - Close button
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .tint(.black)
                    .accessibilityLabel(Text(L10n.tr("Fechar")))
                    .voiceControlNames([L10n.tr("Fechar"), L10n.tr("Cancelar")])
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .dismissKeyboardOnTap()
        }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .animation(.snappy(duration: 0.3), value: selectedRoomID)
    }
    
    // MARK: - Subviews
    
    /// The "Nova tarefa" title and its subtitle.
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nova tarefa")
                .bold()
                .font(.system(size: 32))
                .foregroundStyle(.titleGray)
                .accessibilityAddTraits(.isHeader)
            
            Text("Ela já entra marcada e vai para a escala de **todos**.")
                .font(.system(size: 16))
                .foregroundStyle(.subTitleGray)
        }
    }
    
    /// Room card in the same look as the rest of the app: the room's color and texture, its
    /// icon, and the chore's name written straight on it.
    private var heroCard: some View {
        VStack(spacing: 18) {
            SymbolImage(name: selectedRoom?.symbol ?? "house")
                .frame(width: 88, height: 88)
                .accessibilityHidden(true)
            
            VStack(spacing: 6) {
                TextField(
                    "",
                    text: $draft.name,
                    prompt: Text("Nome da tarefa").foregroundStyle(.white.opacity(0.7))
                )
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
                .tint(.white)
                .focused($isNameFocused)
                .characterLimit(TextLimits.choreName, text: $draft.name)
                .submitLabel(.done)
                .accessibilityLabel(Text(L10n.tr("Nome da tarefa")))
                .voiceControlNames([L10n.tr("Nome da tarefa"), L10n.tr("Nome")])
                
                Capsule()
                    .fill(.white.opacity(0.55))
                    .frame(height: 2)
                    .padding(.horizontal, 24)
                    .accessibilityDecorative()
            }
            
            roomMenu
        }
        .foregroundStyle(.white)
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background {
            if let selectedRoom {
                RoomTextureBackground(room: selectedRoom)
            } else {
                Color.gray
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
    }
    
    /// The menu to pick the chore's room.
    private var roomMenu: some View {
        Menu {
            Picker("Cômodo", selection: $selectedRoomID) {
                ForEach(rooms) { room in
                    Text(room.name.localizedDefault)
                        .tag(RoomModel.ID?(room.id))
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selectedRoom?.name.localizedDefault ?? L10n.tr("Sem Cômodo"))
                    .font(.system(size: 15, weight: .semibold))
                
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.white.opacity(0.22), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.45), lineWidth: 1))
        }
        .accessibilityLabel(Text(L10n.tr("Cômodo")))
        .accessibilityValue(Text(selectedRoom?.name.localizedDefault ?? L10n.tr("Sem Cômodo")))
        // Voice Control: the visible room name first, then the field's own name.
        .voiceControlNames([selectedRoom?.name.localizedDefault ?? L10n.tr("Sem Cômodo"), L10n.tr("Cômodo")])
    }
    
    /// Priority, duration and frequency, one rounded row each, tinted with the room's color.
    private var attributesCard: some View {
        VStack(spacing: 0) {
            attributeRow(icon: "flag.fill", title: "Prioridade") {
                ChoreTagPicker(chore: $draft, type: .priority)
            }
            
            Divider().padding(.leading, 62)
            
            attributeRow(icon: "clock.fill", title: "Duração") {
                ChoreTagPicker(chore: $draft, type: .duration)
            }
            
            Divider().padding(.leading, 62)
            
            attributeRow(icon: "arrow.triangle.2.circlepath", title: "Frequência") {
                ChoreTagPicker(chore: $draft, type: .frequency)
            }
        }
        .padding(.horizontal, 16)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    
    /// One attribute row: a tinted icon, a title and the picker.
    private func attributeRow<Control: View>(
        icon: String,
        title: LocalizedStringKey,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent.uiColor)
                .frame(width: 34, height: 34)
                .background(accent.lowOpacityColor.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityDecorative()
            
            Text(title)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.black)
            
            Spacer(minLength: 8)
            
            control()
        }
        .padding(.vertical, 12)
    }
    
    /// The optional description field.
    private var descriptionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Descrição")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.black)
            } icon: {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent.uiColor)
            }
            
            TextField("Como essa tarefa deve ser feita? (opcional)", text: $draft.description, axis: .vertical)
                .font(.system(size: 16))
                .foregroundStyle(.black.opacity(0.7))
                .lineLimit(3...6)
                .characterLimit(TextLimits.choreDescription, text: $draft.description)
                .accessibilityLabel(Text(L10n.tr("Descrição")))
                .voiceControlNames([L10n.tr("Descrição")])
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    
    /// The "Criar tarefa" button (disabled until there's a name).
    private var createButton: some View {
        Button {
            create()
        } label: {
            HStack(spacing: 8) {
                Text("Criar tarefa")
                    .font(.system(size: 18, weight: .bold))
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(canCreate ? accent.uiColor : Color(.systemGray3), in: Capsule())
            .shadow(color: canCreate ? accent.uiColor.opacity(0.35) : .clear, radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .disabled(!canCreate)
        .accessibilityLabel(Text(L10n.tr("Criar tarefa")))
        .voiceControlNames([L10n.tr("Criar tarefa"), L10n.tr("Criar"), L10n.tr("Confirmar")])
        .voiceOverHint(canCreate ? "" : L10n.tr("Dê um nome à tarefa para poder criá-la"))
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
    }
    
    // MARK: - Actions
    
    /// Fills in the chore's room and icon, sends it back through `onCreate` and closes the sheet.
    private func create() {
        guard canCreate, let room = selectedRoom else { return }
        
        draft.name = trimmedName
        draft.description = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        // `room` also sets `roomReference`, which `createDefaultChores()` uses to place it.
        draft.room = room
        draft.roomDTO = RoomDTO(name: room.kind ?? room.name, symbol: room.symbol, color: room.color)
        draft.symbolName = room.symbol
        draft.isSelected = true
        
        HapticsManager.notify(.success)
        onCreate(draft, room)
        dismiss()
    }
}
