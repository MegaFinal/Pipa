//
//  ShopListView.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 18/09/26.
//

import SwiftUI
import CloudKit

/// The shopping tab: the house's shopping list grouped in sections, with a button to add items,
/// a sort menu and a link to the "Pendências" (who owes whom) screen.
struct ShopListView: View {
    @State private var viewModel: ShopListViewModel

    /// Shows the "new item" sheet.
    @State private var isPresentingAddItem = false
    /// The item being edited, or `nil`.
    @State private var editingItem: ShopListItem?
    /// Opens the "Pendências" screen.
    @State private var isShowingPendingPayments = false

    /// Whether the "add several items with AI" sheet is open.
    @State private var isPresentingAIBatch = false
    /// Whether the AI button shows: the on-device model can run on this device and language.
    @State private var canUseAI = false

    /// The Premium feature whose paywall is open, or `nil`.
    @State private var paywall: PremiumFeature?

    /// "Pode estar faltando": usual items and products that go with the list.
    @State private var suggestionsModel: ShopListSuggestionViewModel

    /// Which card is swiped open; shared so only one can be open at a time.
    @State private var revealedItemID: String?

    /// The delete button matches the row: same height, 16-point corners.
    private let swipeStyle = SwipeToDeleteStyle(cornerRadius: 16, topInset: 0)

    /// Creates the screen. Pass a ready view model for previews.
    init(viewModel: ShopListViewModel? = nil) {
        let shopList = viewModel ?? ShopListViewModel()
        self._viewModel = State(initialValue: shopList)
        self._suggestionsModel = State(initialValue: ShopListSuggestionViewModel(shopList: shopList))
    }

    var body: some View {
        NavigationStack {
            // MARK: - Content and the "Pendências" link
            content
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(isPresented: $isShowingPendingPayments) {
                    PendingPaymentsView(shopList: viewModel)
                }
                .premiumPaywall($paywall)
        }
    }

    /// The page: title and buttons, then the list
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - Fixed block: title and buttons
            // (The "Pode estar faltando" suggestions now sit inside each category's card.)
            VStack(alignment: .leading, spacing: 20) {
                header
            }
            .background(alignment: .top) { HeaderFade(color: .white) }
            .zIndex(1)

