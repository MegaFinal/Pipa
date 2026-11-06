//
//  ReceiptLineFormView.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 06/11/26.
//

import SwiftUI

/// Edits one product of a scanned receipt, laid out like the item form
/// (``ShopListItemFormView``): the name beside the aisle's icon, then the list item it checks
/// off, the aisle, the quantity, the price and who it's for. Works on a copy
/// (``ReceiptLineDraft``): the review only changes on the checkmark.
struct ReceiptLineFormView: View {

    /// The review the product belongs to.
    let viewModel: ReceiptScanViewModel

    @Environment(\.dismiss) private var dismiss
    /// The copy being edited.
    @State private var draft: ReceiptLineDraft
    /// Whether the checkmark closed the form (otherwise a new product is dropped).
    @State private var didConfirm = false
    @FocusState private var isNameFocused: Bool

    init(draft: ReceiptLineDraft, viewModel: ReceiptScanViewModel) {
        self.viewModel = viewModel
        self._draft = State(initialValue: draft)
    }

    /// The list item the product checks off, if any.
    private var linkedItem: ShopListItem? {
        viewModel.linkedItem(for: draft)
    }

    /// The aisle shown: the list item's, or the product's own.
    private var category: ShopItemCategory {
        linkedItem?.category ?? draft.category
    }

    /// Why the checkmark is off, once there is a name.
    private var warning: String? {
        viewModel.missingFieldText(in: draft)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    header

                    if let warning, !draft.trimmedName.isEmpty {
                        Text(warning)
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    listItemCard

                    if linkedItem == nil {
                        categoryCard
                    }

                    section("Quantidade") {
                        quantityCard
                    }

                    section("Valor") {
                        priceField
                        // What the reader flagged, until the person checks it.
                        if let readingWarning = draft.warning {
                            Text(ReceiptScanViewModel.warningText(readingWarning))
                                .font(.system(size: 13))
                                .foregroundStyle(.orange)
                        }
                    }

                    section("Responsável") {
                        VStack(alignment: .leading, spacing: 10) {
                            ResponsibleUserPicker(
                                availableUsers: viewModel.houseUsers,
                                selectedUsers: Binding(
                                    get: { draft.consumers },
                                    set: { viewModel.setConsumers($0, in: &draft) }
                                )
                            )
                            if let shareText {
                                Text(shareText)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.subTitleGray)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGray6).ignoresSafeArea())
            .navigationTitle(draft.isNew ? "Novo item" : "Editar item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .voiceOverLabel(L10n.tr("Cancelar"))
                    .voiceControlNames([L10n.tr("Fechar"), L10n.tr("Cancelar")])
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(action: confirm) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12))
                            .bold()
                            .foregroundColor(.white)
                    }
                    .tint(.blue)
                    .buttonStyle(.glassProminent)
                    .disabled(warning != nil)
                    .voiceOverLabel(L10n.tr("Salvar"))
                    .voiceOverHint(warning ?? "")
                    .voiceControlNames([L10n.tr("Confirmar"), L10n.tr("Salvar"), L10n.tr("OK")])
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGray6))
        .dismissKeyboardOnTap()
        .task {
            // A product the person is adding starts at the name.
            if draft.isNew { isNameFocused = true }
        }
        .onDisappear {
            if !didConfirm { viewModel.discard(draft) }
        }
    }

    // MARK: - Header

    /// The aisle's icon beside the name, like the item form's header.
    private var header: some View {
        HStack(spacing: 18) {
            SymbolImage(name: category.symbol)
                .frame(width: 64, height: 64)
                .foregroundStyle(category.color)
                .padding(.leading, 6)
                .animation(.snappy, value: category)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                TextField(
                    "",
                    text: Binding(
                        get: { draft.name },
                        set: { viewModel.setName($0, in: &draft) }
                    ),
                    prompt: Text("Nome do item").foregroundStyle(.black),
                    axis: .vertical
                )
                .font(.system(size: 28))
                .bold()
                .lineLimit(1...3)
                .characterLimit(TextLimits.shopItemName, text: Binding(
                    get: { draft.name },
                    set: { viewModel.setName($0, in: &draft) }
                ))
                .submitLabel(.done)
                .focused($isNameFocused)
                .voiceOverLabel(L10n.tr("Nome do item"))
                .voiceControlNames([L10n.tr("Nome do item"), L10n.tr("Nome")])

                Capsule()
                    .frame(height: 1.5)
                    .foregroundStyle(.gray.opacity(0.5))
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: - Sections

    /// A titled block, like the item form's.
    private func section<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15))
                .fontWeight(.semibold)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    /// Which list item the product checks off, or "Novo item".
    private var listItemCard: some View {
        menuRow(
            title: L10n.tr("Na lista"),
            value: linkedItem?.name ?? L10n.tr("Novo item"),
            color: category.color
        ) {
            Picker("Na lista", selection: Binding(
                get: { draft.linkedItemID },
                set: { newValue in
                    HapticsManager.selection()
                    withAnimation(.snappy) { viewModel.setLink(newValue, in: &draft) }
                }
            )) {
                Text(L10n.tr("Novo item")).tag(String?.none)
                ForEach(viewModel.linkableItems, id: \.id) { item in
                    Text(item.name).tag(String?.some(item.id))
                }
            }
        }
    }

    /// The aisle of a new item, with the sparkles while it's Apple Intelligence's guess.
    private var categoryCard: some View {
        menuRow(
            title: L10n.tr("Categoria"),
            isSuggested: draft.isCategoryFromAI,
            value: draft.category.displayName,
            color: draft.category.color
        ) {
            Picker("Categoria", selection: Binding(
                get: { draft.category },
                set: { newValue in
                    HapticsManager.selection()
                    viewModel.setCategory(newValue, in: &draft)
                }
            )) {
                ForEach(ShopItemCategory.listOrder) { option in
                    Text(option.displayName).tag(option)
                }
            }
        }
    }

    /// The units (with the stepper), or the weight read from the receipt.
    private var quantityCard: some View {
        Group {
            if draft.isWeighed {
                HStack {
                    Image(systemName: "scalemass.fill")
                        .foregroundStyle(.subTitleGray)
                        .accessibilityHidden(true)
                    Text(ReceiptScanViewModel.weightText(draft.weightKg))
                        .font(.system(size: 17, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.titleGray)
                    Spacer()
                }
            } else {
                QuantityStepper(
                    value: Binding(
                        get: { draft.quantity },
                        set: { viewModel.setQuantity($0, in: &draft) }
                    ),
                    valueDescription: { ShopListViewModel.accessibilityQuantity($0, unit: .unit) }
                )
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// The total paid for the product.
    private var priceField: some View {
        let text = Binding(
            get: { draft.priceText },
            set: { viewModel.setPrice($0, in: &draft) }
        )
        return HStack(spacing: 4) {
            Text("R$")
                .foregroundStyle(.subTitleGray)
                .accessibilityHidden(true)
            TextField("0,00", text: text)
                .priceInput(text: text)
                .voiceOverLabel(L10n.tr("Valor total"))
                .voiceOverValue(ShopListViewModel.accessibilityPrice(draft.priceText))
                .voiceControlNames([L10n.tr("Valor total"), L10n.tr("Preço"), L10n.tr("Valor")])
        }
        .font(.system(size: 17).monospacedDigit())
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// "R$ 12,50 por pessoa".
    private var shareText: String? {
        ShopListViewModel.shareText(
            total: ShopListViewModel.parsePrice(draft.priceText),
            consumerCount: draft.consumers.count
        )
    }

    /// A white card with a title on the left and a menu with the chosen value on the right,
    /// like "Categoria" and "Unidade" on the item form.
    private func menuRow<Options: View>(
        title: String,
        isSuggested: Bool = false,
        value: String,
        color: Color,
        @ViewBuilder options: () -> Options
    ) -> some View {
        HStack {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 15))
                    .fontWeight(.semibold)
                if isSuggested {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.subTitleGray)
                        .voiceOverLabel(L10n.tr("Sugerido automaticamente"))
                }
            }

            Spacer(minLength: 12)

            Menu {
                options()
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(color)
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    Text(value)
                        .font(.system(size: 15))
                        .foregroundStyle(.black)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .foregroundColor(.black)
                        .imageScale(.small)
                }
            }
            .voiceOverLabel(title)
            .voiceOverValue(value)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Confirming

    private func confirm() {
        guard warning == nil else { return }
        viewModel.save(draft)
        didConfirm = true
        HapticsManager.notify(.success)
        dismiss()
    }
}

// MARK: - Previews

#Preview("Item da sua lista, vendido por peso") {
    let shopList = ReceiptScanPreviewData.shopList
    let viewModel = ReceiptScanPreviewData.review(of: shopList)
    var draft = viewModel.draft(for: viewModel.lines[1])
    if let banana = viewModel.linkableItems.first(where: { $0.name == "Banana" }) {
        viewModel.setLink(banana.id, in: &draft)
    }
    return Color.clear
        .sheet(isPresented: .constant(true)) {
            ReceiptLineFormView(draft: draft, viewModel: viewModel)
        }
}

