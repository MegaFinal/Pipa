//
//  OnboardingDelimiteTime.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 20/08/26.
//

import SwiftUI

/// The step where the user sets how much free time they have for house chores on each day of
/// the week. Also opened from the profile ("Alterar Tempo Livre").
///
/// Each row is an ``OnboardingCustomSliderComponent``; the week is saved on the user and the
/// house before moving on.
struct SelectFreeTimeOnboardingView: View {
    
    // MARK: - Properties
    
    /// State shared by every step of the flow.
    @Binding var viewModel: OnboardingViewModel
    
    /// `true` when opened from the profile: loads the saved week and goes back after saving.
    var isFromSettings: Bool = false
    
    /// Goes back (settings).
    @Environment(\.dismiss) private var dismiss
    
    /// The seven days rendered as rows, each holding its own free-time choice.
    @State var weekOrder = [
        DayOfWeekDTO(name: "Segunda - Feira", nameAbbreviation: "Seg"),
        DayOfWeekDTO(name: "Terça - Feira", nameAbbreviation:"Ter"),
        DayOfWeekDTO(name: "Quarta - Feira", nameAbbreviation: "Qua"),
        DayOfWeekDTO(name: "Quinta - Feira", nameAbbreviation: "Qui"),
        DayOfWeekDTO(name: "Sexta - Feira", nameAbbreviation:"Sex"),
        DayOfWeekDTO(name: "Sábado ", nameAbbreviation: "Sáb"),
        DayOfWeekDTO(name: "Domingo ",nameAbbreviation: "Dom")
    ]
    /// Not used.
    @State var showAllert: Bool = false

    /// The free time was saved on the profile but not on the house yet (see `save()`).
    @State private var showSyncWarning: Bool = false

    /// Becomes true once the saved free time has been fetched (settings only).
    @State private var hasLoadedSavedTime: Bool = false
    
    /// Shows a loading state until the saved data arrives when opened from settings.
    private var isFetchingSavedTime: Bool { isFromSettings && !hasLoadedSavedTime }
    
    /// At least one day needs free time before saving.
    private var canSave: Bool {
        weekOrder.contains(where: { $0.freeTime != .none })
    }
    
    // MARK: - Actions
    
    /// Persists the week and advances (onboarding) or goes back (settings).
    private func save() async {
        viewModel.isLoading = true
        defer { viewModel.isLoading = false }

        guard await viewModel.setAvailableTimeToUser(daysOfWeekDTO: weekOrder) else { return }
        HapticsManager.notify(.success)

        // Saved on the user's profile but not yet on the house's: say so before moving on (the
        // alert's button continues). The sync is retried automatically.
        if viewModel.freeTimeSyncWarning != nil {
            showSyncWarning = true
            return
        }
        await continueAfterSaving()
    }

    /// Goes back (settings) or to the next onboarding step.
    private func continueAfterSaving() async {
        if isFromSettings {
            dismiss()
        } else {
            await viewModel.advanceAfterFreeTime()
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading) {
            // MARK: - Title and description
            OnboardingHeader(
                title: "Quanto tempo você tem para a casa?",
                description: "Arraste em cada dia para definir seu tempo livre para as tarefas da casa",
                containerInset: width * 0.0565
            )
            .padding(.bottom, 20)
            
            // MARK: - Hour scale and one slider per day
            VStack {
                HStack(spacing: width * 0.07) {
                    Spacer()
                    Text("30’")
                    Text("1h")
                    Text("2h")
                    Text("3h")
                    Text("4h")
                    Text("5h")
                }
                .font(.system(size: 16))
                .fontWeight(.medium)
                .padding(.trailing, 12)
                .padding(.top, height * 0.005)
                // The scale is visual only; each day reads its value ("2 horas") itself.
                .accessibilityDecorative()
                
                ForEach($weekOrder, id: \.name) { $day in
                    OnboardingCustomSliderComponent(dayOfWeek: $day, width: width, isLoading: $viewModel.isLoading)
                }
            }
            .padding(.horizontal)
            
            // MARK: - Next / save button
            Spacer()
            HStack {
                Spacer()
                OnboardingProgressButton(width: width * 0.12, height: width * 0.12, text: isFromSettings ? "checkmark" : "chevron.right", isSystemImage: true, isLoading: viewModel.isLoading, isDisabled: !canSave) {
                    Task {
                        await save()
                    }
                }
            }
        }
        .padding(.horizontal, width * 0.0565)
        // MARK: - Spinner while loading the saved week (settings)
        .opacity(isFetchingSavedTime ? 0 : 1)
        .overlay {
            if isFetchingSavedTime {
                ProgressView()
                    .controlSize(.large)
                    .accessibilityLabel(Text(L10n.tr("Carregando")))
            }
        }
        // MARK: - Back button (disabled while saving)
        .navigationBarBackButtonHidden(!isFromSettings || viewModel.isLoading)
        .toolbar {
            // While saving, the system back button is hidden; a disabled one takes its place.
            if isFromSettings && viewModel.isLoading {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(true)
                    .accessibilityLabel(Text(L10n.tr("Voltar")))
                    .voiceControlNames([L10n.tr("Voltar")])
                }
            }
        }
        .onboardingBackButton(viewModel: viewModel, isHidden: isFromSettings)
        .hidesTabBar()
        // MARK: - Error and "saved only on your profile" alerts
        .alert("Não deu para salvar seus horários", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Salvo no seu perfil", isPresented: $showSyncWarning) {
            Button("OK") {
                viewModel.freeTimeSyncWarning = nil
                Task {
                    viewModel.isLoading = true
                    defer { viewModel.isLoading = false }
                    await continueAfterSaving()
                }
            }
        } message: {
            Text(viewModel.freeTimeSyncWarning ?? "")
        }
        // MARK: - Loads the saved week (settings) or restores the onboarding choice
        .task {
            guard isFromSettings else {
                // Restores a choice already made in onboarding (kept until the house exists).
                if let pending = viewModel.freeTimeToRestore {
                    for (index, minutes) in pending.enumerated() where weekOrder.indices.contains(index) {
                        weekOrder[index].freeTime = FreeTimeEnum(minutes: minutes)
                    }
                }
                return
            }
            
            viewModel.isLoading = true
            let saved = await viewModel.fetchCurrentFreeTime()
            for (index, freeTime) in saved where weekOrder.indices.contains(index) {
                weekOrder[index].freeTime = freeTime
            }
            viewModel.isLoading = false
            hasLoadedSavedTime = true
        }
    }
}

