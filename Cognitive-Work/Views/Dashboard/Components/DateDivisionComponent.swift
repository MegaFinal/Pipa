//
//  DateDivisionComponent.swift
//  Cognitive-Work
//
//  Created by Isabela Hissa Pinto on 01/10/26.
//

import SwiftUI

/// The "Divisão atual  28 set — 11 out" pill at the top of the progress tab.
struct DateDivisionComponent: View {
    /// The progress tab's view model (gives the period's dates).
    @Binding var viewModel: DashboardViewModel
    
    /// Current division range.
    /// Ex.: "28 set — 11 out"
    private var period: String {
        "\(viewModel.periodStart.shortDayMonth) — \(viewModel.periodFinish.shortDayMonth)"
    }
    
    /// "Divisão atual".
    private var title: some View {
        Text("Divisão atual")
            .font(.system(size: 15))
            .fontWeight(.semibold)
    }
    
    /// The period's dates.
    private var periodText: some View {
        Text(period)
            .font(.system(size: 15))
    }
    
    var body: some View {
        // Title and period side by side when they fit; otherwise stacked on two lines.
        // The pill is only as wide as its text, with a light padding around it.
        ViewThatFits(in: .horizontal) {
            // MARK: - One line when it fits
            HStack(spacing: 6) {
                title
                periodText
            }
            .fixedSize()
            
            // MARK: - Two lines otherwise
            VStack(alignment: .leading, spacing: 2) {
                title
                periodText
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        // MARK: - Gray rounded background hugging the text
        .background(
            Color.gray.opacity(0.2),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        // Pushes the pill to the leading edge (the background was already drawn around it).
        .frame(maxWidth: .infinity, alignment: .leading)
        // One element with the full dates ("Divisão atual, de 28 de setembro a 11 de outubro").
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            L10n.tr("Divisão atual, de \(ChartA11y.dayMonth(viewModel.periodStart)) a \(ChartA11y.dayMonth(viewModel.periodFinish))")
        )
    }
}

#Preview {
    DateDivisionComponent(viewModel: .constant(DashboardViewModel()))
}