#Preview("Item novo com valor a conferir") {
    let shopList = ReceiptScanPreviewData.shopList
    let viewModel = ReceiptScanPreviewData.review(of: shopList)
    let draft = viewModel.draft(for: viewModel.lines[2])
    return Color.clear
        .sheet(isPresented: .constant(true)) {
            ReceiptLineFormView(draft: draft, viewModel: viewModel)
        }
}

#Preview("Item sem valor, para duas pessoas") {
    let shopList = ReceiptScanPreviewData.shopList
    let viewModel = ReceiptScanPreviewData.review(of: shopList)
    var draft = viewModel.draft(for: viewModel.lines[4])
    viewModel.setConsumers(Array(viewModel.houseUsers.prefix(2)), in: &draft)
    return Color.clear
        .sheet(isPresented: .constant(true)) {
            ReceiptLineFormView(draft: draft, viewModel: viewModel)
        }
}

#Preview("Item adicionado à mão") {
    let shopList = ReceiptScanPreviewData.shopList
    let viewModel = ReceiptScanPreviewData.review(of: shopList)
    let draft = viewModel.draft(for: viewModel.addLine())
    return Color.clear
        .sheet(isPresented: .constant(true)) {
            ReceiptLineFormView(draft: draft, viewModel: viewModel)
        }
}