            // MARK: - Spinner, empty state or list
            if !viewModel.hasLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.isListEmpty {
                ShopListEmptyState()
                    .frame(maxHeight: .infinity)
            } else {
                itemList
            }
        }
        // MARK: - Add button and price pop-up
        .overlay(alignment: .bottomTrailing) {
            HStack {
                if canUseAI {
                    aiBatchButton
                }
                addButton
            }
            .floatingActionPlacement()
        }
        .background(Color(.white).ignoresSafeArea())
        .overlay { purchasePriceOverlay }
        .animation(.easeInOut(duration: 0.25), value: viewModel.purchasePrompt?.id)
        // MARK: - Loading and refreshing
        .task {
            canUseAI = viewModel.canSuggestItemDetails
            guard !viewModel.hasLoaded else { return }
            await viewModel.setup()
        }
        // Suggestions follow the list: an item added, bought or removed changes them.
        .onChange(of: suggestionsKey, initial: true) { _, _ in
            suggestionsModel.refresh()
        }
        #if DEBUG
        // DEBUG test mode: a "day" is a minute, so time alone can make an item due; check again
        // every 30 seconds instead of waiting for the list to change.
        .task {
            guard ShopListSuggestionViewModel.usesMinutesAsDays else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                suggestionsModel.refresh()
            }
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .cloudKitDidChange)) { _ in
            viewModel.requestRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            viewModel.requestRefresh()
        }
        // MARK: - New item and edit item sheets
        .sheet(isPresented: $isPresentingAddItem) {
            ShopListItemFormView(
                mode: .create,
                availableUsers: viewModel.houseUsers,
                currentUser: viewModel.currentUser,
                viewModel: viewModel
            )
        }
        // Several items at once with the on-device model, reviewed before saving.
        .sheet(isPresented: $isPresentingAIBatch) {
            AddMoreItensInteligence(viewModel: viewModel)
        }
        .sheet(item: $editingItem) { item in
            ShopListItemFormView(
                mode: .edit(item),
                availableUsers: viewModel.houseUsers,
                currentUser: viewModel.currentUser,
                viewModel: viewModel
            )
        }
        // MARK: - Error alert
        .alert(
            "Não foi possível concluir",
            isPresented: Binding(
                // The AI sheet shows its own errors.
                get: { viewModel.errorMessage != nil && !isPresentingAddItem && editingItem == nil && !isPresentingAIBatch },
                set: { if !$0 { viewModel.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    /// Changes whenever an item is added, removed, bought or renamed.
    private var suggestionsKey: String {
        viewModel.items
            .map { "\($0.id)\($0.isBought)\($0.name)" }
            .joined(separator: "|")
    }

    // MARK: - Price pop-up

    /// "How much was it?", over a dimmed backdrop, when an item without a price is checked off.
    @ViewBuilder
    private var purchasePriceOverlay: some View {
        if let prompt = viewModel.purchasePrompt {
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.dismissPurchasePrompt() }
                    .accessibilityHidden(true)

                PurchasePricePopUp(
                    itemName: prompt.item.name,
                    quantity: prompt.item.quantity,
                    onConfirm: { text in
                        Task { await viewModel.confirmPurchaseAnnouncing(of: prompt.item, valueText: text) }
                    },
                    onSkip: {
                        Task { await viewModel.confirmPurchaseAnnouncing(of: prompt.item, valueText: nil) }
                    },
                    onCancel: { viewModel.dismissPurchasePrompt() }
                )
                .id(prompt.id)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
            .transition(.opacity)
        }
    }

    // MARK: - Header

    /// Page title alongside the controls, laid out like the header of ``ChoresView``.
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                // MARK: Title and pending summary
                Text("Compras")
                    .font(.custom("Alan Sans", size: 34))
                    .fontWeight(.bold)
                    .accessibilityAddTraits(.isHeader)

                if !viewModel.pendingItems.isEmpty {
                    Text(viewModel.pendingSummary)
                        .font(.system(size: 18))
                        .foregroundStyle(.subTitleGray)
                        .fontWeight(.semibold)
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 20)

            Spacer()

            // MARK: "Pendências" button and sort menu
            HStack(spacing: 4) {
                Button {
                    HapticsManager.selection()
                    // Premium: free houses still record prices, so the history is there
                    // the day they subscribe.
                    if PremiumManager.shared.allows(.debts) {
                        isShowingPendingPayments = true
                    } else {
                        paywall = .debts
                    }
                } label: {
                    Image(systemName: "banknote.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.black)
                        .padding(8)
                        .overlay(alignment: .topTrailing) {
                            if !PremiumManager.shared.isPremium { PremiumBadge() }
                        }
                }
                .accessibilityLabel("Pendências")
                .voiceControlNames([L10n.tr("Pendências"), L10n.tr("Dinheiro"), L10n.tr("Pagamentos")])

                Menu {
                    Picker("Ordenar por", selection: $viewModel.sortOption) {
                        ForEach(ShopListSortOption.allCases) { option in
                            Label(option.label, systemImage: option.symbol).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 22))
                        .foregroundColor(.black)
                        .padding(12)
                }
                .accessibilityLabel("Ordenar por")
                .voiceOverValue(viewModel.sortOption.label)
                .voiceControlNames([L10n.tr("Ordenar"), L10n.tr("Filtro"), L10n.tr("Ordenar por")])
            }
            .glassEffect(
                .regular.interactive(),
                in: .capsule
            )
            .padding(.top, 20)
            .padding(.trailing, 30)
        }
    }

    // MARK: - List

    /// The scrolling list: the stack of cards to buy, a black line, then the "bought" cards.
    private var itemList: some View {
        let pendingSections = viewModel.pendingSections

        return ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ShopSectionStack(
                    viewModel: viewModel,
                    sections: pendingSections,
                    footer: { section in
                        guard let category = section.category else { return AnyView(EmptyView()) }
                        return AnyView(ShopSuggestionCards(model: suggestionsModel, category: category))
                    }
                ) { item in
                    row(for: item)
                }
                .padding(.top, 30)

                ShopSuggestionsLeftoverBox(
                    model: suggestionsModel,
                    shownCategories: Set(pendingSections.compactMap(\.category))
                )
                .padding(.top, 24)
                .animation(.snappy, value: suggestionsModel.suggestions.map(\.id))

                if let boughtSection = viewModel.boughtSection {
                    if !pendingSections.isEmpty {
                        boughtDivider
                            .padding(.top, sectionSpacing)
                    }

                    ShopSectionStack(viewModel: viewModel, sections: [boughtSection]) { item in
                        row(for: item)
                    }
                    .padding(.top, 20)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    /// Space between the "to buy" stack and the "bought" line.
    private let sectionSpacing: CGFloat = 40

    /// The black line above the "bought" section.
    private var boughtDivider: some View {
        Capsule()
            .fill(Color.black)
            .frame(height: 1.5)
            .frame(maxWidth: .infinity)
    }

    /// One item card that can be swiped to delete and tapped to edit.
    private func row(for item: ShopListItem) -> some View {
        SwipeToDeleteRow(
            id: item.id,
            revealedID: $revealedItemID,
            style: swipeStyle,
            onDelete: {
                Task { await viewModel.deleteItemAnnouncing(item) }
            }
        ) {
            ShopListItemCard(
                item: item,
                relatedUsers: viewModel.relatedUsers(for: item),
                onToggle: { await viewModel.toggleBoughtAnnouncing(item) },
                onTap: {
                    if revealedItemID != nil {
                        withAnimation(.snappy) { revealedItemID = nil }
                    } else {
                        editingItem = item
                    }
                }
            )
        }
        .accessibilityAction(named: Text(verbatim: L10n.tr("Editar"))) {
            editingItem = item
        }
    }

    /// Opens ``AddMoreItensInteligence`` to add several items from one text.
    private var aiBatchButton: some View {
        FloatingActionButton(
            showsPremiumBadge: !PremiumManager.shared.isPremium, systemImage: "sparkles",
            symbolSize: 28,
            foreground: .black,
            tint: nil
        ) {
            HapticsManager.selection()
            if PremiumManager.shared.allows(.shopAI) {
                isPresentingAIBatch = true
            } else {
                paywall = .shopAI
            }
        }
        .disabled(!viewModel.canAddItems)
        .voiceOverLabel(L10n.tr("Adicionar com IA"))
        .voiceControlNames([L10n.tr("Adicionar com IA"), L10n.tr("IA")])
        .transition(.scale.combined(with: .opacity))
    }

    /// The floating "+" button that opens the new item sheet.
    private var addButton: some View {
        FloatingActionButton(systemImage: "plus") {
            HapticsManager.selection()
            isPresentingAddItem = true
        }
        .disabled(!viewModel.canAddItems)
        .voiceOverLabel(L10n.tr("Adicionar item"))
        .voiceControlNames([L10n.tr("Adicionar"), L10n.tr("Mais"), L10n.tr("Adicionar item")])
    }
}

// MARK: - Empty state

/// Shown when the list has no items: the mascot and a hint to tap "+".
private struct ShopListEmptyState: View {

    /// Makes the sparkles grow a little once the view appears.
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(RoomColor.orange.lowOpacityColor.opacity(0.3))

                SymbolImage(name: "plastic.bag")
                    .foregroundStyle(RoomColor.orange.uiColor)
                    .frame(width: 128, height: 128)
            }
            .frame(width: 176, height: 176)
            .clipShape(Circle())
            .overlay(alignment: .topTrailing) {
                sparkle(size: 24).offset(x: 4, y: 6)
            }
            .overlay(alignment: .bottomLeading) {
                sparkle(size: 16).offset(x: 2, y: -10)
            }
            .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text("Lista de compras vazia")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.titleGray)
                    .multilineTextAlignment(.center)

                Text("Toque em \"+\" para adicionar o primeiro item.")
                    .font(.system(size: 16))
                    .foregroundStyle(.subTitleGray)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .onAppear { isAnimating = true }
    }

    /// A small yellow sparkle around the mascot.
    private func sparkle(size: CGFloat) -> some View {
        Image(systemName: "sparkle")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(RoomColor.orange.uiColor)
            .scaleEffect(isAnimating ? 1.15 : 0.85)
    }
}

#Preview("Lista") {
    ShopListView(viewModel: ShopListPreviewData.populatedViewModel)
}
