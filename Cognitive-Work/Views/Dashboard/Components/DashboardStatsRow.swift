//
//  DashboardStatsRow.swift
//  Cognitive-Work
//

import SwiftUI

/// Today at a glance on the progress tab: average time, chores to do, how much is done and the
/// coin balance, in a 2 × 2 grid.
///
/// The same numbers as the cards on top of the chores tab (plus the coins of the rewards tab),
/// drawn like the other cards of this screen (light gray, 20-point corners).
struct DashboardStatsRow: View {
    /// Today's chore statistics, or `nil` while they load.
    let dashboard: DashboardModel?
    /// The member's coin balance.
    let coins: Int

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                DashboardStatCard(
                    title: "Tempo médio",
                    value: dashboard?.totalTimeFormatted ?? "0h00",
                    systemImage: "clock",
                    tint: RoomColor.blue.uiColor
                )
                DashboardStatCard(
                    title: "A fazer",
                    value: L10n.tr("\(dashboard?.toDo ?? 0) tarefas"),
                    systemImage: "checklist",
                    tint: RoomColor.orange.uiColor
                )
            }
            GridRow {
                DashboardStatCard(
                    title: "Concluído",
                    value: (dashboard?.completionPercentage ?? 0)
                        .formatted(.percent.precision(.fractionLength(0)).locale(L10n.locale)),
                    systemImage: "checkmark.circle",
                    tint: RoomColor.green.uiColor
                )
                DashboardStatCard(
                    title: "Moedas",
                    value: coins.formatted(.number.locale(L10n.locale)),
                    systemImage: "coloncurrencysign.circle.fill",
                    tint: RoomColor.yellow.uiColor
                )
            }
        }
        // Lets each row take the height of its taller card (the cards fill it).
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .voiceOverLabel(L10n.tr("Progresso do dia"))
    }
}

/// One statistic: a colored icon, the value and what it is.
private struct DashboardStatCard: View {
    let title: LocalizedStringKey
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.15), in: .circle)
                .accessibilityHidden(true)

            Text(value)
                .font(.custom("Alan Sans", size: 20))
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.subTitleGray)
                .lineLimit(2)
        }
        .padding(12)
        // Both cards of a row take the height of the taller one.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .foregroundStyle(Color(.systemGray6).opacity(0.5))
        )
        // "Tempo médio, 1h30" as one element.
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    DashboardStatsRow(dashboard: nil, coins: 42)
}
