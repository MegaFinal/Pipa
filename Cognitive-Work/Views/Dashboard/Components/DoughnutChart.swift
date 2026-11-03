//
//  DoughnutChart.swift
//  Cognitive-Work
//
//  Created by Isabela Hissa Pinto on 01/10/26.
//

import SwiftUI
import Charts

/// One slice of ``DoughnutChart``.
struct Slice: Identifiable {
    /// Identifier for the chart.
    let id = UUID()
    /// How many chores the slice stands for.
    let size: Int
    /// The slice's color.
    let color: Color
}

/// The "Hoje" card of the progress tab: a doughnut chart of today's chores done, with the
/// percentage in the middle and "X de Y" below.
struct DoughnutChart: View {
    /// The progress tab's view model (gives today's numbers).
    @Binding var viewModel: DashboardViewModel
    
    /// "X de Y" (done of total).
    private var completedAndAllChores: String {
        L10n.tr("\(viewModel.completedToday) de \(viewModel.totalToday)")
    }
    
    /// Two slices: done (blue) and still to do (light gray).
    var slices: [Slice] {
        let done = Slice(size: viewModel.completedToday, color: .choreBlue)
        let all = Slice(size: viewModel.totalToday - viewModel.completedToday, color: Color.gray.opacity(0.15))
        
        return [done, all]
    }
    
    var body: some View {
        // MARK: - "Hoje", doughnut with the percentage, and "X de Y"
        VStack(spacing: 8) {
            // Leading-aligned across the card; wraps if the language needs more room.
            Text("Hoje")
                .font(.system(size: 17))
                .fontWeight(.semibold)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            ZStack {
                Text(viewModel.completionText)
                    .font(.system(size: 20))
                    .fontWeight(.black)
                
                Chart(slices) { slice in
                    SectorMark(
                        angle: .value("Chores", slice.size),
                        innerRadius: .ratio(0.64)
                    )
                    .foregroundStyle(slice.color)
                }
                .frame(width: width * 0.27, height: height * 0.126)
            }
            
            Text(completedAndAllChores)
                .font(.system(size: 15))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(width: width * 0.437)
        .frame(minHeight: height * 0.21, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .foregroundStyle(Color(.systemGray6).opacity(0.5))
        )
        // The card reads as one element: "Hoje, 3 de 4 tarefas concluídas, 75%".
        .accessibilityElement(children: .ignore)
        .voiceOverLabel(L10n.tr("Hoje"))
        .voiceOverValue(viewModel.todayAccessibilityValue)
    }
}

#Preview {
    let vm: DashboardViewModel = {
        let vm = DashboardViewModel()
        vm.completedToday = 3
        vm.totalToday = 4
        vm.completionProgress = 0.75
        vm.completionText = "75%"
        return vm
    }()
    
    DoughnutChart(viewModel: .constant(vm))
}
