//
//  ChoreDetailsCard.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 18/08/26.
//

import SwiftUI
import CloudKit

/// The back face of a chore card
struct ChoreDetailsCard: View {
    private static let verticalInset: CGFloat = 18
    /// A bit taller (fraction of the screen height) when the AI hint shows under "Deslize para
    /// concluir", so the checklist above keeps its room.
    private static let heightWithNote: CGFloat = 0.64
    
    @State private var viewModel: ChoreDetailsViewModel
    
    /// Whether the card is flipped to this side (the checklist loads only then).
    let isShowingBack: Bool
    
    init(
        chore: ChoreModel,
        recurrentAssignment: RecurrentAssignmentModel? = nil,
        carouselViewModel: CarouselViewModel,
        isShowingBack: Bool
    ) {
        _viewModel = State(initialValue: ChoreDetailsViewModel(
            chore: chore,
            recurrentAssignment: recurrentAssignment,
            carouselViewModel: carouselViewModel
        ))
        self.isShowingBack = isShowingBack
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 18) {
                ChoreDetailsHeader(
                    chore: viewModel.chore,
                    symbol: viewModel.room?.symbol ?? viewModel.chore.symbolName,
                    tagsAccessibilityLabel: viewModel.carouselViewModel.accessibilityTagsText(for: viewModel.chore)
                )
                
                ChoreDetailsInfo(viewModel: viewModel)
                    .frame(maxHeight: .infinity)
                
                footer
            }
            .padding(.vertical, Self.verticalInset)
            
            ChoreDetailsActionBar(viewModel: viewModel)
                .accessibilitySortPriority(1)
        }
        .task(id: isShowingBack) {
            await viewModel.loadChecklistIfNeeded(isShowingBack: isShowingBack)
            // The carousel can show this face without the list having built today's order.
            if isShowingBack {
                await TodayChoreOrder.shared.refresh(using: viewModel.carouselViewModel)
            }
        }
        .alert("Não foi possível adiar", isPresented: $viewModel.didFailToPostpone) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Verifique sua conexão e tente novamente.")
        }
        .frame(width: width * 0.88, height: height * (orderNote == nil ? 0.6 : Self.heightWithNote))
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 31))
        .shadow(color: .black.opacity(0.14), radius: 20.39595, x: 0, y: 5.80668)
        .accessibilityElement(children: .contain)
    }
    
    /// "2ª de 3 hoje · Depois de “Cozinhar” (Ana)": this occurrence's place in today's
    /// suggested order and what comes first (see ``TodayChoreOrder``); `nil` when it isn't one
    /// of the viewer's chores today.
    private var orderNote: String? {
        let id = viewModel.recurrentAssignment?.recordID?.recordName ?? viewModel.chore.id.uuidString
        return TodayChoreOrder.shared.note(for: id)
    }

    /// Postpone buttons (not for daily chores) above the swipe to complete.
    private var footer: some View {
        VStack(spacing: 12) {
            if viewModel.canPostpone {
                ChoreDetailsPostponeButtons(viewModel: viewModel)
            }
            
            SwipeToCompleteButton(
                isDone: viewModel.isDone,
                action: { Task { await viewModel.toggleCompletion() } },
                color: viewModel.room?.color.uiColor ?? .gray
            )
            .padding(.horizontal, 30)

            // Grey AI hint under "Deslize para concluir", for the viewer's chores today: its
            // place in the suggested order and what to do first.
            if let note = orderNote {
                Label {
                    Text(note)
                } icon: {
                    Image(systemName: "sparkles")
                }
                .font(.system(size: 13))
                .foregroundStyle(.subTitleGray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
                .voiceOverLabel(L10n.tr("Sugestão: \(note)"))
            }
        }
    }
}

#Preview {
    @Previewable @State var isShowingBack = true
    
    let room: RoomModel = {
        var room = RoomModel(name: "Cozinha", symbol: "bed.stripes", color: .orange)
        room.recordID = CKRecord.ID(recordName: "preview-room")
        return room
    }()
    
    let chore: ChoreModel = {
        let chore = ChoreModel(
            name: "Lavar a louça",
            description: "Lavar tudo que estiver na pia, secar e guardar nos armários.",
            frequency: .weekly,
            duration: 1200,
            isPublic: true,
            priorityTag: .medium,
            roomReference: CKRecord.Reference(
                recordID: CKRecord.ID(recordName: "preview-room"),
                action: .none
            )
        )
        chore.symbolName = "toilet"
        return chore
    }()
    
    let vm: CarouselViewModel = {
        let vm = CarouselViewModel()
        vm.roomModels = [room]
        return vm
    }()
    
    ChoreDetailsCard(chore: chore, carouselViewModel: vm, isShowingBack: isShowingBack)
}
