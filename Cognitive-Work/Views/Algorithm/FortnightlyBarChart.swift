//
//  DashboardBarChart.swift
//  Cognitive-Work
//
//  Created by anshu Li on 24/08/26.
//

import SwiftUI
import CloudKit

/// The fortnight bar chart: one column per day, with one colored bar per chore.
///
/// Each bar's color is the member who does the chore and its height is how long the chore takes.
/// Tapping a bar selects it so the screen can show its details.
struct FortnightlyBarChart: View {
    /// The house members (their order picks each bar's color).
    var users: [UserModel]
    /// The chores to draw, one per day and member.
    var entries: [DailyUsageEntry]
    /// The first day of the chart.
    var startDate: Date = Date()
    /// The bar that is selected, if any.
    var selectedEntry: DailyUsageEntry?
    /// Called when a bar is tapped.
    var onSelect: (DailyUsageEntry) -> Void
    /// Whether the chart scrolls sideways. Turn it off to render the whole chart (e.g. to share it).
    var scrollEnabled: Bool = true
    /// How many days (columns) to show.
    var daysToShow: Int = 14
    
    /// Empty space around the columns, so the selection halo isn't cut off.
    var selectionInset: CGFloat = 0
    
    var body: some View {
        let calendar = Calendar.current
        let baseStartDate = calendar.startOfDay(for: startDate)
        
        // MARK: - One column per day
        let content = HStack(alignment: .top, spacing: 0) {
            ForEach(0..<daysToShow, id: \.self) { dayOffset in
                if let day = calendar.date(byAdding: .day, value: dayOffset, to: baseStartDate) {
                    let dayEntries = entries.filter { calendar.isDate($0.day, inSameDayAs: day) }
                    FortnightlyDayUserBar(
                        day: day,
                        entries: dayEntries,
                        users: users,
                        selectedEntry: selectedEntry,
                        onSelect: onSelect
                    )
                }
            }
        }
        // VoiceOver: days in order, bars as buttons, plus an audio graph of minutes per resident.
        .accessibilityElement(children: .contain)
        .voiceOverLabel(L10n.tr("Gráfico da escala quinzenal, \(entries.count) tarefas em \(daysToShow) dias"))
        .accessibilityChartDescriptor(chartDescriptor)
        
        // MARK: - Scrolling or fixed
        let paddedContent = content.padding(selectionInset)
        
        if scrollEnabled {
            ScrollView(.horizontal, showsIndicators: false) {
                paddedContent
            }
        } else {
            paddedContent
        }
    }
    
    /// Total minutes each resident got in the period, for VoiceOver's chart rotor.
    private var chartDescriptor: CategoryChartDescriptor {
        let points = users.map { user -> (label: String, value: Double) in
            let minutes = entries
                .filter { $0.userID == user.recordID }
                .reduce(0) { $0 + $1.minutes }
            return (label: user.name, value: minutes)
        }
        return CategoryChartDescriptor(
            title: L10n.tr("Minutos de tarefas por morador"),
            summary: nil,
            categoryAxisTitle: L10n.tr("Morador"),
            valueAxisTitle: L10n.tr("Minutos"),
            points: points
        )
    }
}

/// One day column: the weekday label on top and that day's bars stacked below.
private struct FortnightlyDayUserBar: View {
    /// The day of this column.
    var day: Date
    /// That day's chores.
    var entries: [DailyUsageEntry]
    /// The house members (used for colors and names).
    var users: [UserModel]
    /// The bar that is selected, if any.
    var selectedEntry: DailyUsageEntry?
    /// Called when a bar is tapped.
    var onSelect: (DailyUsageEntry) -> Void
    
    /// Height of the tallest bar (a long chore).
    private let maxBarHeight: Double = 100
    
    /// Short weekday ("Seg" / "Mon") in the app's language.
    private func weekdayText(for day: Date) -> String {
        day.formatted(.dateTime.weekday(.abbreviated).locale(L10n.locale))
            .replacingOccurrences(of: ".", with: "")
            .capitalized(with: L10n.locale)
    }
    
