//
//  DashboardViewModel+Accessibility.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 09/10/26.
//

import SwiftUI
import Accessibility

// MARK: - Shared formatting

/// Formatting helpers for the charts' VoiceOver labels, always in the app's current language.
enum ChartA11y {

    /// "40%" in the app's language.
    static func percent(_ fraction: Double) -> String {
        let clamped = fraction.isFinite ? fraction : 0
        return clamped.formatted(.percent.precision(.fractionLength(0)).locale(L10n.locale))
    }

    /// "segunda-feira, 5 de outubro" / "Monday, October 5".
    static func weekdayDayMonth(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(L10n.locale))
    }

    /// "5 de outubro" / "October 5".
    static func dayMonth(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).locale(L10n.locale))
    }

    /// "Cozinha, Banheiro e Sala" / "Kitchen, Bathroom and Living room".
    static func list(_ items: [String]) -> String {
        items.formatted(.list(type: .and).locale(L10n.locale))
    }

    /// "15 minutos".
    static func minutes(_ value: Double) -> String {
        L10n.tr("\(Int(value.rounded())) minutos")
    }

    /// "Lavar a louça, Cozinha, tarefa curta, 15 minutos": what a chore bar says.
    static func choreDescription(name: String, room: String?, minutes: Double) -> String {
        let tier = ChoreDurationTier.from(minutes: minutes)
        var parts = [name]
        if let room, !room.isEmpty { parts.append(room) }
        parts.append(L10n.tr("tarefa \(tier.displayText)"))
        if minutes > 0 { parts.append(Self.minutes(minutes)) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Dashboard

extension DashboardViewModel {

    /// "3 de 4 tarefas concluídas, 75%" for the "Hoje" doughnut.
    var todayAccessibilityValue: String {
        guard totalToday > 0 else { return L10n.tr("Nenhuma tarefa para hoje") }
        return L10n.tr("\(completedToday) de \(totalToday) tarefas concluídas, \(completionText)")
    }

    /// How the user's share compares to the ideal one; mirrors the bar's color scale.
    var cognitiveShareStatusText: String? {
        let ideal = idealCognitiveShare
        guard ideal > 0 else { return nil }
        let share = myCognitiveShare
        if share < ideal * 0.5 { return L10n.tr("bem abaixo do ideal") }
        if share < ideal { return L10n.tr("abaixo do ideal") }
        if share <= ideal * 1.2 { return L10n.tr("dentro do ideal") }
        if share <= ideal * 1.5 { return L10n.tr("acima do ideal") }
        return L10n.tr("bem acima do ideal")
    }

    /// "40%, ideal 50%, abaixo do ideal" for the house-division bar.
    var cognitiveShareAccessibilityValue: String {
        var parts = [myCognitiveShareText]
        if idealCognitiveShare > 0 && idealCognitiveShare < 1 {
            parts.append(L10n.tr("ideal \(idealCognitiveShareText)"))
        }
        if let status = cognitiveShareStatusText { parts.append(status) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Chart descriptor

/// Audio-graph descriptor for a simple bar chart: one value per category (room, resident).
nonisolated struct CategoryChartDescriptor: AXChartDescriptorRepresentable {

    /// Title read by VoiceOver's chart rotor.
    let title: String

    /// Optional sentence summarising the chart.
    let summary: String?

    /// Name of the category axis ("Cômodo", "Morador").
    let categoryAxisTitle: String

    /// Name of the value axis ("Tarefas", "Minutos").
    let valueAxisTitle: String

    /// One bar per category.
    let points: [(label: String, value: Double)]

    /// Builds the chart description VoiceOver uses for its audio graph.
    func makeChartDescriptor() -> AXChartDescriptor {
        let categories = points.map(\.label)
        let maxValue = max(points.map(\.value).max() ?? 0, 1)

        let xAxis = AXCategoricalDataAxisDescriptor(
            title: categoryAxisTitle,
            categoryOrder: categories
        )
        let yAxis = AXNumericDataAxisDescriptor(
            title: valueAxisTitle,
            range: 0...maxValue,
            gridlinePositions: []
        ) { value in
            "\(Int(value.rounded()))"
        }
        let series = AXDataSeriesDescriptor(
            name: title,
            isContinuous: false,
            dataPoints: points.map { AXDataPoint(x: $0.label, y: $0.value) }
        )
        return AXChartDescriptor(
            title: title,
            summary: summary,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}
