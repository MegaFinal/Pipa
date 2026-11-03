//
//  ChoresView.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 25/08/26.
//

import SwiftUI
import CloudKit

/// The chores tab, the app's main screen.
///
/// It shows the chores as a carousel of today's chores ("Seu dia") or as a list of the whole
/// division ("Sua divisão"), with three progress cards on top and floating buttons to create
/// chores and to take chores that have no owner. Popups (a focused card, a chore opened from a
/// notification, the chores without owner, the new member pop-up) are drawn on top.
struct ChoresView: View {
    
    /// The view model controlling the state and data of the chores carousel.
    @State var carouselVM = CarouselViewModel()
    
    /// The dominant color derived from the currently focused chore's room.
    @State private var activeRoomColor: Color = .black
    
    /// Chore opened from a notification. Shown on top of everything until dismissed.
    @State private var choreFromNotification: ChoreOccurrence?
    
    /// Namespace used for matched geometry effect transitions between the list and carousel layouts.
    @Namespace private var cardAnimation
    
    /// Animation for switching between carousel and list.
    private static let layoutToggleAnimation: Animation = .snappy(duration: 0.3)
    
    /// Switches between carousel and list with ``layoutToggleAnimation``.
    private func toggleLayout() {
        withAnimation(Self.layoutToggleAnimation) {
            carouselVM.toggleLayout()
        }
        VoiceOver.announce(carouselVM.layoutMode == .grid ? L10n.tr("Seu dia") : L10n.tr("Sua divisão"))
    }
    
    /// Whether a card or popup covers the screen, so VoiceOver must skip what's behind it.
    private var isOverlayShown: Bool {
        carouselVM.hasFocusedCard || choreFromNotification != nil || carouselVM.itemAwaitingDate != nil
    }
    
    /// Opens the screen that creates a new division (from the new member pop-up).
    @State private var isResetting = false

    /// The Premium paywall (re-dividing mid-cycle is Premium).
    @State private var paywall: PremiumFeature?
    
    /// Opens the progress screen (from any of the progress cards).
    @State private var isShowingProgress = false
    
