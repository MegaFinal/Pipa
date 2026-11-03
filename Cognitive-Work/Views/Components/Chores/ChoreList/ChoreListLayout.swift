//
//  ChoreListLayout.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 26/08/26.
//

import SwiftUI
import UIKit

/// The list layout of the chores screen: occurrences grouped under one collapsible title per
/// day ("Hoje 23/09 ⌄"), nearest day first, each card with a custom swipe-to-delete.
struct ChoreListLayout: View {
    
    /// The carousel view model controlling the global collection of chores.
    @Bindable var viewModel: CarouselViewModel
    
    /// Called when the list is pulled down past the top: switches back to the carousel.
    let onSwipeDown: () -> Void
    
    /// Namespace required for geometric transitions into the grid view.
    let namespace: Namespace.ID
    
    /// Days the user has collapsed, keyed by ``DayGroup/id``.
    @State private var collapsedDays: Set<Date> = []
    
    /// The occurrence whose delete button is currently revealed. Only one at a time: revealing
    /// another closes it, and tapping any card closes it instead of opening the details.
    @State private var revealedOccurrenceID: String?
    
    /// Whether the list is currently pulled down past its top edge by more than
    /// ``pullDownThreshold``. Only flips when crossing the threshold, so scrolling doesn't
    /// re-render the list every frame.
    @State private var isPulledPastThreshold = false
    
    /// How far past the top (in points) the list must be pulled, on release, to switch back
    /// to the carousel.
    private let pullDownThreshold: CGFloat = 70
    
    // MARK: - Spacing
    
    /// Gap between two cards of the same day.
    private let cardSpacing: CGFloat = 18
    
    /// Gap between a day's title and its first card.
    private let titleToCardSpacing: CGFloat = 20
    
    /// Gap above each day's title, separating it from the previous day.
    private let daySpacing: CGFloat = 20
    
    /// The suggested order of the viewer's chores today (see ``TodayChoreOrder``).
    private var todayOrder: TodayChoreOrder { TodayChoreOrder.shared }

    /// Changes whenever today's open chores change, to refresh ``todayOrder``.
    private var todayOrderKey: String {
        viewModel.openOccurrencesToday()
            .map { "\($0.occurrence.id)\($0.isMine)" }
            .joined(separator: "|")
    }

    /// Look and feel of the swipe-to-delete — see ``SwipeToDeleteStyle``.
    private let swipeStyle = SwipeToDeleteStyle()
    