// MARK: - Private subviews

/// A single onboarding row that lets the user define how much free time is
/// available on a given day of the week.
///
/// The row shows the abbreviated day name on the leading edge, a
/// ``FreeTimeSlider`` on the trailing side and, right below it, the full day
/// name followed by the currently selected free-time label. Every selection
/// change is written back to the `dayOfWeek` binding.
private struct OnboardingCustomSliderComponent: View {
    
    // MARK: - Constants
    
    /// Layout values shared by the component, kept here to avoid magic numbers.
    private enum Layout {
        /// Width reserved for the day abbreviation, expressed as a fraction of
        /// the available width.
        static let abbreviationWidthRatio: CGFloat = 0.091
        
        /// Font size of the abbreviated day name.
        static let abbreviationFontSize: CGFloat = 16
        
        /// Font size of the caption line shown below the slider.
        static let captionFontSize: CGFloat = 14
    }
    
    // MARK: - Properties
    
    /// Day being configured. The selected free time is written back to it.
    @Binding var dayOfWeek: DayOfWeekDTO
    
    /// Total width available to the component, used to size its children
    /// proportionally.
    let width: CGFloat
    
    /// Amount of free-time blocks currently selected on the slider.
    @State private var selectedFreeTimeLevel: Int = 0
    
    /// Width reserved for the day abbreviation.
    private var abbreviationWidth: CGFloat {
        width * Layout.abbreviationWidthRatio
    }
    
    /// `true` while saving: the slider can't be changed.
    @Binding var isLoading: Bool
    
    // MARK: - Body
    
    var body: some View {
        HStack(spacing: 10) {
            // MARK: - Day abbreviation
            Text(LocalizedStringKey(dayOfWeek.nameAbbreviation))
                .font(.system(size: Layout.abbreviationFontSize))
                .fontWeight(.medium)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: abbreviationWidth, alignment: .leading)
                .padding(.bottom)
            
            // MARK: - Slider and its caption
            VStack(spacing: 8) {
                FreeTimeSlider(rating: $selectedFreeTimeLevel, isLoading: $isLoading)
                
                caption
            }
        }
        // MARK: - Accessibility
        // VoiceOver: each day is one adjustable element — "Segunda-feira, 2 horas", swipe up or
        // down to change it — instead of a drag-only row.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(L10n.tr(key: dayOfWeek.name.trimmingCharacters(in: .whitespaces))))
        .accessibilityValue(Text(FreeTimeSlider.accessibilityValue(for: selectedFreeTimeLevel)))
        .accessibilityAdjustableAction { direction in
            guard !isLoading else { return }
            switch direction {
            case .increment: selectedFreeTimeLevel = min(6, selectedFreeTimeLevel + 1)
            case .decrement: selectedFreeTimeLevel = max(0, selectedFreeTimeLevel - 1)
            @unknown default: break
            }
        }
        // Voice Control: "Mostrar ações para Segunda-feira" → "Aumentar"/"Diminuir", since it
        // can't swipe-adjust. The visible abbreviation ("Seg") comes first.
        .voiceControlNames([
            L10n.tr(key: dayOfWeek.nameAbbreviation),
            L10n.tr(key: dayOfWeek.name.trimmingCharacters(in: .whitespaces))
        ])
        .accessibilityAction(named: Text(L10n.tr("Aumentar"))) {
            guard !isLoading else { return }
            selectedFreeTimeLevel = min(6, selectedFreeTimeLevel + 1)
        }
        .accessibilityAction(named: Text(L10n.tr("Diminuir"))) {
            guard !isLoading else { return }
            selectedFreeTimeLevel = max(0, selectedFreeTimeLevel - 1)
        }
        // MARK: - Keeps the slider and the day in sync
        .onChange(of: selectedFreeTimeLevel) { _, newValue in
            withAnimation(.easeInOut(duration: 0.1)) {
                dayOfWeek.freeTime = FreeTimeEnum(newValue)
            }
        }
        .onAppear {
            selectedFreeTimeLevel = dayOfWeek.freeTime.level
        }
        .onChange(of: dayOfWeek.freeTime) { _, newValue in
            if selectedFreeTimeLevel != newValue.level {
                selectedFreeTimeLevel = newValue.level
            }
        }
    }
    
    // MARK: - Subviews
    
    /// The caption shown below the slider: the selected free time (e.g. "2 horas").
    private var caption: some View {
        HStack {
            Text(dayOfWeek.freeTime.displayName)
                .font(.system(size: Layout.captionFontSize))
                .fontWeight(.light)
            
            Spacer()
        }
        .foregroundColor(Color(red: 0.45, green: 0.45, blue: 0.45))
    }
}

#Preview {
    @Previewable @State var viewModel = OnboardingViewModel()
    NavigationStack {
        SelectFreeTimeOnboardingView(viewModel: $viewModel, isFromSettings: true)
    }
}
