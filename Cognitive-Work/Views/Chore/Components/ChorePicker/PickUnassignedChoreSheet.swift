//
//  PickUnassignedChoreSheet.swift
//  Cognitive-Work
//
//  Created by anshu Li on 25/09/26.
//

import SwiftUI

/// A popup card to take a chore that has no owner: the user picks the day(s) they will do it
/// on a calendar and confirms. Daily chores pick several days; others pick one.
struct PickUnassignedChoreCard: View {
    /// The chore without owner being taken.
    let item: CarouselViewModel.UnassignedItem
    /// Gives the dates, the busy-day shading and saves the pick.
    @Bindable var carouselViewModel: CarouselViewModel
    
    /// The occurrences to take, each with its day and whether it's included.
    @State private var slots: [CarouselViewModel.WeeklyPickSlot] = []
    /// The slot whose day the calendar edits (non-daily chores).
    @State private var activeSlot = 0
    /// `true` while saving (spinner on the confirm button).
    @State private var isSaving = false
    /// Shows the "couldn't save" message.
    @State private var didFail = false
    
    /// The chore being taken.
    private var chore: ChoreModel { item.chore }
    /// The range of days the picker allows.
    private var window: Range<Date> { carouselViewModel.pickerWindow }
    /// Whether it's a daily chore (several days can be picked).
    private var isDaily: Bool { chore.frequency == .daily }
    /// Whether it's a weekly chore (only days of its week can be picked).
    private var isWeekly: Bool { chore.frequency == .weekly }
    
    /// The room's name, or "Sem cômodo".
    private var roomName: String {
        carouselViewModel.getRoom(for: chore)?.name.localizedDefault ?? L10n.tr("Sem cômodo")
    }
    
    /// The room's color, or gray.
    private var roomColor: Color {
        carouselViewModel.getRoom(for: chore)?.color.uiColor ?? .gray
    }
    
    /// The day the occurrence was planned for, for recurring chores.
    private var originalDay: Date? {
        if case .recurring(let assignment) = item.choreType { return assignment.day }
        return nil
    }
    