    /// Two soft rings around the selected bar, in the bar's own color. 
    private func selectionHalo(color: Color, isSelected: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15 + 9)
                .fill(color.opacity(0.2))
                .padding(-9)
            RoundedRectangle(cornerRadius: 15 + 5)
                .fill(color.opacity(0.45))
                .padding(-5)
        }
        .opacity(isSelected ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
    
    var body: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            // MARK: - Weekday label
            Text(weekdayText(for: day))
                .font(.system(size: 16.35))
                .fontWeight(.medium)
                .voiceOverLabel(ChartA11y.weekdayDayMonth(day))
                .accessibilityValue(
                    entries.isEmpty
                        ? L10n.tr("Sem tarefas")
                        : L10n.tr("\(entries.count) tarefas")
                )
            
            // MARK: - Bars (colored by member, sized by chore length)
            if !entries.isEmpty {
                VStack(spacing: 4) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        let userIndex = users.firstIndex(where: { $0.recordID == entry.userID }) ?? (users.isEmpty ? 0 : index % users.count)
                        
                        let barColor = UserColorPalette.color(for: userIndex)
                        let isSelected = entry == selectedEntry
                        
                        RoundedRectangle(cornerRadius: 15)
                            .fill(barColor)
                            .frame(width: 45, height: maxBarHeight * entry.tier.heightRatio)
                            .background { selectionHalo(color: barColor, isSelected: isSelected) }
                            .onTapGesture {
                                onSelect(entry)
                            }
                            // "Ana, Lavar a louça, tarefa curta, 15 minutos", selectable.
                            .accessibilityElement()
                            .voiceOverLabel(accessibilityLabel(for: entry))
                            .accessibilityAddTraits(.isButton)
                            .voiceOverTraits(.isSelected, when: isSelected)
                            .voiceOverHint(L10n.tr("Mostra os detalhes abaixo do gráfico"))
                            .accessibilityAction {
                                onSelect(entry)
                            }
                            // Voice Control: "Toque em Lavar a louça" or "Toque em Ana".
                            .voiceControlNames(inputLabels(for: entry))
                    }
                }
            }
        }
        .frame(width: 55)
    }
    
    /// Short speakable names for Voice Control: the chore, then the resident.
    private func inputLabels(for entry: DailyUsageEntry) -> [String] {
        let user = users.first(where: { $0.recordID == entry.userID })
        return [entry.choreName.localizedDefault, user?.name].compactMap { $0 }
    }
    
    /// Resident first, then the chore: who does what is the point of this chart.
    private func accessibilityLabel(for entry: DailyUsageEntry) -> String {
        let chore = ChartA11y.choreDescription(
            name: entry.choreName.localizedDefault,
            room: nil,
            minutes: entry.minutes
        )
        guard let user = users.first(where: { $0.recordID == entry.userID }) else { return chore }
        return "\(user.name), \(chore)"
    }
}

#Preview {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())

    let user1ID = CKRecord.ID(recordName: "preview-user-1")
    let user2ID = CKRecord.ID(recordName: "preview-user-2")
    let chore1ID = CKRecord.ID(recordName: "preview-chore-1")
    let chore2ID = CKRecord.ID(recordName: "preview-chore-2")

    let user1 = UserModel(
        name: "Você",
        tier: .tier1,
        recordID: user1ID,
        ownerRecordName: "preview-owner-1"
    )
    let user2 = UserModel(
        name: "Alice",
        tier: .tier1,
        recordID: user2ID,
        ownerRecordName: "preview-owner-2"
    )

    let mockEntries: [DailyUsageEntry] = [
        DailyUsageEntry(day: today, userID: user1ID, choreID: chore1ID,
                        minutes: 15.0, choreName: "Lavar a louça"),
        DailyUsageEntry(day: today, userID: user2ID, choreID: chore2ID,
                        minutes: 45.0, choreName: "Varrer a sala"),
        DailyUsageEntry(day: calendar.date(byAdding: .day, value: 1, to: today) ?? today,
                        userID: user2ID, choreID: chore2ID,
                        minutes: 90.0, choreName: "Limpar a casa")
    ]

    FortnightlyBarChart(
        users: [user1, user2],
        entries: mockEntries,
        startDate: today,
        onSelect: { entry in print("Selected: \(entry.choreName)") }
    )
    .frame(height: 200)
}