    /// Creates the list.
    init(viewModel: CarouselViewModel, onSwipeDown: @escaping () -> Void, namespace: Namespace.ID) {
        self.viewModel = viewModel
        self.onSwipeDown = onSwipeDown
        self.namespace = namespace
    }
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                // MARK: - One title and its cards per day
                ForEach(dayGroups) { group in
                    dayTitle(for: group)
                        .padding(.top, daySpacing)
                        .padding(.bottom, titleToCardSpacing)
                    
                    if !collapsedDays.contains(group.id) {
                        // Today only: the suggested order of the viewer's own chores (AI).
                        if group.isToday, todayOrder.steps.count >= 2 {
                            TodayOrderBox(steps: todayOrder.steps)
                                .frame(width: width * 0.92)
                                .padding(.bottom, cardSpacing)
                        }

                        VStack(spacing: cardSpacing) {
                            ForEach(group.occurrences) { item in
                                card(for: item)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 120)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollClipDisabled()
        // MARK: - Pull down past the top to go back to the carousel
        .onScrollGeometryChange(for: Bool.self) { geometry in
            -(geometry.contentOffset.y + geometry.contentInsets.top) > pullDownThreshold
        } action: { _, isPastThreshold in
            isPulledPastThreshold = isPastThreshold
        }
        .onScrollPhaseChange { oldPhase, newPhase in
            if oldPhase == .interacting, newPhase != .interacting, isPulledPastThreshold {
                onSwipeDown()
            }
        }
        .matchedGeometryEffect(id: "Spawnpoint", in: namespace)
        // Rebuilds the suggested order when today's chores change (done, added, reassigned).
        .task(id: todayOrderKey) {
            await todayOrder.refresh(using: viewModel)
        }
        // MARK: - Empty state
        .overlay {
            if viewModel.visibleOccurrences.isEmpty {
                emptyState
            }
        }
    }
    
    // MARK: - Subviews
    
    /// One card, wrapped in the swipe-to-delete.
    private func card(for item: IndexedOccurrence) -> some View {
        SwipeToDeleteRow(
            id: item.id,
            revealedID: $revealedOccurrenceID,
            style: swipeStyle,
            onDelete: { delete(item.occurrence) }
        ) {
            ChoreCardListStyle(
                chore: item.occurrence.chore,
                recurrentAssignment: item.occurrence.assignment,
                namespace: namespace,
                carouselViewModel: viewModel
            ) {
                if revealedOccurrenceID != nil {
                    withAnimation(.snappy) { revealedOccurrenceID = nil }
                } else {
                    viewModel.focusDetailsImmediately(item.index)
                }
            }
        }
    }
    
    /// A day's title ("Hoje 23/09 ⌄"). Tapping it collapses or expands that day.
    private func dayTitle(for group: DayGroup) -> some View {
        let isCollapsed = collapsedDays.contains(group.id)
        
        return Button {
                if isCollapsed {
                    collapsedDays.remove(group.id)
                } else {
                    collapsedDays.insert(group.id)
                }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(group.title)
                    .font(.system(size: 22, weight: .bold))
                
                if let dateText = group.dateText {
                    Text(dateText)
                        .font(.system(size: 17))
                }
                
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
            }
            .foregroundStyle(.black)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: width * 0.92, alignment: .leading)
        // "Hoje, quinta-feira, 25 de setembro" — header — "expandido, 3 tarefas"
        .voiceOverLabel(group.accessibilityTitle)
        .voiceControlNames([group.title])
        .accessibilityValue(Text(verbatim: "\(isCollapsed ? L10n.tr("recolhido") : L10n.tr("expandido")), \(L10n.tr("\(group.occurrences.count) tarefas"))"))
        .voiceOverHint(isCollapsed ? L10n.tr("Toque duas vezes para expandir.") : L10n.tr("Toque duas vezes para recolher."))
        .accessibilityAddTraits(.isHeader)
    }
    
    /// Shown when there's nothing to list — either the house has no chores, or the active
    /// filter matches none.
    private var emptyState: some View {
        ChoresEmptyState(kind: viewModel.isFilterOn ? .filtered : .division)
    }
    
    // MARK: - Day grouping
    
    /// ``CarouselViewModel/visibleOccurrences`` split into one group per calendar day.
    ///
    /// The view model always sorts by day first, so each day's occurrences are already
    /// contiguous — this only has to cut the list wherever the day changes.
    private var dayGroups: [DayGroup] {
        let calendar = Calendar.current
        var groups: [DayGroup] = []
        
        for (index, occurrence) in viewModel.visibleOccurrences.enumerated() {
            let day = occurrence.day.map { calendar.startOfDay(for: $0) }
            let item = IndexedOccurrence(index: index, occurrence: occurrence)
            
            if let last = groups.last, last.day == day {
                groups[groups.count - 1].occurrences.append(item)
            } else {
                groups.append(DayGroup(day: day, occurrences: [item]))
            }
        }
        
        return groups
    }
    
    // MARK: - Actions
    
    /// Deletes an occurrence: only that day for a recurring chore (the chore and its other
    /// occurrences are left alone), or the whole chore for a one-off one.
    @MainActor
    private func delete(_ occurrence: ChoreOccurrence) {
        let targetOccurrences = occurrence.assignment.map { [$0] } ?? []
        
        let snapshot: CarouselViewModel.RemovedOccurrenceSnapshot = withAnimation(.snappy) {
            revealedOccurrenceID = nil
            return viewModel.removeOccurrenceLocally(chore: occurrence.chore, targetOccurrences: targetOccurrences)
        }
        VoiceOver.announce(L10n.tr("Tarefa excluída"))
        
        Task {
            await viewModel.persistDelete(chore: occurrence.chore, targetOccurrences: targetOccurrences, restoring: snapshot)
        }
    }
}

// MARK: - Swipe to delete

/// How the list's swipe-to-delete looks and behaves. Change the defaults here to adjust it.
struct SwipeToDeleteStyle {
    
