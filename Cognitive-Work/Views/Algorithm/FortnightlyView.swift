//
//  FortnightlyView.swift
//  Cognitive-Work
//
//  Created by anshu Li on 26/08/26.
//

import SwiftUI
import CloudKit

/// The schedule chart of the generated division: a bar chart of who does what each day, a
/// legend, and the details card of the selected chore.
struct FortnightlyView: View {
    /// The house members.
    let users: [UserModel]
    /// Every chore of the house.
    let chores: [ChoreModel]
    
    /// Assignments and rooms already in memory. When both are given nothing is fetched.
    var assignments: [RecurrentAssignmentModel]? = nil
    /// The house's rooms, when already in memory.
    var rooms: [RoomModel]? = nil
    
    /// Builds the chart's data.
    @State private var viewModel = FortnightlyViewModel()
    /// The bar the user selected.
    @State private var selectedEntry: DailyUsageEntry?
    /// The member of the selected bar.
    @State private var selectedUser: UserModel?
    
    /// The explanation under the title.
    let description: LocalizedStringKey = "Dividimos as tarefas escolhidas pelos moradores pensando nas cargas horárias que cada um tem disponível."
    
    var body: some View {
        VStack {
            // MARK: - Title and explanation
            VStack(alignment: .leading, spacing: 20) {
                Text("Escala quinzenal")
                    .bold()
                    .font(.custom("Alan Sans", size: 32, relativeTo: .largeTitle))
                    .foregroundStyle(.titleGray)
                    .accessibilityAddTraits(.isHeader)
                
                VStack(alignment: .leading, spacing: 10) {
                    Text(description)
                    
                    Text("Clique nas tarefas para saber mais.")
                        // VoiceOver users double-tap; the bars carry their own hint.
                        .accessibilityHidden(true)
                }
            }
            .padding(.bottom, 30)
            .foregroundColor(.secondary)
            .frame(width: width * 0.888)
            
            // MARK: - Chart, legend and selected chore
            ScrollView(showsIndicators: false) {
                chart
            }
            
            Spacer()
        }
        .navigationBarBackButtonHidden()
        .padding(.top, 30)
        
    }
    
    /// Loading, error, or the chart with its legend and the selected chore's card.
    private var chart: some View {
        VStack(spacing: 16) {
            if viewModel.isLoading {
                ProgressView("Carregando gráfico...")
            } else if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundColor(.red)
            } else {
                FortnightlyBarChart(
                    users: users,
                    entries: viewModel.usageEntries,
                    startDate: viewModel.startDate,
                    selectedEntry: selectedEntry,
                    onSelect: { entry in
                        select(entry)
                    },
                    selectionInset: 12
                )
                
                legend
                    .padding(.bottom)
                
                if let entry = selectedEntry,
                   let chore = viewModel.chores.first(where: { $0.recordID == entry.choreID }) {
                    ChoreCard(
                        chore: chore,
                        user: selectedUser,
                        room: viewModel.getRoom(for: chore)
                    )
                }
            }
        }
        .task {
            if let assignments, let rooms {
                await viewModel.setup(users: users, chores: chores)
            } else {
                await viewModel.setup(users: users, chores: chores)
            }
            selectInitialEntry()
            if let errorMessage = viewModel.errorMessage {
                VoiceOver.announce(errorMessage)
            }
        }
    }
    
    // MARK: - Selection
    
    /// Selects `entry` (and its member), announcing the change to VoiceOver.
    private func select(_ entry: DailyUsageEntry) {
        let changed = selectedEntry != nil && selectedEntry != entry
        selectedEntry = entry
        selectedUser = viewModel.users.first { $0.recordID == entry.userID }
        // The card below the chart changes out of VoiceOver's focus: say what it now shows.
        if changed {
            VoiceOver.announce(L10n.tr("Detalhes de \(entry.choreName.localizedDefault) abaixo do gráfico"))
        }
    }
    
    /// The screen always opens with the first chore of the first day (the leftmost column,
    /// its topmost bar) selected.
    private func selectInitialEntry() {
        guard selectedEntry == nil,
              let firstDay = viewModel.usageEntries.map(\.day).min(),
              let first = viewModel.usageEntries.first(where: { Calendar.current.isDate($0.day, inSameDayAs: firstDay) })
        else { return }
        
        select(first)
    }
    
    /// The members and their colors.
    private var legend: some View {
        HStack {
            ForEach(Array(viewModel.users.enumerated()), id: \.offset) { index, user in
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
        // Colors only matter visually: every bar already reads its resident's name.
        .accessibilityElement(children: .ignore)
        .voiceOverLabel(L10n.tr("Moradores na legenda: \(ChartA11y.list(viewModel.users.map(\.name)))"))
    }
}

#Preview {
    return FortnightlyView(users: [], chores: [])
}
