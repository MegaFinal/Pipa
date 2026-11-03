//
//  FortnightlyChartRenderView.swift
//  Cognitive-Work
//
//  Created by anshu Li on 01/09/26.
//

import SwiftUI

/// A lightweight view that renders a compact fortnightly bar chart and user legend,
/// optimized for snapshot capture or e-paper hardware display.
struct FortnightlyChartRenderView: View {
    
    /// The list of users displayed in the chart and legend.
    let users: [UserModel]
    
    /// The list of chores tracked in the system.
    let chores: [ChoreModel]
    
    /// The aggregated usage entries used to populate the bar chart.
    let usageEntries: [DailyUsageEntry]
    
    /// The starting date of the chart's visible time window.
    let startDate: Date
    
    /// The content and layout of the render view.
    var body: some View {
        let calendar = Calendar.current
        let tomorrowStartDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: startDate)) ?? startDate
        
        VStack(spacing: 16) {
            // MARK: - Week bar chart (starting tomorrow)
            FortnightlyBarChart(
                users: users,
                entries: usageEntries,
                startDate: tomorrowStartDate,
                onSelect: { _ in },
                scrollEnabled: false,
                daysToShow: 7
            )
             
            // MARK: - Members legend
            legend
        }
        .frame(maxWidth: 350, maxHeight: 200, alignment: .top)
        .clipped()
        // Rendered to an image for the e-paper device; never meant for VoiceOver.
        .accessibilityHidden(true)
    }
    
    /// A helper subview that generates a color-coded legend for each user.
    private var legend: some View {
        HStack {
            ForEach(Array(users.enumerated()), id: \.offset) { index, user in
                HStack {
                    Circle()
                        .frame(width: 14)
                        .foregroundStyle(UserColorPalette.color(for: index))

                    Text(user.name)
                        .font(.system(size: 15))
                        .fontWeight(.light)
                }
            }
        }
    }
}
