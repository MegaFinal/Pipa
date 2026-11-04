//
//  Calendar.swift
//  Cognitive-Work
//
//  Created by anshu Li on 23/09/26.
//

import SwiftUI

/// A month-style calendar for a range of days (the cycle).
///
/// Days outside the range or before `earliestSelectable` are grey and can't be tapped.
/// Each day's background shows how busy it is, using `opacityForDay`.
struct CustomCalendar: View {
    /// The selected day, or `nil`. Tapping it again clears it.
    @Binding var selectedDate: Date?
    /// The days that can be picked (the end is not included).
    let window: Range<Date>
    /// How strong each day's background is (0 = no background). Used to show how busy a day is.
    let opacityForDay: (Date) -> Double
    /// Extra days to show as selected (e.g. other days of a chore).
    var highlightedDays: [Date] = []
    /// The first day that can be picked. Defaults to today.
    var earliestSelectable: Date? = nil   // days before this are shown grey and can't be tapped
    /// If set, only these days can be picked.
    var selectableDays: Set<Date>? = nil
    /// If set, called on tap instead of changing `selectedDate`.
    var onTapDay: ((Date) -> Void)? = nil
    
    /// Computed (not stored) so it follows a language change without recreating the view.
    private var daysOfWeek: [String] { Date.capitalizedFirstLettersOfWeekdays }
    /// Seven equal columns, one per weekday.
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    /// The calendar used for all date math.
    private let calendar = Calendar.current
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // MARK: - Month title, weekday letters and day grid
            header
                .padding(5)
            weekdayRow
            dayGrid
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .foregroundStyle(Color.gray.opacity(0.08))
        )
    }
    
    // MARK: - Data

    /// Every day to display in the grid: from the start of the week containing the window's first day,
    /// to the end of the week containing the window's last day.
    private var gridDays: [Date] {
        let lastDay = calendar.date(byAdding: .day, value: -1, to: window.upperBound) ?? window.lowerBound

        // Pad backwards from the week of the first day to the start of the week
        let startOffset = (calendar.component(.weekday, from: window.lowerBound) - Date.firstDayOfWeek + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -startOffset, to: window.lowerBound) else { return [] }

        // Pad forwards from the week of the last day to the end of the week
        let endOffset = 6 - (calendar.component(.weekday, from: lastDay) - Date.firstDayOfWeek + 7) % 7
        guard let gridEnd = calendar.date(byAdding: .day, value: endOffset, to: lastDay) else { return [] }

        var days: [Date] = []
        var day = gridStart
        while day <= gridEnd {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }
    
    // MARK: - Header
    
    /// The month (and year) of the range, e.g. "Março - Abril 2026".
    private var headerTitle: String {
        let first = window.lowerBound
        let last = calendar.date(byAdding: .day, value: -1, to: window.upperBound) ?? first
         
        let firstYear = calendar.component(.year, from: first)
        let lastYear = calendar.component(.year, from: last)
         
        if firstYear != lastYear {
            // Cross-year
            return "\(monthName(first)) \(firstYear) - \(monthName(last)) \(lastYear)"
        }
        if first.monthInt != last.monthInt {
            // Cross-month
            return "\(monthName(first)) - \(monthName(last)) \(firstYear)"
        }
        // Same month
        return "\(monthName(first)) \(firstYear)"
    }
    
    /// The full month name in the app's language.
    private func monthName(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).locale(L10n.locale))
            .capitalized(with: L10n.locale)
    }
    
    // MARK: - Subviews
    
    /// The month title.
    private var header: some View {
        Text(headerTitle)
            .font(.system(size: 16))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityAddTraits(.isHeader)
    }
    
    /// The weekday letters on top of the grid.
    private var weekdayRow: some View {
        HStack {
            ForEach(daysOfWeek.indices, id: \.self) { index in
                Text(daysOfWeek[index])
                    .font(.system(size: 15))
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.black.opacity(0.3))
            }
        }
        // Each day already says its weekday.
        .accessibilityHidden(true)
    }
    
    /// The grid of day cells.
    private var dayGrid: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(gridDays, id: \.self) { day in
                let normalizedDay = day.startOfDay
                let today = Calendar.current.startOfDay(for: Date())
                let inWindow = window.contains(normalizedDay) && normalizedDay >= (earliestSelectable ?? today)
                let isAllowedBySlots = selectableDays?.contains(normalizedDay) ?? true
                let selectable = inWindow && isAllowedBySlots
                let highlighted = selectable && (isSelected(normalizedDay) || isHighlighted(normalizedDay))
                
                DayCell(
                    day: day,
                    opacity: selectable ? opacityForDay(day) : 0,
                    isSelectable: selectable,
                    isSelected: highlighted,
                    action: {
                        guard selectable else { return }
                        if let onTapDay {
                            onTapDay(normalizedDay)
                        } else {
                            select(normalizedDay)
                        }
                    }
                )
            }
        }
    }
        
    /// The selected date written out, or "Nenhuma data selecionada".
    private var selectedDateLabel: some View {
        if let selectedDate {
            Text(selectedDate.formatted(
                .dateTime
                    .weekday(.wide).day().month(.wide).year()
                    .locale(L10n.locale))
            )
            .font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity, alignment: .center)
        } else {
            Text("Nenhuma data selecionada")
                .font(.system(size: 15))
                .italic()
                .foregroundStyle(.gray)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
    
    // MARK: - Actions
    
    /// Whether `day` is the selected day.
    private func isSelected(_ day: Date) -> Bool {
        guard let selectedDate else { return false }
        return calendar.isDate(selectedDate, inSameDayAs: day)
    }
    
    /// Selects `day`, or clears it if it was already selected.
    private func select(_ day: Date) {
        // Tapping an already selected date again = deselects it
        selectedDate = isSelected(day) ? nil : day.startOfDay
    }
    
    /// Whether `day` is one of `highlightedDays`.
    private func isHighlighted(_ day: Date) -> Bool {
        highlightedDays.contains { calendar.isDate($0, inSameDayAs: day) }
    }
}