    /// The days the calendar lets the user pick: the chore's week for weekly chores, the picker
    /// range for daily chores, and the whole cycle otherwise.
    private var effectiveWindow: Range<Date> {
        let calendar = Calendar.current
        let cycle = carouselViewModel.cycleWindow ?? window
        
        if isWeekly {
            let base = originalDay
            ?? slots.first(where: { $0.date != nil })?.date
            ?? window.lowerBound
            
            let startOfWeek = calendar.date(
                from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: base)
            ) ?? base
            
            if let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek) {
                let clampedStart = max(startOfWeek, cycle.lowerBound)
                let clampedEnd = min(endOfWeek, cycle.upperBound)
                
                if clampedStart < clampedEnd {
                    return clampedStart..<clampedEnd
                }
            }
        }
        
        if isDaily { return window }
        return cycle
    }
    
    /// The days picked so far.
    private var includedDates: [Date] {
        slots.compactMap { $0.included ? $0.date : nil }
    }
    
    /// Whether at least one day is picked.
    private var canConfirm: Bool { !includedDates.isEmpty }
    
    var body: some View {
        VStack(spacing: 8) {
            // MARK: - Close, title and confirm
            header
                .padding(.bottom)
            
            // MARK: - Chore, question, "take all" switch and calendar
            choreDetail
            
            calendarText
            
            if isDaily {
                Toggle(isOn: allDailyIncluded) {
                    Text("Pegar todas as tarefas diárias")
                        .font(.system(size: 15))
                        .foregroundStyle(.black)
                }
                .toggleStyle(.switch)
                .voiceControlNames([L10n.tr("Pegar todas as tarefas diárias"), L10n.tr("Pegar todas")])
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            CustomCalendar(
                selectedDate: isDaily ? Binding<Date?>.constant(nil) : activeDateBinding,
                window: effectiveWindow,
                opacityForDay: { date in carouselViewModel.loadOpacity(on: date, in: window) },
                highlightedDays: includedDates,
                selectableDays: isDaily ? Set(slots.compactMap { $0.date }) : nil,
                onTapDay: isDaily ? { day in toggleDailySlot(day) } : nil
            )
            
            // MARK: - Error message
            if didFail {
                Text("Não foi possível salvar. Tente novamente.")
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        // The height follows the content: a calendar with more weeks makes the popup taller.
        .frame(width: width * 0.88)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 31))
        .shadow(color: .black.opacity(0.2), radius: 25, x: 0, y: 8)
        .task {
            slots = carouselViewModel.initialPickSlots(for: item)
            activeSlot = slots.firstIndex { $0.isDateEditable } ?? 0
        }
        // MARK: - Popup accessibility: keeps VoiceOver inside it; the escape gesture closes it.
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) {
            carouselViewModel.dismissPickCard()
        }
        .onChange(of: didFail) { _, failed in
            if failed { VoiceOver.announce(L10n.tr("Não foi possível salvar. Tente novamente.")) }
        }
    }
    
    // MARK: - Calendar binding
    
    /// Connects the calendar to the active slot's day.
    private var activeDateBinding: Binding<Date?> {
        Binding(
            get: { slots.indices.contains(activeSlot) ? slots[activeSlot].date : nil },
            set: { newValue in
                guard slots.indices.contains(activeSlot) else { return }
                slots[activeSlot].date = newValue
                slots[activeSlot].included = newValue != nil
            }
        )
    }
    
    /// Drives, and reflects, whether every open daily slot is selected.
    private var allDailyIncluded: Binding<Bool> {
        Binding(
            get: { !slots.isEmpty && slots.allSatisfy { $0.included } },
            set: { newValue in
                for index in slots.indices { slots[index].included = newValue }
            }
        )
    }
    
    /// Picks or unpicks a daily slot when its day is tapped.
    private func toggleDailySlot(_ day: Date) {
        let calendar = Calendar.current
        guard let index = slots.firstIndex(where: {
            $0.date.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        }) else { return }
        slots[index].included.toggle()
    }
    
    // MARK: - Subviews
    
    /// The close button, the title and the confirm button.
    private var header: some View {
        HStack {
            closeButton
            
            Spacer()
            
            Text("Selecionar dia")
                .font(.system(size: 16))
                .foregroundStyle(.black)
                .accessibilityAddTraits(.isHeader)
            
            Spacer()
            
            confirmButton
        }
    }
    
    /// The room, the chore's name and its tags.
    private var choreDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(roomName)
                .font(.system(size: 15))
                .foregroundStyle(.black)
            
            Text(chore.localizedName)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.black)
            
            ChoreTagsRow(chore: chore, spacing: 16, horizontalPadding: 6, verticalPadding: 1.5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .foregroundStyle(Color.gray.opacity(0.08))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(chore.localizedName), \(roomName), \(carouselViewModel.accessibilityTagsText(for: chore))"))
    }
    
    /// "Quando você deseja realizar esta tarefa?" and its note.
    private var calendarText: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quando você deseja realizar esta tarefa?")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.black)
                .accessibilityAddTraits(.isHeader)
            
            Text("Esta escolha será apenas para a divisão de tarefas atual")
                .font(.system(size: 15))
                .foregroundStyle(.gray)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    /// Closes the card without saving.
    private var closeButton: some View {
        Button {
            carouselViewModel.dismissPickCard()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.black)
                .frame(width: 35, height: 35)
                .glassEffect(in: .circle)
        }
        .buttonStyle(.plain)
        .voiceOverLabel(L10n.tr("Fechar"))
        .voiceControlNames([L10n.tr("Fechar"), L10n.tr("Cancelar")])
    }
    
    /// Saves the pick, gives the points and closes the card (or shows the error).
    private var confirmButton: some View {
        Button {
            Task {
                isSaving = true
                didFail = false
                
                let success = await carouselViewModel.confirmPick(item, slots: slots)
                
                if success {
                    _ = await ScoreManager.shared.assignScoreForMyUser(
                        score: ScoreValues.unassignedChorePicked.points
                    )
                    carouselViewModel.dismissPickCard()
                    VoiceOver.announce(L10n.tr("Tarefa adicionada às suas tarefas"))
                } else {
                    isSaving = false
                    didFail = true
                }
            }
        } label: {
            Group {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 35, height: 35)
            .background(Color.blue)
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canConfirm || isSaving)
        .opacity(canConfirm ? 1.0 : 0.5)
        .voiceOverLabel(isSaving ? L10n.tr("Salvando") : L10n.tr("Confirmar"))
        .voiceControlNames([L10n.tr("Confirmar"), L10n.tr("Salvar"), L10n.tr("OK")])
        .voiceOverHint(canConfirm ? "" : L10n.tr("Escolha pelo menos um dia para confirmar."))
    }
}
