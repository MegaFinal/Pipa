//
//  ReceiptReviewView.swift
//  Cognitive-Work
//
//  Created by anshu Li on 04/11/26.
//

import Foundation
import SwiftUI

/// The products read from a scanned receipt, reviewed before anything reaches the shopping
/// list. Drawn like the shopping area: the total like the balance on "Pendências"
/// (``ReceiptSummaryCard``), then one card per aisle like the list's (``ReceiptCategoryCard``),
/// with rows like the list's (``ReceiptLineRow``). Tapping a row opens its form
/// (``ReceiptLineFormView``); its check leaves it out, and the blue checkmark at the top right
/// confirms.
struct ReceiptReviewView: View {

    /// The scanned pages.
    let pages: [UIImage]
    /// The shopping list the receipt goes to.
    let shopList: ShopListViewModel
    /// Closes this sheet and opens the scanner (or the photo picker) again.
    let onScanAgain: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ReceiptScanViewModel
    /// The product whose form is open.
    @State private var editing: ReceiptLineDraft?
    /// Aisles whose card is collapsed to its banner.
    @State private var collapsed: Set<ShopItemCategory> = []

    init(pages: [UIImage], shopList: ShopListViewModel, onScanAgain: @escaping () -> Void) {
        self.pages = pages
        self.shopList = shopList
        self.onScanAgain = onScanAgain
        self._viewModel = State(initialValue: ReceiptScanViewModel())
    }

    /// A review already read (previews).
    init(viewModel: ReceiptScanViewModel, shopList: ShopListViewModel) {
        self.pages = []
        self.shopList = shopList
        self.onScanAgain = {}
        self._viewModel = State(initialValue: viewModel)
    }

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
            .background(Color.white.ignoresSafeArea())
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
            }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.white)
        .interactiveDismissDisabled(viewModel.isApplying)
        .sheet(item: $editing) { draft in
            ReceiptLineFormView(draft: draft, viewModel: viewModel)
        }
        .task {
            // Previews come already read (or stay reading, without pages).
            guard viewModel.phase == .reading, !pages.isEmpty else { return }
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
            Text("Tente de novo com a nota reta e bem iluminada.")
                .font(.system(size: 15))
                .foregroundStyle(.subTitleGray)
                .multilineTextAlignment(.center)
            scanAgainButton
            addLineButton
        }
        .padding(32)
    }

    // MARK: - Review

    private var review: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                ReceiptSummaryCard(
                    totalText: ReceiptScanViewModel.money(viewModel.sum),
                    status: summaryStatus
                )

                Text("Revise os itens antes de adicionar.")
                    .font(.system(size: 15))
                    .foregroundStyle(.subTitleGray)
                    .padding(.horizontal, 4)

                VStack(spacing: 10) {
                    ForEach(viewModel.sections) { section in
                        ReceiptCategoryCard(
                            section: section,
                            isExpanded: !collapsed.contains(section.category),
                            onToggle: { toggleCollapsed(section.category) }
                        ) { line in
                            row(for: line)
                        }
                    }
                }

                VStack(spacing: 8) {
                    addLineButton
                    scanAgainButton
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 40)
            .animation(.snappy, value: viewModel.lines.map(\.id))
        }
    }

    /// How the sum compares with the receipt's printed total.
    private var summaryStatus: ReceiptSummaryCard.Status {
        switch viewModel.totalCheck {
        case .matches: .matches
        case .differs(let total, _): .differs(receiptTotal: ReceiptScanViewModel.money(total))
        case .noPrintedTotal: .unknown
        }
    }

    /// One product's row, inside its aisle's card.
    private func row(for line: ReceiptScanLine) -> some View {
        ReceiptLineRow(
            name: line.name,
            detailText: viewModel.detailText(for: line),
            users: viewModel.consumers(for: line),
            needsReview: line.warning != nil,
            isIncluded: viewModel.isIncluded(line),
            onToggle: {
                withAnimation(.snappy) { viewModel.toggle(line) }
            },
            onEdit: {
                HapticsManager.selection()
                editing = viewModel.draft(for: line)
            }
        )
        .disabled(viewModel.isApplying)
    }

    /// "+ Adicionar item": a product the reader missed.
    private var addLineButton: some View {
        Button(action: addLine) {
            Label("Adicionar item", systemImage: "plus.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.blue)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isApplying)
        .voiceControlNames([L10n.tr("Adicionar item"), L10n.tr("Adicionar")])
    }

    /// Back to the camera (or the photos).
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

    // MARK: - Actions

    /// Collapses an aisle's card to its banner, or opens it.
    private func toggleCollapsed(_ category: ShopItemCategory) {
        withAnimation(.snappy) {
            if collapsed.contains(category) {
                collapsed.remove(category)
            } else {
                collapsed.insert(category)
            }
        }
    }

    /// Adds a product the reader missed and opens its form.
    private func addLine() {
        HapticsManager.selection()
        let line = withAnimation(.snappy) { viewModel.addLine() }
        editing = viewModel.draft(for: line)
    }

    /// Saves into the list and closes. It closes on a failure too (the list shows the error),
    /// since part of it may already be saved and confirming again would repeat it.
    private func confirm() async {
        let didSaveAll = await viewModel.confirm(into: shopList)
        if didSaveAll {
            HapticsManager.notify(.success)
            VoiceOver.announce(L10n.tr("Lista atualizada"))
        } else {
            HapticsManager.notify(.error)
        }
        dismiss()
    }
}

// MARK: - Previews

#Preview("Total diferente da nota") {
    let shopList = ReceiptScanPreviewData.shopList
    let viewModel = ReceiptScanPreviewData.review(of: shopList)
    return Color.clear
        .sheet(isPresented: .constant(true)) {
            ReceiptReviewView(viewModel: viewModel, shopList: shopList)
        }
}

#Preview("Confere com a nota") {
    let shopList = ReceiptScanPreviewData.shopList
    let viewModel = ReceiptScanPreviewData.cleanReview(of: shopList)
    return Color.clear
        .sheet(isPresented: .constant(true)) {
            ReceiptReviewView(viewModel: viewModel, shopList: shopList)
        }
}

#Preview("Sem total, itens desmarcados") {
    let shopList = ReceiptScanPreviewData.shopList
    let viewModel = ReceiptScanPreviewData.review(of: shopList, lines: ReceiptScanPreviewData.lines, printedTotal: nil)
    viewModel.lines.suffix(2).forEach { viewModel.toggle($0) }
    return Color.clear
        .sheet(isPresented: .constant(true)) {
            ReceiptReviewView(viewModel: viewModel, shopList: shopList)
        }
}

#Preview("Lendo a nota") {
    let shopList = ReceiptScanPreviewData.shopList
    return Color.clear
        .sheet(isPresented: .constant(true)) {
            ReceiptReviewView(viewModel: ReceiptScanViewModel(), shopList: shopList)
        }
}

#Preview("Nenhum item encontrado") {
    let shopList = ReceiptScanPreviewData.shopList
    let viewModel = ReceiptScanPreviewData.emptyReview(of: shopList)
    return Color.clear
        .sheet(isPresented: .constant(true)) {
            ReceiptReviewView(viewModel: viewModel, shopList: shopList)
        }
}