    /// Width of the revealed delete button.
    var buttonWidth: CGFloat = 76
    
    /// Gap between the card and the button once it's revealed.
    var gap: CGFloat = 10
    
    /// Corner radius of the button. The card's own is 25.
    var cornerRadius: CGFloat = 25
    
    /// Space above the button, so it lines up with the card's body below its folder tab.
    var topInset: CGFloat = 38
    
    /// The button's background color.
    var backgroundColor: Color = .red
    /// The icon and title color.
    var foregroundColor: Color = .white
    /// The button's SF Symbol.
    var systemImage: String = "trash.fill"
    
    /// Label under the icon; `nil` shows the icon alone.
    var title: String? = "Excluir"
    
    /// Dragging the card past this fraction of the row's width and letting go deletes right
    /// away, without tapping the button (like iOS's own "full swipe").
    var fullSwipeFraction: CGFloat = 0.55
    
    /// Animation used to open, close and dismiss the card.
    var animation: Animation = .snappy
}

/// Wraps a card with a left swipe that slides it aside to reveal a delete button.
/// Shared by the chore list and the shopping list.
struct SwipeToDeleteRow<Content: View>: View {
    
    /// This row's id.
    let id: String
    
    /// Which row is revealed; shared by every row so only one can be open at a time.
    @Binding var revealedID: String?
    
    /// The look and feel of the swipe.
    let style: SwipeToDeleteStyle
    /// Called after the card slid away.
    let onDelete: () -> Void
    /// The card inside the row.
    let content: Content
    
    /// Live horizontal translation of the drag in progress (0 when idle).
    @State private var dragTranslation: CGFloat = 0
    
    /// Whether the current drag is past the full-swipe threshold, so the haptic only fires
    /// when crossing it.
    @State private var isPastFullSwipe = false
    
    /// Set once deleting starts, sliding the card off screen.
    @State private var isDeleting = false
    
    /// The row's width, to know when a drag is a full swipe.
    @State private var rowWidth: CGFloat = 0
    
    /// Creates a row.
    /// - Parameters:
    ///   - id: This row's id.
    ///   - revealedID: Which row is open, shared by every row.
    ///   - style: The look and feel of the swipe.
    ///   - onDelete: Called after the card slid away.
    ///   - content: The card.
    init(
        id: String,
        revealedID: Binding<String?>,
        style: SwipeToDeleteStyle,
        onDelete: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.id = id
        self._revealedID = revealedID
        self.style = style
        self.onDelete = onDelete
        self.content = content()
    }
    
    /// Whether this row is the open one.
    private var isRevealed: Bool { revealedID == id }
    
    /// How far the card slides to reveal the button.
    private var revealDistance: CGFloat { style.buttonWidth + style.gap }
    
    /// How far a drag must go to delete without tapping the button.
    private var fullSwipeDistance: CGFloat { rowWidth * style.fullSwipeFraction }
    
    /// The card's current horizontal offset (always ≤ 0: it only ever slides left).
    private var offset: CGFloat {
        if isDeleting { return -(rowWidth + revealDistance) }
        let resting: CGFloat = isRevealed ? -revealDistance : 0
        return min(0, resting + dragTranslation)
    }
    
    /// 0 with the card at rest, 1 once it has slid far enough to fully show the button.
    private var revealProgress: CGFloat {
        guard revealDistance > 0 else { return 0 }
        return min(1, -offset / revealDistance)
    }
    
