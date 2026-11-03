//
//  CheckListCreateAndEdit.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 30/08/26.
//

import SwiftUI

/// The chore's checklist inside the form: one row per subtask (check circle and text), separated
/// by lines, and "Adicionar subtarefa" at the end. There's always at least one row to type into.
struct CheckListCreateAndEdit: View {
    
    /// The subtasks being edited. Blank rows are dropped when the chore is saved.
    @Binding var localChecklist: [CheckItemDTO]
    
    /// The row whose text field currently has the keyboard.
    @FocusState private var focusedItemID: UUID?
    
    /// Indent of the separators and of "Adicionar subtarefa", so they line up with the text.
    private let textIndent: CGFloat = 34
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - One row per subtask
            ForEach($localChecklist) { $item in
                row(for: $item)
                
                Divider()
                    .padding(.leading, textIndent)
            }
            
            // MARK: - "Adicionar subtarefa"
            Button {
                appendItem()
            } label: {
                Text("Adicionar subtarefa")
                    .foregroundStyle(.blue)
            }
            .padding(.leading, textIndent)
            .padding(.vertical, 12)
            .voiceControlNames([L10n.tr("Adicionar subtarefa"), L10n.tr("Adicionar"), L10n.tr("Mais")])
        }
    }
    
    /// Check circle, text field and, when there's more than one row, a remove button.
    private func row(for item: Binding<CheckItemDTO>) -> some View {
        HStack(spacing: 12) {
            Button {
                item.wrappedValue.isDone.toggle()
                HapticsManager.selection()
            } label: {
                Image(systemName: item.wrappedValue.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(item.wrappedValue.isDone ? Color.primary : Color.secondary)
            }
            .buttonStyle(.plain)
            .voiceOverLabel(accessibilityName(of: item.wrappedValue))
            .voiceOverValue(item.wrappedValue.isDone ? L10n.tr("Concluído") : L10n.tr("Pendente"))
            .voiceOverHint(L10n.tr("Toque duas vezes para alternar."))
            
            TextField("Descrição da subtarefa", text: item.name)
                .strikethrough(item.wrappedValue.isDone, color: .gray)
                .foregroundStyle(item.wrappedValue.isDone ? Color.secondary : Color.primary)
                .characterLimit(TextLimits.checklistItem, text: item.name)
                .focused($focusedItemID, equals: item.wrappedValue.id)
                .submitLabel(.next)
                .onSubmit { insertItem(after: item.wrappedValue.id) }
                .voiceControlNames([accessibilityName(of: item.wrappedValue), L10n.tr("Item")])
            
            if localChecklist.count > 1 {
                Button {
                    remove(item.wrappedValue.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .voiceOverLabel(L10n.tr("Remover \(accessibilityName(of: item.wrappedValue))"))
            }
        }
        .padding(.vertical, 12)
    }
    
    /// The item's text, or "Nova subtarefa" while it's still blank.
    private func accessibilityName(of item: CheckItemDTO) -> String {
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? L10n.tr("Nova subtarefa") : name
    }
    
    // MARK: - Actions
    
    /// Creates an empty row right after `id` and focuses it (keyboard return).
    private func insertItem(after id: UUID) {
        guard let index = localChecklist.firstIndex(where: { $0.id == id }) else { return }
        
        // Return on a blank row ends the list instead of creating another blank row.
        guard !localChecklist[index].name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            focusedItemID = nil
            return
        }
        
        let newItem = CheckItemDTO(name: "", isDone: false)
        localChecklist.insert(newItem, at: index + 1)
        focusedItemID = newItem.id
    }
    
    /// "Adicionar subtarefa": reuses a trailing blank row if there is one, otherwise appends.
    private func appendItem() {
        if let last = localChecklist.last,
           last.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            focusedItemID = last.id
            return
        }
        let newItem = CheckItemDTO(name: "", isDone: false)
        localChecklist.append(newItem)
        focusedItemID = newItem.id
    }
    
    /// Removes the item `id`, always leaving one row to type into.
    private func remove(_ id: UUID) {
        if let item = localChecklist.first(where: { $0.id == id }) {
            VoiceOver.announce(L10n.tr("\(accessibilityName(of: item)) removido"))
        }
        localChecklist.removeAll { $0.id == id }
        if localChecklist.isEmpty {
            localChecklist.append(CheckItemDTO(name: "", isDone: false))
        }
    }
}