    /// Creates the view, optionally injecting a pre-populated view model (used by previews and tests).
    init(carouselVM: CarouselViewModel = CarouselViewModel()) {
        self._carouselVM = State(initialValue: carouselVM)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // MARK: - Header, progress cards and action buttons
                VStack(spacing: 3) {
                    VStack(spacing: 15) {
                        header
                        progressSection
                    }
                    // Solid at the top (under the status bar), fading out below the progress
                    // cards, so the list scrolls "under" the fixed block.
                    .background(alignment: .top) { headerFade }
                    // Above the list (zIndex 1000) so the fade covers the cards scrolling past.
                    .zIndex(1001)
                    
                    Spacer()
                        .matchedGeometryEffect(id: "Spawnpoint", in: cardAnimation)
                    
                    if carouselVM.layoutMode != .grid {
                        ChoreListLayout(
                            viewModel: carouselVM,
                            onSwipeDown: toggleLayout,
                            namespace: cardAnimation
                        )
                        .zIndex(1000)
                    }
                }
                .accessibilityHidden(isOverlayShown || carouselVM.isShowingUnassignedList)
                
                // MARK: - Floating buttons
                VStack {
                    Spacer()
                    ChoresViewButtonsSection(carouselViewModel: carouselVM)
                }
                .zIndex(carouselVM.hasFocusedCard ? 0 : 3)
                .accessibilityHidden(isOverlayShown)
                
                // MARK: - Darkening the view if there's a focused card
                if carouselVM.hasFocusedCard {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .zIndex(1)
                        .transition(.opacity)
                        .onTapGesture {
                            dismissFocusedCard()
                        }
                        // The card itself offers "Fechar" and the escape gesture.
                        .accessibilityHidden(true)
                }
                
                // MARK: - Chore Card layout conditionals
                if carouselVM.layoutMode == .grid {
                    VStack {
                        Spacer()
                        Carousel(
                            viewModel: carouselVM,
                            isBackgroundClear: true,
                            onSwipeDown: toggleLayout, namespace: cardAnimation
                        )
                        .padding(.top, 70)
                        Spacer()
                    }
                    .zIndex(2)
                    .accessibilityHidden(choreFromNotification != nil || carouselVM.itemAwaitingDate != nil || carouselVM.isShowingUnassignedList)
                } else if let occurrence = carouselVM.focusedOccurrence {
                    VStack {
                        Spacer()
                        CarouselCardFrame(
                            chore: occurrence.chore,
                            recurrentAssignment: occurrence.assignment,
                            carouselViewModel: carouselVM,
                            namespace: cardAnimation,
                            isFocused: true,
                            rotation: 180,
                            isShowingBack: true
                        )
                        .accessibilityElement(children: .contain)
                        .accessibilityAddTraits(.isModal)
                        .accessibilityAction(.escape) {
                            dismissFocusedCard()
                        }
                        Spacer()
                    }
                    .zIndex(2)
                    .transition(.scale)
                    .accessibilityHidden(choreFromNotification != nil || carouselVM.itemAwaitingDate != nil)
                }
                
                // MARK: - Chore opened from a notification
                if let occurrence = choreFromNotification {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .zIndex(4)
                        .transition(.opacity)
                        .onTapGesture {
                            dismissChoreFromNotification()
                        }
                        .accessibilityHidden(true)
                    
                    CarouselCardFrame(
                        chore: occurrence.chore,
                        recurrentAssignment: occurrence.assignment,
                        carouselViewModel: carouselVM,
                        namespace: cardAnimation,
                        isFocused: true,
                        rotation: 180,
                        isShowingBack: true
                    )
                    .zIndex(5)
                    .transition(.scale)
                    .accessibilityElement(children: .contain)
                    .accessibilityAddTraits(.isModal)
                    .accessibilityAction(.escape) {
                        dismissChoreFromNotification()
                    }
                    .accessibilityHidden(carouselVM.itemAwaitingDate != nil)
                }
                
                // MARK: - Unassigned chores popup, always on top of everything else
                if carouselVM.isShowingUnassignedList {
                    
                    Color.black.opacity(0.3)
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .zIndex(2000)
                        .transition(.opacity)
                        .onTapGesture {
                            carouselVM.dismissUnassignedList()
                        }
                        .accessibilityHidden(true)
                    
                    UnassignmentList(
                        items: carouselVM.unassignedItems,
                        onPick: { item in
                            Task { await carouselVM.requestPick(item) }
                        }, carouselViewModel: carouselVM
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 105)
                    .padding(.bottom, 20)
                    .zIndex(2100)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottomTrailing)))
                }
                
                // MARK: - Pick Unassigned Chore Card Overlay
                PickUnassignedChoreOverlay(carouselViewModel: carouselVM)
                    .zIndex(2999)
            }
            .background(
                Color(.white)
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismissFocusedCard()
                    }
            )
            .tabBarVisibilityRoot()
            // MARK: - New division screen (must be inside the NavigationStack, otherwise SwiftUI ignores it)
            .navigationDestination(isPresented: $isResetting) {
                FortnightlyScheduleView(shouldGenerate: true) {
                    isResetting = false
                }
            }
            // MARK: - Progress screen (opened by the progress cards)
            .navigationDestination(isPresented: $isShowingProgress) {
                DashboardView()
            }
        }
        .premiumPaywall($paywall)
        // MARK: - Loading and the progress cards' color
        .task {
            await carouselVM.fetchAllData()
            updateActiveRoomColor()
        }
        .task(id: carouselVM.activeIndex) {
            updateActiveRoomColor()
        }
        .task(id: carouselVM.dataVersion) {
            updateActiveRoomColor()
        }
        // MARK: - VoiceOver re-reads the screen whenever a card or popup opens or closes
        .onChange(of: carouselVM.hasFocusedCard) { _, _ in VoiceOver.screenChanged() }
        .onChange(of: choreFromNotification?.id) { _, _ in VoiceOver.screenChanged() }
        .onChange(of: carouselVM.isShowingUnassignedList) { _, _ in VoiceOver.screenChanged() }
        .onChange(of: carouselVM.itemAwaitingDate?.id) { _, _ in VoiceOver.screenChanged() }
        // MARK: - Reloads when CloudKit changes
        .onReceive(NotificationCenter.default.publisher(for: .cloudKitDidChange)) { _ in
            Task {
                await carouselVM.fetchAllData(afterRemoteChange: true)
            }
        }
        // MARK: - Delete error alert and new member pop-up
        .alert(
            "Não foi possível excluir",
            isPresented: Binding(
                get: { carouselVM.errorMessage != nil },
                set: { if !$0 { carouselVM.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(carouselVM.errorMessage ?? "")
        }
        .overlay { newUserPopUpOverlay }
    }
    
    // MARK: - Subviews
    
    /// "Seu dia" in the carousel (today's chores), "Sua divisão" in the list (the whole division).
    private var headerTitle: LocalizedStringKey {
        carouselVM.layoutMode == .grid ? "Seu dia" : "Sua divisão"
    }
    
    /// White gradient behind the fixed block: opaque, then transparent a little below it.
    private var headerFade: some View {
        HeaderFade()
    }
    
    /// Side margin shared by the header, the progress cards and the chore list (the list's
    /// cards are 92% of the screen wide, so 4% is left on each side).
    private var sideMargin: CGFloat { width * 0.04 }
    
    /// Page title alongside the layout toggle control.
    private var header: some View {
        HStack {
            // MARK: Title
            Text(headerTitle)
                .font(.custom("Alan Sans", size: 34))
                .bold()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)
                .padding(.horizontal, sideMargin)
                .padding(.top, 20)
                .accessibilityAddTraits(.isHeader)
//                .frame(width: width * 0.6)
            
            Spacer()
            
            HStack (spacing: 4) {
                // MARK: Layout toggle
                Button {
                    toggleLayout()
                } label: {
                    Image(systemName: carouselVM.layoutMode == .grid ? "inset.filled.leftthird.middlethird.rightthird.rectangle" : "inset.filled.topthird.middlethird.bottomthird.rectangle")
                        .font(.system(size: 22))
                        .foregroundColor(.black)
                        .padding(8)
                }
                .voiceOverLabel(carouselVM.layoutMode == .grid ? L10n.tr("Ver como lista") : L10n.tr("Ver como carrossel"))
                .voiceControlNames(carouselVM.layoutMode == .grid
                    ? [L10n.tr("Lista"), L10n.tr("Ver como lista"), L10n.tr("Layout")]
                    : [L10n.tr("Carrossel"), L10n.tr("Ver como carrossel"), L10n.tr("Layout")])
                
                // MARK: Notifications
                NavigationLink {
                    NotificationsView(
                        onPickChores: {
                            withAnimation { carouselVM.isShowingUnassignedList = true }
                        },
                        onOpenChore: { chore, assignment in
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                choreFromNotification = ChoreOccurrence(chore: chore, assignment: assignment)
                            }
                        },
                        onNewMember: {
                            carouselVM.presentNewUserPopUp()
                        }
                    )
                } label: {
                    Image(systemName: "bell")
                        .font(.system(size: 22))
                        .foregroundColor(.black)
                        .padding(8)
                }
                .voiceOverLabel(L10n.tr("Notificações"))
                .voiceControlNames([L10n.tr("Notificações"), L10n.tr("Avisos")])
                
                // MARK: Filter menu (list only)
                if carouselVM.layoutMode == .list {
                    Menu {
                        FilterOptionsMenu(viewModel: carouselVM)
                    } label: {
                        Image(systemName: carouselVM.isFilterOn
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease")
                        .font(.system(size: 22))
                        .foregroundColor(.black)
                        .padding(12)
                    }
                    .voiceOverLabel(L10n.tr("Filtrar e ordenar"))
                    .voiceOverValue(carouselVM.isFilterOn ? L10n.tr("Filtro ativo") : "")
                    .voiceControlNames([L10n.tr("Filtro"), L10n.tr("Ordenar"), L10n.tr("Filtrar e ordenar")])
                }
            }
            .glassEffect(
                .regular.interactive(),
                in: .capsule
            )
            .padding(.top, 20)
            .padding(.trailing, sideMargin)
        }
    }
    
    /// Informational segment displaying metric-based progress cards.
    ///
    /// Each card is bound to a different statistic from ``dashboard``
    private var progressSection: some View {
        let cardColor = carouselVM.layoutMode == .grid ? activeRoomColor : .black
        
        return HStack(spacing: 10) {
            progressCard(
                title: "Tempo médio",
                data: dashboard?.totalTimeFormatted ?? "0h00",
                color: cardColor
            )
            progressCard(
                title: "A fazer",
                data: L10n.tr("\(dashboard?.toDo ?? 0) tarefas"),
                color: cardColor
            )
            progressCard(
                title: "Concluído",
                data: (dashboard?.completionPercentage ?? 0)
                    .formatted(.percent.precision(.fractionLength(0)).locale(L10n.locale)),
                color: cardColor
            )
        }
        .padding(.horizontal, sideMargin)
        .animation(.easeInOut, value: activeRoomColor)
        .accessibilityElement(children: .contain)
        .voiceOverLabel(L10n.tr("Progresso do dia"))
    }
    
    /// One progress card; tapping it opens the progress screen.
    private func progressCard(title: LocalizedStringKey, data: String, color: Color) -> some View {
        Button {
            HapticsManager.selection()
            isShowingProgress = true
        } label: {
            ProgressIndicatorCard(title: title, data: data, color: color)
        }
        .buttonStyle(.plain)
        .voiceOverHint(L10n.tr("Abre o seu progresso."))
    }
    
    // MARK: - Actions
    
    /// Dismisses the currently focused card based on the active layout mode.
    private func dismissFocusedCard() {
        if carouselVM.layoutMode == .grid {
            carouselVM.clearFocus()
        } else {
            carouselVM.clearFocusedDetails()
        }
    }
    
    /// Closes the chore card opened from a notification.
    private func dismissChoreFromNotification() {
        withAnimation(.easeOut(duration: 0.2)) {
            choreFromNotification = nil
        }
    }
    
    /// Updates the background color of the progress section locally to match the focused chore's room color.
    private func updateActiveRoomColor() {
        guard !carouselVM.visibleChores.isEmpty,
              carouselVM.visibleChores.indices.contains(carouselVM.activeIndex) else {
            activeRoomColor = .black
            return
        }
        
        let centeredChore = carouselVM.visibleChores[carouselVM.activeIndex]
        
        if let room = carouselVM.getRoom(for: centeredChore) {
            activeRoomColor = room.color.progressCardColor
        } else {
            activeRoomColor = .gray
        }
    }
    
    /// Today's chore statistics.
    private var dashboard: DashboardModel? {
        carouselVM.dashboard
    }
    
    /// The "new member" pop-up over a dark background. Confirming opens a new division.
    ///
    /// Only the house admin gets `showNewUserPopUp == true` (see `CarouselViewModel.checkNewUser`).
    @ViewBuilder
    private var newUserPopUpOverlay: some View {
        if carouselVM.showNewUserPopUp {
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { }
                
                NewUserPopUp {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        carouselVM.showNewUserPopUp = false
                        // Free plan: the new member joins the division at the next cycle (and
                        // can take chores without an owner meanwhile). Premium re-divides now.
                        if PremiumManager.shared.allows(.rebalanceDivision) {
                            isResetting = true
                        } else {
                            paywall = .rebalanceDivision
                        }
                    }
                } onDismiss: {
                    carouselVM.showNewUserPopUp = false
                }
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
            .transition(.opacity)
        }
    }
}


