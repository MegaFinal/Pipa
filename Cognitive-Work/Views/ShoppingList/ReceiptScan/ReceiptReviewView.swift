//
//  ReceiptReviewView.swift
//  Cognitive-Work
//
//  Created by anshu Li on 04/11/26.
//

import SwiftUI

/// The products read from a scanned receipt, for the person to check before anything reaches
/// the shopping list: whether their sum matches the receipt, the lines worth a look (orange),
/// the item numbers that weren't read, and where each line goes (a list item to check off, a
/// new item, or nowhere). Names and prices can be fixed and a line read by mistake swiped
/// away. "Confirmar" saves it all at once.
struct ReceiptReviewView: View {

    /// The scanned pages.
    let pages: [UIImage]
    /// The shopping list the receipt is linked to.
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
                    .voiceOverLabel(L10n.tr("Fechar"))
                    .voiceControlNames([L10n.tr("Fechar"), L10n.tr("Cancelar")])
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: onScanAgain) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.phase == .reading || viewModel.isApplying)
                    .voiceOverLabel(L10n.tr("Escanear de novo"))
                    .voiceControlNames([L10n.tr("Escanear de novo"), L10n.tr("Escanear")])
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
            await viewModel.read(pages, linking: shopList.receiptLinkableItems)
            switch viewModel.phase {
            case .review: VoiceOver.announce(L10n.tr("\(viewModel.lines.count) itens"))
            case .empty: VoiceOver.announce(L10n.tr("Nenhum item encontrado"))
            case .reading: break
            }
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
                .accessibilityAddTraits(.isHeader)
            Text("Não encontramos itens nesta foto. Tente fotografar a nota de novo, reta e bem iluminada.")
                .font(.system(size: 15))
                .foregroundStyle(.subTitleGray)
                .multilineTextAlignment(.center)
            scanAgainButton
        }
        .padding(32)
    }

    private var scanAgainButton: some View {
        Button(action: onScanAgain) {
            Label("Escanear de novo", systemImage: "doc.text.viewfinder")
                .font(.system(size: 16, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
        }
        .buttonStyle(.glassProminent)
        .tint(.blue)
    }

    // MARK: - Review

    private var review: some View {
        List {
            Section {
                summary
                if viewModel.looksHardToRead {
                    hardToReadNotice
                }
            }

            Section {
                listLinking
            } header: {
                Text("Lista de compras")
            }

            Section {
                ForEach(viewModel.lines) { line in
                    row(for: line)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                withAnimation(.snappy) { viewModel.remove(line) }
                            } label: {
                                Label(L10n.tr("Remover"), systemImage: "trash")
                            }
                        }
                        .accessibilityAction(named: Text(verbatim: L10n.tr("Remover"))) {
                            withAnimation(.snappy) { viewModel.remove(line) }
                        }
                }
            } header: {
                Text(L10n.tr("\(viewModel.lines.count) itens"))
            } footer: {
                if !viewModel.missingItemNumbers.isEmpty {
                    let numbers = viewModel.missingItemNumbers.map { String(format: "%03d", $0) }.joined(separator: ", ")
                    Text(L10n.tr("Itens não lidos: \(numbers)"))
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { confirmBar }
    }

    /// The products' sum, the receipt's total and whether they match.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent(L10n.tr("Soma dos itens"), value: ReceiptScanViewModel.money(viewModel.sum))
                .font(.system(size: 16, weight: .semibold))

            switch viewModel.totalCheck {
            case .matches(let total):
                LabeledContent(L10n.tr("Total da nota"), value: ReceiptScanViewModel.money(total))
                Label(L10n.tr("Bate com o total da nota"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .differs(let total, let difference):
                LabeledContent(L10n.tr("Total da nota"), value: ReceiptScanViewModel.money(total))
                Label(L10n.tr("Diferença de \(ReceiptScanViewModel.money(difference)) para o total da nota"),
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            case .noPrintedTotal:
                Label(L10n.tr("Total da nota não encontrado"), systemImage: "questionmark.circle")
                    .foregroundStyle(.subTitleGray)
            }

            if viewModel.warningCount > 0 {
                Text(L10n.tr("\(viewModel.warningCount) itens para conferir"))
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
            }
        }
        .font(.system(size: 15))
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// Suggests scanning again when the receipt was hard to read.
    private var hardToReadNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Esta nota está difícil de ler. Confira os itens marcados ou escaneie de novo.")
                .font(.system(size: 14))
                .foregroundStyle(.titleGray)
            Button(action: onScanAgain) {
                Label("Escanear de novo", systemImage: "doc.text.viewfinder")
                    .font(.system(size: 15, weight: .semibold))
            }
        }
        .padding(.vertical, 4)
    }

    /// How many lines go to the list, the list items the receipt doesn't seem to have, and a
    /// shortcut to add every left-out line as a new item.
    @ViewBuilder
    private var listLinking: some View {
        Text(L10n.tr("\(viewModel.linkedCount) da lista, \(viewModel.newCount) novos"))
            .font(.system(size: 15, weight: .semibold))

        let unfound = viewModel.unfoundItems
        if !unfound.isEmpty {
            let names = ShopListViewModel.accessibilityList(unfound.map(\.name))
            Text(L10n.tr("Não encontrados na nota: \(names)"))
                .font(.system(size: 14))
                .foregroundStyle(.subTitleGray)
        }

        if viewModel.skippedCount > 0 {
            Button {
                HapticsManager.selection()
                withAnimation(.snappy) { viewModel.addSkippedAsNew() }
            } label: {
                Label(L10n.tr("Adicionar os outros \(viewModel.skippedCount) como novos"), systemImage: "plus.circle")
                    .font(.system(size: 15, weight: .semibold))
            }
        }
    }

    /// One product: its name and amount on the left, the price on the right, where it goes
    /// below, and the warning last in orange.
    private func row(for line: ReceiptScanLine) -> some View {
        let nameBinding = Binding(
            get: { viewModel.lines.first(where: { $0.id == line.id })?.name ?? "" },
            set: { newValue in
                if let index = viewModel.lines.firstIndex(where: { $0.id == line.id }) {
                    viewModel.lines[index].name = newValue
                }
            }
        )
        let priceBinding = Binding(
            get: { viewModel.priceTexts[line.id] ?? "" },
            set: { viewModel.updatePrice($0, for: line) }
        )
        let amount = ReceiptScanViewModel.amountText(for: line)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Nome do item", text: nameBinding, axis: .vertical)
                        .font(.system(size: 15, weight: .semibold))
                        .voiceOverLabel(L10n.tr("Nome do item"))
                    if !amount.isEmpty {
                        Text(amount)
                            .font(.system(size: 13))
                            .foregroundStyle(.subTitleGray)
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 2) {
                    Text("R$")
                        .foregroundStyle(.subTitleGray)
                        .accessibilityHidden(true)
                    TextField("0,00", text: priceBinding)
                        .priceInput(text: priceBinding)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .voiceOverLabel(L10n.tr("Valor total"))
                        .voiceOverValue(ShopListViewModel.accessibilityPrice(priceBinding.wrappedValue))
                }
                .font(.system(size: 15).monospacedDigit())
            }

            targetMenu(for: line)

            if let warning = line.warning {
                Label(ReceiptScanViewModel.warningText(warning), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Where a line goes

    /// A chip with where the line goes; tapping it lists the list items, "new item" and "leave
    /// out".
    private func targetMenu(for line: ReceiptScanLine) -> some View {
        let target = viewModel.targets[line.id] ?? .skip

        return Menu {
            if !viewModel.linkableItems.isEmpty {
                Section(L10n.tr("Itens da lista")) {
                    ForEach(viewModel.linkableItems, id: \.id) { item in
                        Button {
                            HapticsManager.selection()
                            viewModel.setTarget(.item(item.id), for: line)
                        } label: {
                            if target == .item(item.id) {
                                Label(menuName(for: item), systemImage: "checkmark")
                            } else {
                                Text(menuName(for: item))
                            }
                        }
                    }
                }
            }
            Button {
                HapticsManager.selection()
                viewModel.setTarget(.newItem, for: line)
            } label: {
                Label("Adicionar como novo item", systemImage: "plus.circle")
            }
            Button {
                HapticsManager.selection()
                viewModel.setTarget(.skip, for: line)
            } label: {
                Label("Não adicionar", systemImage: "minus.circle")
            }
        } label: {
            let style = chip(for: target, line: line)
            HStack(spacing: 5) {
                Image(systemName: style.icon)
                Text(style.title)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(style.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(style.color.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.borderless)
        .voiceOverLabel(L10n.tr("Na lista"))
        .voiceOverValue(chip(for: target, line: line).title)
    }

    /// The chip's icon, text and color for a target.
    private func chip(for target: ReceiptScanViewModel.Target, line: ReceiptScanLine) -> (icon: String, title: String, color: Color) {
        switch target {
        case .item(let id):
            return ("checkmark.circle.fill", viewModel.item(withID: id)?.name ?? "", .green)
        case .newItem:
            return ("plus.circle.fill", L10n.tr("Novo item"), .blue)
        case .skip:
            return ("minus.circle", L10n.tr("Não adicionar"), .gray)
        }
    }

    /// A list item's name in the menu; a bought one without a price says so.
    private func menuName(for item: ShopListItem) -> String {
        item.isBought ? L10n.tr("\(item.name) (comprado sem preço)") : item.name
    }

    // MARK: - Confirming

    /// "Confirmar", pinned under the list.
    private var confirmBar: some View {
        Button {
            Task { await confirm() }
        } label: {
            Group {
                if viewModel.isApplying {
                    ProgressView()
                } else {
                    Text("Confirmar")
                }
            }
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        .tint(.blue)
        .disabled(!viewModel.canConfirm)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .voiceOverValue(L10n.tr("\(viewModel.linkedCount) da lista, \(viewModel.newCount) novos"))
    }

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