// MARK: - Previews

/// Preview wrapper that keeps the selected day in `@State`.
private struct ChoreDatePickerPreview: View {
    /// The days that can be picked.
    let window: Range<Date>
    /// The selected day.
    @State private var selected: Date?
    
    var body: some View {
        CustomCalendar(
            selectedDate: $selected,
            window: window,
            // Mock data: simulates varying workload volumes (0 = no chores, no background)
            opacityForDay: { day in
                let d = Calendar.current.component(.day, from: day)
                if d % 3 == 0 { return 0.9 }
                if d % 2 == 0 { return 0.4 }
                return 0
            }
        )
    }
}

/// Standard case: 15 days starting today
#Preview("15 Days Starting Today") {
    let today = Calendar.current.startOfDay(for: Date())
    let end = Calendar.current.date(byAdding: .day, value: 15, to: today)!
    return ChoreDatePickerPreview(window: today..<end)
}

/// Cross-month window: starts 5 days before the end of the current month, spanning into the next
#Preview("Cross-Month Window") {
    let calendar = Calendar.current
    let start = calendar.date(byAdding: .day, value: -4, to: Date.now.endOfMonth)!
    let startOfDay = calendar.startOfDay(for: start)
    let end = calendar.date(byAdding: .day, value: 15, to: startOfDay)!
    return ChoreDatePickerPreview(window: startOfDay..<end)
}

#Preview("Cross-Year: 15 Days Starting December 20th") {
    let calendar = Calendar.current
    let start = calendar.date(from: DateComponents(year: 2026, month: 12, day: 20))!
    let end = calendar.date(byAdding: .day, value: 15, to: start)!
    return ChoreDatePickerPreview(window: start..<end)
}