// MARK: - Private subviews

/// Renders statistics paired with a title tag.
private struct ProgressIndicatorCard: View {
    /// The card's label (e.g. "A fazer").
    var title: LocalizedStringKey
    /// Formatted data result (e.g., "1h 30m").
    var data: String
    /// The card's background color.
    var color: Color = .black
    
    var body: some View {
        VStack(spacing: 5) {
            Spacer()
            Text(title)
                .font(.system(size: 12))
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.8))
            
            Text(data)
                .font(.custom("Alan Sans", size: 15))
                .fontWeight(.semibold)
                .foregroundColor(.white)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: height * 0.088)
        .background(color)
        .clipShape(RoundedRectangle(cornerRadius: 21))
        .shadow(color: .black.opacity(0.25), radius: 4.07717, x: 0, y: 1.23551)
        .accessibilityElement(children: .combine)
    }
}

/// A single scheduled occurrence of a chore: the chore itself plus the
/// assignment that places it on a given day.
///
/// One-off chores have no assignment; their date comes from `chore.dueDate`.
struct ChoreOccurrence: Identifiable {
    /// The chore.
    let chore: ChoreModel
    /// The occurrence's assignment, or `nil` for one-off chores.
    let assignment: RecurrentAssignmentModel?
    
    /// A unique id: the assignment's record name, or the chore's id.
    var id: String {
        if let assignmentId = assignment?.recordID {
            return assignmentId.recordName
        }
        return chore.id.uuidString
    }
    
