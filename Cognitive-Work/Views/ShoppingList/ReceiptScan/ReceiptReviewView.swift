//
//  ReceiptReviewView.swift
//  Cognitive-Work
//
//  Created by anshu Li on 04/11/26.
//

import Foundation
import SwiftUI

/// The products read from a scanned receipt, reviewed before anything reaches the shopping
/// list. Laid out like the review step of ``AddMoreItensInteligence``: one white card per
/// product with a checkbox in front (ticked ones go to the list), and the blue checkmark at the
/// top right to confirm. Products whose name matches a list item come first and check that
/// item off; below a line, the ones bought outside the list, added already bought for who the
/// person picks (the whole house by default) in the aisle guessed for them. On top, whether
/// their sum matches the receipt.
struct ReceiptReviewView: View {

    /// The scanned pages.
    let pages: [UIImage]
    /// The shopping list the receipt goes to.
    let shopList: ShopListViewModel
    /// Closes this sheet and opens the scanner (or the photo picker) again.
    let onScanAgain: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ReceiptScanViewModel()

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .reading:
                    reading
                case .empty:
                    empty
                case .review:
                    review
                        // Saving: what's on screen is what gets saved, so nothing changes now.
                        .disabled(viewModel.isApplying)
                        .opacity(viewModel.isApplying ? 0.5 : 1)
                        .animation(.easeInOut(duration: 0.2), value: viewModel.isApplying)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGray6).ignoresSafeArea())
            .navigationTitle("Nota escaneada")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .disabled(viewModel.isApplying)
                    .voiceOverLabel(L10n.tr("Cancelar"))
                    .voiceControlNames([L10n.tr("Fechar"), L10n.tr("Cancelar")])
                }

                if viewModel.phase == .review {
                    // Like confirming the AI items: the blue checkmark at the top right.
                    ToolbarItem(placement: .confirmationAction) {
                        if viewModel.isApplying {
                            ProgressView()
                        } else {
                            Button {
                                Task { await confirm() }
                            } label: {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12))
                                    .bold()
                                    .foregroundColor(.white)
                            }
                            .tint(.blue)
                            .buttonStyle(.glassProminent)
                            .disabled(!viewModel.canConfirm)
                            .voiceOverLabel(L10n.tr("Adicionar itens (\(viewModel.included.count))"))
                            .voiceControlNames([L10n.tr("Adicionar"), L10n.tr("Confirmar"), L10n.tr("OK")])
                        }
                    }
                }

                // Closes the number pad of the price fields.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") { hideKeyboard() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGray6))
        .interactiveDismissDisabled(viewModel.isApplying)
        .task {
            await viewModel.read(
                pages,
                linking: shopList.receiptLinkableItems,
                houseUsers: shopList.houseUsers,
                memory: shopList.receiptNameMemory,
                knownCategory: { [shopList] name in shopList.receiptCategory(named: name) }
            )
            switch viewModel.phase {
            case .review: VoiceOver.announce(L10n.tr("\(viewModel.lines.count) itens"))
            case .empty: VoiceOver.announce(L10n.tr("Nenhum item encontrado"))
            case .reading: break
            }
            // While the person reviews: aisles nothing else could tell.
            await viewModel.guessCategoriesWithAI()
        }
    }

    // MARK: - Reading and empty

    private var reading: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Lendo a nota…")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.titleGray)
        }
    }

    private var empty: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.subTitleGray)
                .accessibilityHidden(true)
            Text("Nenhum item encontrado")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.titleGray)
                .accessibilityAddTraits(.isHeader)
            Text("Não encontramos itens nesta foto. Tente fotografar a nota de novo, reta e bem iluminada.")
                .font(.system(size: 15))
                .foregroundStyle(.subTitleGray)
                .multilineTextAlignment(.center)
            scanAgainButton
            addLineButton
        }
        .padding(32)
    }

    /// Back to the camera (or the photos), like "Editar texto" on the AI items.
    private var scanAgainButton: some View {
        Button(action: onScanAgain) {
            Label("Escanear de novo", systemImage: "doc.text.viewfinder")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.titleGray)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isApplying)
    }

    // MARK: - Review

    private var review: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Revise os itens antes de adicionar.")
                    .font(.system(size: 15))
                    .foregroundStyle(.subTitleGray)

                summary
                    .padding(.bottom, 4)

                let listLines = viewModel.listLines
                let otherLines = viewModel.otherLines

                if !listLines.isEmpty {
                    sectionTitle(L10n.tr("Da sua lista"))
                    ForEach(listLines) { line in
                        row(for: line)
                    }
                }

                if !otherLines.isEmpty {
                    if !listLines.isEmpty {
                        // The same black line that separates "Comprados" on the list.
                        Capsule()
                            .fill(Color.black)
                            .frame(height: 1.5)
                            .padding(.vertical, 12)
                            .accessibilityHidden(true)
                    }
                    HStack {
                        sectionTitle(L10n.tr("Fora da lista"))
                        Spacer()
                        otherLinesConsumersMenu
                    }
                    ForEach(otherLines) { line in
                        row(for: line)
                    }
                }

                if !viewModel.missingItemNumbers.isEmpty {
                    let numbers = viewModel.missingItemNumbers.map { String(format: "%03d", $0) }.joined(separator: ", ")
                    Text(L10n.tr("Itens não lidos: \(numbers)"))
                        .font(.system(size: 13))
                        .foregroundStyle(.subTitleGray)
                        .padding(.horizontal, 6)
                }

                addLineButton
                    .frame(maxWidth: .infinity)

                scanAgainButton
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
            .padding(22)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// The products' sum against the receipt's total, in a white card.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Soma dos itens")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.titleGray)
                Spacer()
                Text(ReceiptScanViewModel.money(viewModel.sum))
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.titleGray)
            }

            Group {
                switch viewModel.totalCheck {
                case .matches:
                    Label(L10n.tr("Bate com o total da nota"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .differs(let total, let difference):
                    Label {
                        Text(verbatim: "\(L10n.tr("Total da nota")) \(ReceiptScanViewModel.money(total)) · "
                             + L10n.tr("Diferença de \(ReceiptScanViewModel.money(difference)) para o total da nota"))
                    } icon: {
                        Image(systemName: "exclamationmark.circle.fill")
                    }
                    .foregroundStyle(.orange)
                case .noPrintedTotal:
                    Label(L10n.tr("Total da nota não encontrado"), systemImage: "questionmark.circle")
                        .foregroundStyle(.subTitleGray)
                }
            }
            .font(.system(size: 13))

            // The same part of the receipt photographed twice: said, so the count makes sense.
            if viewModel.repeatedPages > 0 {
                Label(L10n.tr("Fotos repetidas ignoradas: \(viewModel.repeatedPages)"), systemImage: "photo.on.rectangle")
                    .font(.system(size: 13))
                    .foregroundStyle(.subTitleGray)
            }

            // The parser's sum didn't match, so the photo was read by the model instead.
            if viewModel.readFromPhoto {
                Label(L10n.tr("Lido pela foto com Apple Intelligence"), systemImage: "sparkles")
                    .font(.system(size: 13))
                    .foregroundStyle(.subTitleGray)
            }

            if viewModel.looksHardToRead {
                Text("Esta nota está difícil de ler. Confira os itens marcados ou escaneie de novo.")
                    .font(.system(size: 13))
                    .foregroundStyle(.subTitleGray)
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// One product: the checkbox in front, then its name, amount and price, where it goes in
    /// the list, and a warning in orange when the reading needs a look.
    private func row(for line: ReceiptScanLine) -> some View {
        let isIncluded = viewModel.isIncluded(line)
        let nameBinding = Binding(
            get: { viewModel.lines.first(where: { $0.id == line.id })?.name ?? "" },
            set: { viewModel.rename(line, to: $0) }
        )
        let priceBinding = Binding(
            get: { viewModel.priceTexts[line.id] ?? "" },
            set: { viewModel.updatePrice($0, for: line) }
        )
        let amount = ReceiptScanViewModel.amountText(for: line)

        return HStack(alignment: .top, spacing: 6) {
            Button {
                HapticsManager.selection()
                withAnimation(.snappy) { viewModel.toggle(line) }
            } label: {
                Image(systemName: isIncluded ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(isIncluded ? Color.blue : Color.gray.opacity(0.5))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .voiceOverLabel(L10n.tr("Incluir \(line.name)"))
            .voiceOverTraits(.isSelected, when: isIncluded)
            .voiceControlNames([L10n.tr("Incluir \(line.name)")])

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    TextField("Nome do item", text: nameBinding, axis: .vertical)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.titleGray)
                        .voiceOverLabel(L10n.tr("Nome do item"))

                    HStack(spacing: 2) {
                        Text("R$")
                            .foregroundStyle(.subTitleGray)
                            .accessibilityHidden(true)
                        TextField("0,00", text: priceBinding)
                            .priceInput(text: priceBinding)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 72)
                            .voiceOverLabel(L10n.tr("Valor total"))
                            .voiceOverValue(ShopListViewModel.accessibilityPrice(priceBinding.wrappedValue))
                    }
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.titleGray)
                }

                // Weighed: the weight read. Units: changeable.
                if line.weightKg > 0 {
                    infoLine("dumbbell.fill", amount)
                } else {
                    quantityControl(for: line)
                }

                if isIncluded {
                    destination(for: line)
                    // A new item goes in the aisle guessed for it; the person can change it.
                    if viewModel.linkedItem(for: line) == nil {
                        categoryMenu(for: line)
                    }
                    // A weighed product changes the list's quantity to the weight bought: said
                    // here, before confirming.
                    if let change = viewModel.quantityChange(for: line) {
                        Label(L10n.tr("Quantidade na lista: \(change.from) → \(change.to)"),
                              systemImage: line.weightKg > 0 ? "scalemass.fill" : "number.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.blue)
                    }
                    // A list item starts with its own people; any line can change them.
                    consumersMenu(for: line)
                }

                if let warning = line.warning {
                    Label(ReceiptScanViewModel.warningText(warning), systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.top, 10)
        }
        .padding(.vertical, 6)
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .opacity(isIncluded ? 1 : 0.5)
    }

    /// Where a ticked product goes: the list item it checks off ("Já está na lista: banana"),
    /// or a new item. The menu changes it, as plain options in a picker like the repeated-item
    /// choice on the AI items.
    private func destination(for line: ReceiptScanLine) -> some View {
        let linked = viewModel.linkedItem(for: line)
        let title = linked.map { L10n.tr("Já está na lista: \($0.name)") } ?? L10n.tr("Novo item")

        return Menu {
            Picker(selection: Binding(
                get: { viewModel.links[line.id] },
                set: { newValue in
                    HapticsManager.selection()
                    // The card moves between "Da sua lista" and "Fora da lista".
                    withAnimation(.snappy) { viewModel.link(line, to: newValue) }
                }
            )) {
                Text(L10n.tr("Novo item")).tag(String?.none)
                ForEach(viewModel.linkableItems, id: \.id) { item in
                    Text(item.name)
                        .tag(String?.some(item.id))
                }
            } label: {
                EmptyView()
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: linked == nil ? "plus.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .frame(width: 16)
                Text(title)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(linked == nil ? Color.subTitleGray : Color.green)
        }
        .buttonStyle(.plain)
        .voiceOverLabel(L10n.tr("Na lista"))
        .voiceOverValue(title)
    }

    /// The aisle a product bought outside the list goes in, changeable like its destination.
    /// One the model chose has the sparkles, so the person gives it a look.
    private func categoryMenu(for line: ReceiptScanLine) -> some View {
        let category = viewModel.category(for: line)
        let isFromAI = viewModel.aiCategories.contains(line.id)

        return Menu {
            Picker(selection: Binding(
                get: { viewModel.category(for: line) },
                set: { newValue in
                    HapticsManager.selection()
                    viewModel.setCategory(newValue, for: line)
                }
            )) {
                ForEach(ShopItemCategory.listOrder) { category in
                    Text(category.displayName).tag(category)
                }
            } label: {
                EmptyView()
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: isFromAI ? "sparkles" : "square.grid.2x2.fill")
                    .font(.system(size: 11))
                    .frame(width: 16)
                Text(category.displayName)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.subTitleGray)
        }
        .buttonStyle(.plain)
        .voiceOverLabel(L10n.tr("Categoria"))
        .voiceOverValue(category.displayName)
    }

    // MARK: - Who it's for

    /// "Da sua lista", "Fora da lista".
    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(.titleGray)
            .padding(.horizontal, 6)
            .accessibilityAddTraits(.isHeader)
    }

    /// Who a product bought outside the list is for: "Todos", or the names. The menu ticks
    /// people in and out and stays open, so several can be changed at once.
    private func consumersMenu(for line: ReceiptScanLine) -> some View {
        let text = peopleText(for: line)

        return Menu {
            Button {
                HapticsManager.selection()
                viewModel.setConsumers(nil, for: line)
            } label: {
                if viewModel.isForEveryone(line) {
                    Label(L10n.tr("Todos"), systemImage: "checkmark")
                } else {
                    Text(L10n.tr("Todos"))
                }
            }
            Divider()
            ForEach(viewModel.houseUsers) { user in
                let isChosen = viewModel.consumers(for: line).contains { $0.id == user.id }
                Button {
                    HapticsManager.selection()
                    viewModel.toggleConsumer(user, for: line)
                } label: {
                    if isChosen {
                        Label(user.name, systemImage: "checkmark")
                    } else {
                        Text(user.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 11))
                    .frame(width: 16)
                Text(text)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.subTitleGray)
        }
        .menuActionDismissBehavior(.disabled)
        .buttonStyle(.plain)
        .voiceOverLabel(L10n.tr("Responsável"))
        .voiceOverValue(text)
    }

    /// Sets who every product outside the list is for at once: the whole house, or one person.
    private var otherLinesConsumersMenu: some View {
        Menu {
            Button(L10n.tr("Todos")) {
                HapticsManager.selection()
                viewModel.setConsumersForOtherLines(nil)
            }
            Divider()
            ForEach(viewModel.houseUsers) { user in
                Button(user.name) {
                    HapticsManager.selection()
                    viewModel.setConsumersForOtherLines([user])
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "person.2.fill")
                Text(L10n.tr("Responsável"))
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.titleGray)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.white, in: Capsule())
        }
        .buttonStyle(.plain)
        .voiceOverLabel(L10n.tr("Responsável"))
        .voiceOverHint(L10n.tr("Escolha para quem são todos os itens fora da lista."))
    }

    /// "Todos", or "Ana, Bruno".
    private func peopleText(for line: ReceiptScanLine) -> String {
        viewModel.isForEveryone(line)
            ? L10n.tr("Todos")
            : ShopListViewModel.accessibilityList(viewModel.consumers(for: line).map(\.name))
    }

    // MARK: - Quantity and added lines

    /// "− 2 unidades +": the units of a line, changeable in place (the price follows). Lined up
    /// with the other info lines' text.
    private func quantityControl(for line: ReceiptScanLine) -> some View {
        let quantity = line.quantity
        let text = ShopListViewModel.accessibilityQuantity(quantity, unit: .unit)

        return HStack(spacing: 6) {
            Button {
                HapticsManager.selection()
                viewModel.setQuantity(quantity - 1, for: line)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 20))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .disabled(quantity <= QuantityStepper.allowedRange.lowerBound)
            .accessibilityHidden(true)
            Text(text)
                .monospacedDigit()
            Button {
                HapticsManager.selection()
                viewModel.setQuantity(quantity + 1, for: line)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .disabled(quantity >= QuantityStepper.allowedRange.upperBound)
            .accessibilityHidden(true)
        }
        .buttonStyle(.borderless)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.subTitleGray)
        .accessibilityElement(children: .ignore)
        .voiceOverLabel(L10n.tr("Quantidade"))
        .voiceOverValue(text)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: viewModel.setQuantity(quantity + 1, for: line)
            case .decrement: viewModel.setQuantity(quantity - 1, for: line)
            @unknown default: break
            }
        }
    }

    /// "+ Adicionar item": an empty line for a product the reader missed.
    private var addLineButton: some View {
        Button {
            HapticsManager.selection()
            withAnimation(.snappy) { viewModel.addLine() }
        } label: {
            Label("Adicionar item", systemImage: "plus.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.blue)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isApplying)
        .voiceControlNames([L10n.tr("Adicionar item"), L10n.tr("Adicionar")])
    }

    /// A small grey line with its icon in front, like on the AI items.
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

    // MARK: - Confirming

    /// Saves into the list and closes. It closes on a failure too (the list shows the error),
    /// since part of it may already be saved and confirming again would repeat it.
    private func confirm() async {
        hideKeyboard()
        let didSaveAll = await viewModel.confirm(into: shopList)
        if didSaveAll {
            HapticsManager.notify(.success)
            VoiceOver.announce(L10n.tr("Lista atualizada"))
        } else {
            HapticsManager.notify(.error)
        }
        dismiss()
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
