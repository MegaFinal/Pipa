//
//  UserScheduleCard.swift
//  Cognitive-Work
//
//  Created by Carolina Sun on 02/10/26.
//

import Foundation
import SwiftUI
import CloudKit

// MARK: - Card

/// A card that shows the current user's chores as stacked bars, one column per day.
///
/// Each bar is one chore. Its **height** comes from the chore's duration tier
/// (``DailyUsageEntry/tier``) and its **color** from the room the chore belongs to.
/// Tapping a bar opens a popover with the chore's details.
/// > Note: With the default of 7 days the chart fits a 361 pt wide card. A larger
/// > `daysToShow` scrolls horizontally.
struct UserScheduleCard: View {
    
    /// The resident the card belongs to. Used for the avatar and the popover.
    let user: UserModel?
    
    /// The user's entries; entries from other residents should be filtered out beforehand.
    let entries: [DailyUsageEntry]
    
    /// Fallback first day, used only when there are no entries (the chart starts on the first day with chores).
    let startDate: Date
    
    /// Rooms listed in the legend.
    let roomCaption: [RoomModel]
    
    /// Resolves the chore an entry refers to.
    let chore: (DailyUsageEntry) -> ChoreModel?
    
    /// Resolves the room a chore belongs to.
    let room: (ChoreModel) -> RoomModel?
    
    /// Total number of days to display (should match the division interval)
    let daysToShow = 14
    
    /// The entry whose popover is currently open, if any.
    @State private var selectedEntry: DailyUsageEntry?
    
    // MARK: Layout
    
    /// Screen the Figma was drawn for (iPhone 16). Every measure below is written in Figma
    /// points and converted with ``designWidth(_:)`` / ``designHeight(_:)``, so the card keeps
    /// the same proportions on any iPhone.
    private static let referenceScreen = CGSize(width: 393, height: 852)
    
    /// Converts a horizontal Figma measure into this device's points.
    private func designWidth(_ value: CGFloat) -> CGFloat {
        width * value / Self.referenceScreen.width
    }
    
    /// Converts a vertical Figma measure into this device's points.
    private func designHeight(_ value: CGFloat) -> CGFloat {
        height * value / Self.referenceScreen.height
    }
    
    /// Number of day columns that fit in the card at once; the rest scroll horizontally.
    static let visibleDays: CGFloat = 7
    
    /// Bar height for a `heightRatio` of 1, before scaling. Only the *ratio* between bars
    /// matters, since everything is scaled to fill the chart.
    static let baseBarHeight: CGFloat = 80
    
    /// Gap between two bars of the same day (not scaled).
    static let barSpacing: CGFloat = 4
    
    /// Fixed height of the weekday label, so the space left for the bars is known exactly.
    static let weekdayLabelHeight: CGFloat = 20
    
    /// Gap between the weekday label and the bars.
    static let labelToBarsSpacing: CGFloat = 6
    