    /// The day of this occurrence.
    var day: Date? {
        return assignment?.day ?? chore.dueDate
    }
}

#Preview("Lista de tarefas") {
    let vm: CarouselViewModel = {
        var cozinha = RoomModel(name: "Cozinha", symbol: "cooktop", color: .orange)
        cozinha.recordID = CKRecord.ID(recordName: "preview-cozinha")
        
        var banheiro = RoomModel(name: "Banheiro", symbol: "toilet", color: .blue)
        banheiro.recordID = CKRecord.ID(recordName: "preview-banheiro")
        
        func makeChore(_ name: String, symbol: String, room: RoomModel, frequency: Recurrence, duration: Double, priority: PriorityTag) -> ChoreModel {
            let chore = ChoreModel(
                name: name,
                description: "Descrição da tarefa \(name.lowercased()).",
                frequency: frequency,
                duration: duration,
                isPublic: true,
                priorityTag: priority,
                roomReference: room.recordID.map { CKRecord.Reference(recordID: $0, action: .none) }
            )
            chore.symbolName = symbol
            chore.recordID = CKRecord.ID(recordName: "preview-\(UUID().uuidString)")
            return chore
        }
        
        let vm = CarouselViewModel()
        vm.roomModels = [cozinha, banheiro]
        vm.cardModels = [
            makeChore("Lavar a louça", symbol: "dishwasher", room: cozinha,
                      frequency: .daily, duration: 20, priority: .medium),
            makeChore("Limpar o box", symbol: "shower", room: banheiro,
                      frequency: .weekly, duration: 45, priority: .high),
            makeChore("Organizar a despensa", symbol: "cabinet", room: cozinha,
                      frequency: .monthly, duration: 90, priority: .low)
        ]
        return vm
    }()
    
    ChoresView(carouselVM: vm)
}