    var body: some View {
        // MARK: - The card, with the delete button behind it
        content
            // MARK: - VoiceOver alternative to the swipe: an "Excluir" action on the row
            .accessibilityAction(named: Text(L10n.tr(key: style.title ?? "Excluir"))) {
                dismissAndDelete()
            }
            .background(alignment: .trailing) {
                deleteButton
                    .offset(x: -offset)
            }
            .offset(x: offset)
            // MARK: - Measures the row and handles the swipe
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { rowWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, newWidth in rowWidth = newWidth }
                }
            }
            .gesture(swipeGesture)
    }
    
    /// The red delete button, fading in as the card slides.
    private var deleteButton: some View {
        Button(action: dismissAndDelete) {
            VStack(spacing: 4) {
                Image(systemName: style.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                
                if let title = style.title {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundStyle(style.foregroundColor)
            .frame(width: style.buttonWidth)
            .frame(maxHeight: .infinity)
            .background(style.backgroundColor, in: RoundedRectangle(cornerRadius: style.cornerRadius))
        }
        .buttonStyle(.plain)
        .padding(.top, style.topInset)
        .opacity(revealProgress)
        .scaleEffect(0.8 + 0.2 * revealProgress)
        .allowsHitTesting(isRevealed && !isDeleting)
        // Reached through the row's "Excluir" accessibility action instead.
        .accessibilityHidden(true)
    }

    /// The swipe: follows the finger, opens/closes the button, or deletes on a full swipe.
    private var swipeGesture: HorizontalPanGesture {
        HorizontalPanGesture(
            onBegan: {
                guard !isDeleting else { return }
                if let revealedID, revealedID != id {
                    withAnimation(style.animation) { self.revealedID = nil }
                }
            },
            onChanged: { translation in
                guard !isDeleting else { return }
                dragTranslation = translation
                
                let pastFullSwipe = -offset > fullSwipeDistance
                if pastFullSwipe != isPastFullSwipe {
                    isPastFullSwipe = pastFullSwipe
                    HapticsManager.impact(.medium)
                }
            },
            onEnded: { translation, velocity, wasCancelled in
                defer { isPastFullSwipe = false }
                guard !isDeleting else { return }
                
                if !wasCancelled, -offset > fullSwipeDistance {
                    dismissAndDelete()
                    return
                }
                
                let resting: CGFloat = isRevealed ? -revealDistance : 0
                let projected = resting + translation + (wasCancelled ? 0 : velocity * 0.25)
                
                withAnimation(style.animation) {
                    dragTranslation = 0
                    revealedID = -projected > revealDistance / 2 ? id : (isRevealed ? nil : revealedID)
                }
            }
        )
    }
    
    /// Slides the card off screen, then deletes it.
    private func dismissAndDelete() {
        guard !isDeleting else { return }
        HapticsManager.notify(.warning)
        
        withAnimation(style.animation) {
            isDeleting = true
            dragTranslation = 0
        } completion: {
            onDelete()
        }
    }
}

// MARK: - Horizontal pan

/// A pan that only ever *begins* for a mostly-horizontal drag.
///
/// A vertical drag makes this recognizer fail right away (`gestureRecognizerShouldBegin`),
/// so the enclosing `ScrollView` always gets vertical scrolling
struct HorizontalPanGesture: UIGestureRecognizerRepresentable {
    
    /// Called once, when a horizontal drag is recognized.
    var onBegan: () -> Void
    
    /// Called with the horizontal translation (points) as the drag moves.
    var onChanged: (CGFloat) -> Void
    
    /// Called when the drag finishes, with the final horizontal translation
    var onEnded: (_ translation: CGFloat, _ velocity: CGFloat, _ wasCancelled: Bool) -> Void
    
    /// Creates the delegate that only lets horizontal drags start.
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }
    
    /// Creates the UIKit pan recognizer.
    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }
    
    /// Sends the pan's changes to the closures above.
    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view).x
        
        switch recognizer.state {
        case .began:
            onBegan()
            onChanged(translation)
        case .changed:
            onChanged(translation)
        case .ended:
            onEnded(translation, recognizer.velocity(in: recognizer.view).x, false)
        case .cancelled, .failed:
            onEnded(translation, 0, true)
        default:
            break
        }
    }
    
    /// The pan's delegate.
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// Only start for drags that move more sideways than up/down.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }
}

