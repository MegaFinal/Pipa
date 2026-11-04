//
//  ChoreDetailsInfo.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 26/10/26.
//

import SwiftUI

/// Middle of the details card: description, room and checklist. Scrolls when it doesn't fit.
struct ChoreDetailsInfo: View {
    @Bindable var viewModel: ChoreDetailsViewModel
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                Text(viewModel.chore.localizedDescription)
                    .font(.system(size: 14))
                
                roomRow
                checklistHeader
                checklist
            }
            .frame(width: width * 0.75, alignment: .leading)
        }
        .frame(width: width * 0.75)
    }
    
    private var roomRow: some View {
        HStack {
            Text("Cômodo")
                .font(.system(size: 15))
                .fontWeight(.semibold)
            
            Spacer()
            
            CapsuleTag(
                tagName: viewModel.room?.name.localizedDefault ?? L10n.tr("Sem cômodo"),
                tagColor: viewModel.room?.color.uiColor ?? .gray,
                horizontalPadding: 10.0,
                verticalPadding: 1.5
            )
        }
        .accessibilityElement(children: .ignore)
        .voiceOverLabel(L10n.tr("Cômodo: \(viewModel.carouselViewModel.accessibilityRoomName(for: viewModel.chore))"))
    }
    
    private var checklistHeader: some View {
        HStack {
            Text("Checklist")
                .font(.system(size: 15))
                .fontWeight(.semibold)
            
            Spacer()
            
            Text(viewModel.occurrenceDate?.formatted(.dateTime.day().month(.twoDigits).year().locale(L10n.locale))
                 ?? L10n.tr("Sem data definida"))
                .font(.system(size: 12))
        }
        .accessibilityElement(children: .ignore)
        .voiceOverLabel(viewModel.checklistAccessibilityLabel)
        .accessibilityAddTraits(.isHeader)
    }
    
    private var checklist: some View {
        VStack(alignment: .leading, spacing: 5) {
            if viewModel.isLoadingChecklist {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .voiceOverLabel(L10n.tr("Carregando checklist"))
            }
            ForEach($viewModel.checkList, id: \.id) { $item in
                ChecklistItemButton(item: $item)
            }
        }
    }
}

/// One checklist item; tapping toggles whether it's done.
private struct ChecklistItemButton: View {
    @Binding var item: CheckItemModel
    
    var body: some View {
        Button {
            HapticsManager.selection()
            Task {
                await item.toggle()
                VoiceOver.announce(item.isDone ? L10n.tr("Concluído") : L10n.tr("Pendente"))
            }
        } label: {
            HStack {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(item.isDone ? .black : .gray)
                    .font(.system(size: 17, weight: .semibold))
                
                Text(item.name.localizedDefault)
                    .strikethrough(item.isDone, color: .gray)
                    .foregroundColor(item.isDone ? .gray : .black)
                    .font(.system(size: 13))
                    .multilineTextAlignment(.leading)
            }
        }
        .buttonStyle(.plain)
        .voiceOverLabel(item.name.localizedDefault)
        .voiceOverValue(item.isDone ? L10n.tr("Concluído") : L10n.tr("Pendente"))
        .voiceOverHint(L10n.tr("Toque duas vezes para alternar."))
    }
}