    /// Factor applied to every bar so the busiest day exactly fills `barAreaHeight`.
    ///
    /// For each day: (area − gaps) / (sum of the bars' natural heights) is the largest scale
    /// that still fits that day. The smallest of those values fits *every* day, and using the
    /// same factor everywhere keeps the bars proportional to each other.
    private func barScale(fitting barAreaHeight: CGFloat) -> CGFloat {
        let calendar = Calendar.current
        let entriesByDay = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.day) }
        
        let scalesThatFit = entriesByDay.values.compactMap { dayEntries -> CGFloat? in
            let barsHeight = dayEntries.reduce(CGFloat(0)) { total, entry in
                total + Self.baseBarHeight * CGFloat(entry.tier.heightRatio)
            }
            guard barsHeight > 0 else { return nil }
            let gaps = Self.barSpacing * CGFloat(dayEntries.count - 1)
            return max(barAreaHeight - gaps, 0) / barsHeight
        }
        
        return scalesThatFit.min() ?? 1
    }
    
    var body: some View {
        // Figma (iPhone 16): card 361 × 476, padding 16 top/bottom and 8 on the sides,
        // 12 between title, chart and legend.
        VStack(alignment: .leading, spacing: designHeight(12)) {
            // MARK: - Title, chart and room legend
            header
            
            chart
            
            RoomScheduleCaption(rooms: roomCaption)
        }
        .padding(.vertical, designHeight(16))
        .padding(.horizontal, designWidth(8))
        // Card size follows the screen. Title and legend take their natural height;
        // the chart gets the rest.
        .frame(width: designWidth(361), height: designHeight(476))
        .background(
            RoundedRectangle(cornerRadius: 20)
                .foregroundColor(Color(.systemGray6).opacity(0.5))
        )
    }
    
    // MARK: Subviews
    
    /// The card's title.
    private var header: some View {
        HStack(alignment: .top) {
            Text("Sua divisão atual")
                .font(.system(size: 22).bold())
                .accessibilityAddTraits(.isHeader)
            
            Spacer()
            
        }
    }
    
    /// The scrollable chart: one column per day, sized to fill the space left in the card.
    private var chart: some View {
        let calendar = Calendar.current
        // The chart starts on the first day that has chores (or on the period start if none).
        let firstDay = entries.map { calendar.startOfDay(for: $0.day) }.min()
            ?? calendar.startOfDay(for: startDate)
        
        // GeometryReader is greedy: it takes all the space the card has left after the
        // title and the legend, and tells us how much that is.
        return GeometryReader { proxy in
            let columnHeight = proxy.size.height
            // The busiest day uses the whole column: its label on top, its bars below.
            let barAreaHeight = max(columnHeight - Self.weekdayLabelHeight - Self.labelToBarsSpacing, 0)
            // Exactly `visibleDays` columns fill the card width on any device.
            let columnWidth = proxy.size.width / Self.visibleDays
            // Computed once here instead of once per column.
            let scale = barScale(fitting: barAreaHeight)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(0..<daysToShow, id: \.self) { offset in
                        if let day = calendar.date(byAdding: .day, value: offset, to: firstDay) {
                            ScheduleDayColumn(
                                day: day,
                                entries: entries.filter { calendar.isDate($0.day, inSameDayAs: day) },
                                selectedEntry: $selectedEntry,
                                barScale: scale,
                                columnHeight: columnHeight,
                                columnWidth: columnWidth,
                                user: user,
                                chore: chore,
                                room: room
                            )
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        // VoiceOver walks the days in order: each weekday reads its full date, then its bars
        // as buttons that open the chore popover.
        .accessibilityElement(children: .contain)
        .voiceOverLabel(chartAccessibilityLabel)
    }
    
    /// "Gráfico da sua divisão, 12 tarefas em 14 dias".
    private var chartAccessibilityLabel: String {
        L10n.tr("Gráfico da sua divisão, \(entries.count) tarefas em \(daysToShow) dias")
    }
}

// MARK: - Day column

/// One day of the chart: the weekday label with the day's chore bars stacked below it.
private struct ScheduleDayColumn: View {
    
    /// The day this column represents.
    let day: Date
    
    /// Entries scheduled on ``day``.
    let entries: [DailyUsageEntry]
    
    /// Shared selection; the popover opens on the bar whose entry equals this value.
    @Binding var selectedEntry: DailyUsageEntry?
    
    /// Factor applied to every bar height (see `UserScheduleCard.barScale(fitting:)`).
    let barScale: CGFloat
    
    /// Full height of the column (label + bars), the same for every day.
    let columnHeight: CGFloat
    
    /// Width of the column; the bar uses most of it.
    let columnWidth: CGFloat
    
    /// The resident shown in the popover.
    let user: UserModel?
    /// Finds the chore of an entry.
    let chore: (DailyUsageEntry) -> ChoreModel?
    /// Finds the room of a chore.
    let room: (ChoreModel) -> RoomModel?
    
    var body: some View {
        VStack(spacing: UserScheduleCard.labelToBarsSpacing) {
            // MARK: - Weekday label
            Text(weekdayText)
                .font(.system(size: 16.35, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(height: UserScheduleCard.weekdayLabelHeight)
                .voiceOverLabel(ChartA11y.weekdayDayMonth(day))
                .accessibilityValue(
                    entries.isEmpty
                        ? L10n.tr("Sem tarefas")
                        : L10n.tr("\(entries.count) tarefas")
                )
            
            // MARK: - The day's bars
            VStack(spacing: UserScheduleCard.barSpacing) {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    bar(for: entry)
                }
            }
        }
        // Same height for every day, content at the bottom: as in the Figma, each weekday
        // label sits right on top of its own bars.
        .frame(width: columnWidth, height: columnHeight, alignment: .bottom)
    }
    
    /// Short, capitalized weekday in the app's language (e.g. "Seg").
    private var weekdayText: String {
        day.formatted(.dateTime.weekday(.abbreviated).locale(L10n.locale))
            .replacingOccurrences(of: ".", with: "")
            .capitalized(with: L10n.locale)
    }
    
    /// A shape that shows a room's ``RoomTextureBackground``, clipped to an outline.
    ///
    /// Delegating to ``RoomTextureBackground`` keeps bars and legend dots identical to the
    /// room cards (same color, pattern and texture opacity). A `nil` room is drawn as plain
    /// gray, matching how unknown rooms are shown elsewhere.
    private struct RoomTexturedShape<S: Shape>: View {
        
        /// The outline to clip to (a rounded rectangle for bars, a circle for legend dots).
        let shape: S
        
        /// The room that provides the color and texture.
        let room: RoomModel?
        
        /// Higher values draw bigger, fewer shapes.
        var zoom: CGFloat = RoomTextureBackground.textureZoom
        
        /// Fixed size of the texture, forwarded to ``RoomTextureBackground``.
        /// Use it so shapes of different sizes show the same artwork scale.
        var fixedSize: CGFloat? = nil
        
        var body: some View {
            if let room {
                RoomTextureBackground(room: room, zoom: self.zoom, fixedSize: fixedSize)
                    .clipShape(shape)
            } else {
                shape.fill(.gray)
            }
        }
    }
    
    /// A binding that is `true` only while `entry` is the selected one.
    private func isPresented(_ entry: DailyUsageEntry) -> Binding<Bool> {
        Binding(
            get: { selectedEntry == entry },
            set: { isShown in
                if !isShown, selectedEntry == entry { selectedEntry = nil }
            }
        )
    }
    
    /// A single tappable bar that presents the chore popover.
    @ViewBuilder
    private func bar(for entry: DailyUsageEntry) -> some View {
        let resolvedChore = chore(entry)
        let resolvedRoom = resolvedChore.flatMap(room)
        let maxBarHeight = UserScheduleCard.baseBarHeight
        
        RoomTexturedShape(
            shape: RoundedRectangle(cornerRadius: 15),
            room: resolvedRoom,
            zoom: 1.5
        )
        // 45 of 50 in the original layout: the bar keeps that share of the column.
        .frame(width: columnWidth * 0.9, height: maxBarHeight * CGFloat(entry.tier.heightRatio) * barScale)
        .contentShape(RoundedRectangle(cornerRadius: 15))
        .onTapGesture {
            selectedEntry = (selectedEntry == entry) ? nil : entry
        }
        // Each bar is a button: "Lavar a louça, Cozinha, tarefa curta, 15 minutos".
        .accessibilityElement()
        .accessibilityLabel(
            ChartA11y.choreDescription(
                name: resolvedChore?.localizedName ?? entry.choreName.localizedDefault,
                room: resolvedRoom?.name.localizedDefault,
                minutes: entry.minutes
            )
        )
        .accessibilityAddTraits(.isButton)
        .voiceOverHint(L10n.tr("Mostra os detalhes da tarefa"))
        .accessibilityAction {
            selectedEntry = (selectedEntry == entry) ? nil : entry
        }
        // Voice Control: "Toque em Lavar a louça" (or the room) instead of the full sentence.
        .voiceControlNames([
            resolvedChore?.localizedName ?? entry.choreName.localizedDefault,
            resolvedRoom?.name.localizedDefault
        ].compactMap { $0 })
        .popover(
            isPresented: isPresented(entry),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .bottom
        ) {
            if let resolvedChore {
                ChorePopOverComponent(chore: resolvedChore, user: user, room: resolvedRoom)
                    .padding()
                    // Keeps a real popover on iPhone instead of a sheet.
                    .presentationCompactAdaptation(.none)
                    .presentationBackground(.white)
                    // Voice Control can't tap outside the popover: "Toque em Fechar" closes it.
                    .accessibilityAddTraits(.isButton)
                    .voiceControlNames([resolvedChore.localizedName, L10n.tr("Fechar")])
                    .voiceOverHint(L10n.tr("Fecha os detalhes da tarefa"))
                    .accessibilityAction { selectedEntry = nil }
                    .accessibilityAction(.escape) { selectedEntry = nil }
            }
        }
    }
}

// MARK: - Room swatch

/// A shape that shows a room's ``RoomTextureBackground``, clipped to an outline.
///
/// Delegating to ``RoomTextureBackground`` keeps bars and legend dots identical to the
/// room cards (same color, pattern and texture opacity). A `nil` room is drawn as plain
/// gray, matching how unknown rooms are shown elsewhere.
private struct RoomTexturedShape<S: Shape>: View {
    
    /// The outline to clip to (a rounded rectangle for bars, a circle for legend dots).
    let shape: S
    
    /// The room that provides the color and texture.
    let room: RoomModel?
    
    /// Higher values draw bigger, fewer shapes.
    var zoom: CGFloat = RoomTextureBackground.textureZoom
    
    var body: some View {
        if let room {
            RoomTextureBackground(room: room, zoom: self.zoom)
                .clipShape(shape)
        } else {
            shape.fill(.gray)
        }
    }
}

// MARK: - Caption

/// A wrapping legend that lists each room with its color.
private struct RoomScheduleCaption: View {
    
    /// Rooms to list.
    let rooms: [RoomModel]
    
    // MARK: - Room dots and names
    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 90), alignment: .leading)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(rooms, id: \.recordID) { room in
                HStack(spacing: 6) {
                    RoomTexturedShape(shape: Circle(), room: room, zoom: 1)
                        .frame(width: 14, height: 14)
                    
                    Text(room.name)
                        .font(.system(size: 15, weight: .light))
                }
            }
        }
        // The swatches only matter visually (each bar already says its room): one summary line.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            L10n.tr("Cômodos na legenda: \(ChartA11y.list(rooms.map { $0.name.localizedDefault }))")
        )
    }
}