// MARK: - Grouping models

/// One day's section in the list layout.
private struct DayGroup: Identifiable {
    /// The app's language, for the weekday and date.
    private static var locale: Locale { L10n.locale }
    
    /// The day, at its start; `nil` for occurrences with no date.
    let day: Date?
    /// The day's occurrences, in order.
    var occurrences: [IndexedOccurrence]
    
    /// A unique id: the day (undated groups use a far future date).
    var id: Date { day ?? .distantFuture }

    /// Whether this is today's group (it gets the suggested-order box).
    var isToday: Bool {
        day.map { Calendar.current.isDateInToday($0) } ?? false
    }
    
    /// "Hoje", "Amanhã", or the weekday's name ("Sexta-feira"). Past days never get a
    /// group — `CarouselViewModel` leaves them out of the list.
    var title: String {
        guard let day else { return L10n.tr("Sem data") }
        
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return L10n.tr("Hoje") }
        if calendar.isDateInTomorrow(day) { return L10n.tr("Amanhã") }
        
        let weekday = day.formatted(.dateTime.weekday(.wide).locale(Self.locale))
        return weekday.prefix(1).uppercased() + weekday.dropFirst()
    }
    
    /// Spoken title: "Hoje, quinta-feira, 25 de setembro" (or "Sem data").
    var accessibilityTitle: String {
        guard let day else { return title }
        let longDate = CarouselViewModel.accessibilityDateText(day)
        let calendar = Calendar.current
        if calendar.isDateInToday(day) || calendar.isDateInTomorrow(day) {
            return "\(title), \(longDate)"
        }
        return longDate
    }
    
    /// "25/09", or `nil` for the undated group.
    var dateText: String? {
        // Day/month order follows the language: "25/09" in Portuguese, "09/25" in English.
        day?.formatted(.dateTime.day(.twoDigits).month(.twoDigits).locale(Self.locale))
    }
}

/// An occurrence plus its position in ``CarouselViewModel/visibleOccurrences``, which the
/// details card's focus (`focusDetailsImmediately`) is indexed by.
private struct IndexedOccurrence: Identifiable {
    /// Its position in ``CarouselViewModel/visibleOccurrences``.
    let index: Int
    /// The occurrence.
    let occurrence: ChoreOccurrence
    
    /// The occurrence's id.
    var id: String { occurrence.id }
}

// MARK: - Suggested order for today

/// "Ordem sugerida" under today's title: the viewer's own chores for today, numbered in the
/// order the AI suggests, each with why when something has to come first ("Depois de
/// “Cozinhar” (Ana)"). Only a suggestion: the cards below keep their usual order.
private struct TodayOrderBox: View {
    let steps: [TodayChoreOrder.Step]

    /// Closed with the chevron; remembered on this device, so it stays as the person left it.
    @AppStorage("todayOrderBoxCollapsed") private var isCollapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The title row opens or closes the box (chevron on the right, like the day titles).
            Button {
                // No haptic, like the day titles.
                withAnimation(.snappy) { isCollapsed.toggle() }
            } label: {
                HStack {
                    Label {
                        Text("Ordem sugerida para hoje")
                    } icon: {
                        Image(systemName: "sparkles")
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.subTitleGray)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(Text(verbatim: isCollapsed ? L10n.tr("recolhido") : L10n.tr("expandido")))
            .voiceOverHint(isCollapsed ? L10n.tr("Toque duas vezes para expandir.") : L10n.tr("Toque duas vezes para recolher."))

            if !isCollapsed {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(verbatim: "\(index + 1)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.chorePurple)
                        .frame(width: 18, alignment: .leading)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.titleGray)

                        if let note = step.note {
                            Text(note)
                                .font(.system(size: 13))
                                .foregroundStyle(.subTitleGray)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .transition(.opacity)
            }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.aiOpacity, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.chorePurple.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [6, 4]))
        )
    }
}
