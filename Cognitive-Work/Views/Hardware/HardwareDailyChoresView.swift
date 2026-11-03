//
//  HardwareDailyChoresView.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 17/09/26.
//

import Foundation
import SwiftUI
//import WeatherKit // desativado (App Review 5.2.5)
import CloudKit

/// Wall-dashboard view showing every house member's chores for the target day, one column per
/// user, shaded by the room each chore belongs to.
///
/// The image goes to a 4-level grayscale e-paper, converted with
/// `UIImage.levelBitmap4Gray(halfTones: true)`, which turns those 4 levels into 7 tones. The
/// rooms use those tones (``EInkRoomStyle``) instead of their app colors, which all collapsed
/// into similar grays there.
///
/// Which day that is comes from ``HardwareDailyChoresViewModel/dayOffsetFromToday`` — currently
/// tomorrow, on purpose, while the e-paper flow is being tested.
///
/// > Note: this view is render-only. ``HardwareViewModel/sendChartToESP32()`` awaits
/// > `viewModel.setup()` and then hands the populated view model to `ImageRenderer`, which does
/// > not run `.task`. The modifier below is a fallback for presenting the dashboard on screen;
/// > it is not what fills the image sent to the device.
struct HardwareDailyChoresView: View {
    /// Loads the target day's chores, members and rooms.
    var viewModel = HardwareDailyChoresViewModel()
//    var weatherViewModel = WeatherViewModel() // WeatherKit desativado

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // MARK: - Title and one column per member
            header
            userColumns
        }
        .padding(.vertical)
        // MARK: - E-paper colors, hidden from VoiceOver, fallback loading
        .foregroundStyle(EInkShade.black)
        .environment(\.colorScheme, .light)
        .accessibilityHidden(true)
        .task {
            guard viewModel.userGroups.isEmpty else { return }
            await viewModel.setup()
        }
    }

    // MARK: - Subviews

    /// The title and the target day's date. (The weather forecast is turned off.)
    private var header: some View {
        HStack {
            HStack(alignment: .firstTextBaseline) {
                Text("Tarefas do Dia,")
                    .font(.title)
                    .bold()

                Text(viewModel.targetDateFormatted)
                    .font(.title2)
            }
            
            Spacer()
            
            // WeatherKit desativado (App Review 5.2.5) - previsão do tempo no cabeçalho
//            HStack(spacing: 10) {
//                Image(systemName: weatherViewModel.weatherIcon)
//
//                Text(weatherViewModel.averageTemperature)
//            }
//            .font(.title2)
//            .padding(.bottom)
        }
        .padding(.horizontal)
    }

    /// One column per house member, each showing their chores for the target day.
    private var userColumns: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 12) {
                ForEach(viewModel.userGroups) { group in
                    UserDailyChoresColumn(group: group, roomProvider: viewModel.room(for:))
                        .frame(height: geometry.size.height)
                }
            }
        }
        .padding(.horizontal)
    }

    /// Room legend, with the same shade as the cards. Not shown right now.
    private var legend: some View {
        HStack(spacing: 20) {
            ForEach(viewModel.roomsInUse) { room in
                HStack(spacing: 6) {
                    EInkRoomSwatch(style: EInkRoomStyle(room: room))
                    Text(room.name.localizedDefault)
                        .font(.title3)
                        .foregroundStyle(.black)
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom)
    }
}

// MARK: - Private subviews

/// One member's column: their name and share of the day on top, then their chore cards.
private struct UserDailyChoresColumn: View {
    /// The member and their chores.
    var group: UserDailyChoresGroup
    /// Finds the room of a chore (for its shade).
    var roomProvider: (ChoreModel) -> RoomModel?

    /// Caps how many chore cards a column renders, so a user with a long list doesn't demand
    /// more height than the screen has to offer. Chores past the cap collapse into one thin
    /// "+N tarefas" strip instead of a full card.
    static let maxVisibleChores = 3

    /// The chores that get a card.
    private var visibleChores: [ChoreModel] {
        Array(group.chores.prefix(Self.maxVisibleChores))
    }

    /// How many chores didn't fit (the "+N tarefas" strip).
    private var overflowCount: Int {
        max(0, group.chores.count - Self.maxVisibleChores)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // MARK: - Name and share of the day
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(group.user.name)
                    .font(.title3)
                    .fontWeight(.bold)
                
                Spacer()
                
                Text(group.shareOfDayFormatted)
                    .font(.title3)
                    .foregroundStyle(.black)
            }
            .padding(.trailing, 5)

            // MARK: - Chore cards, "+N" strip or empty state
            if group.chores.isEmpty {
                emptyState
            } else {
                VStack(spacing: 7) {
                    ForEach(visibleChores) { chore in
                        DailyChoreCard(chore: chore, room: roomProvider(chore))
                            .frame(maxHeight: .infinity)
                    }
                    if overflowCount > 0 {
                        OverflowStrip(count: overflowCount)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Shown instead of the chore stack when the user has nothing due today.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Sem tarefas por hoje")
                .font(.title3)
                .fontWeight(.bold)
                // No line limit: wraps onto as many lines as it needs instead of "…".
                .fixedSize(horizontal: false, vertical: true)

            // Makes card expand when there's only one chore
            Spacer(minLength: 0)
        }
        // Plain white with dark gray text: no fill or border, so it never reads as a room.
        .foregroundColor(EInkShade.darkGray)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(EInkShade.white)
    }
}

/// A single chore card, shaded with the e-paper tone of its room.
private struct DailyChoreCard: View {
    /// The chore shown.
    var chore: ChoreModel
    /// The chore's room, or `nil`.
    var room: RoomModel?

    /// The card's tones.
    private var style: EInkRoomStyle { EInkRoomStyle(room: room) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(room?.name.localizedDefault ?? L10n.tr("Sem cômodo"))
                .font(.body)
                .fontWeight(.medium)
                .fixedSize(horizontal: false, vertical: true)

            Text(chore.localizedName)
                .font(.title3)
                .fontWeight(.bold)
                .fixedSize(horizontal: false, vertical: true)

            // Makes card expand when there's only one chore
            Spacer(minLength: 0)
        }
        .foregroundColor(style.text)
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 55, alignment: .topLeading)
        .background(style.fill)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// A thin strip with the number of chores that didn't get a card.
private struct OverflowStrip: View {
    /// How many chores are hidden.
    var count: Int

    var body: some View {
        Text(verbatim: "+" + L10n.tr("\(count) tarefas"))
            .font(.title3)
            .fontWeight(.semibold)
            .foregroundColor(EInkShade.darkGray)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .background(EInkShade.white)
    }
}

// MARK: - E-ink palette

/// The 7 tones the e-paper shows (`UIImage.eInkHalfTones`). Paint only these: the converter
/// snaps any other gray to the nearest one. The in-between tones come out on the panel as a
/// fine checkerboard of the two neighbouring levels.
private enum EInkShade {
    /// The darkest tone.
    static let black = tone(0)
    /// Between black and dark gray.
    static let blackDarkGray = tone(1)
    /// Dark gray.
    static let darkGray = tone(2)
    /// The middle tone (not used by any room).
    static let darkLightGray = tone(3)
    /// Light gray.
    static let lightGray = tone(4)
    /// The lightest shade that still stands out from the white background.
    static let lightGrayWhite = tone(5)
    /// White (the background).
    static let white = tone(6)

    /// The color of tone `index` from the e-paper's 7 tones.
    private static func tone(_ index: Int) -> Color {
        Color(white: Double(UIImage.eInkHalfTones[index].brightness) / 255)
    }
}

/// How a room's cards look on the e-paper.
///
/// Every room color gets its own tone, ordered by how dark the app color is, so the dashboard
/// keeps a similar feel. Text is white on every tone except the lightest (light gray / white).
private struct EInkRoomStyle {
    /// The card's background tone.
    let fill: Color
    /// The card's text tone.
    let text: Color

    /// The style for a room, by its app color. Rooms without color use the middle tone.
    init(room: RoomModel?) {
        guard let color = room?.color else {
            // The middle tone, unused by the rooms.
            self.init(fill: EInkShade.darkLightGray, text: EInkShade.white)
            return
        }
        switch color {
        case .purple: self.init(fill: EInkShade.black, text: EInkShade.white)
        case .blue: self.init(fill: EInkShade.blackDarkGray, text: EInkShade.white)
        case .orange: self.init(fill: EInkShade.darkGray, text: EInkShade.white)
        case .green: self.init(fill: EInkShade.lightGray, text: EInkShade.white)
        case .yellow: self.init(fill: EInkShade.lightGrayWhite, text: EInkShade.black)
        }
    }

    /// Creates a style from two tones.
    private init(fill: Color, text: Color) {
        self.fill = fill
        self.text = text
    }
}

/// Legend dot with a room's tone.
private struct EInkRoomSwatch: View {
    /// The room's tones.
    let style: EInkRoomStyle

    var body: some View {
        Circle()
            .fill(style.fill)
            .frame(width: 22, height: 22)
    }
}

/// Sample data for the previews: five rooms, five members and their chores.
@MainActor
private enum HardwareDailyChoresPreviewData {

    /// Builds a view model filled with the sample data.
    static func makeViewModel() -> HardwareDailyChoresViewModel {
        // MARK: rooms
        func makeRoom(_ name: String, color: RoomColor, id: String) -> RoomModel {
            var room = RoomModel(name: name, symbol: "fish", color: color)
            room.recordID = CKRecord.ID(recordName: "preview-\(id)")
            return room
        }

        let banheiro      = makeRoom("Banheiro",        color: .purple, id: "banheiro")
        let cozinha       = makeRoom("Cozinha",         color: .blue,   id: "cozinha")
        let salaDeEstar   = makeRoom("Sala de estar",   color: .green,  id: "sala")
        let areaDeServico = makeRoom("Área de serviço", color: .yellow, id: "area")
        let quarto        = makeRoom("Quarto",          color: .orange, id: "quarto")

        // MARK: users
        func makeUser(_ name: String) -> UserModel {
            let user = UserModel(name: name, tier: .tier1, ownerRecordName: "preview-\(name)")
            user.recordID = CKRecord.ID(recordName: "preview-user-\(name)")
            return user
        }

        let jones   = makeUser("Jones")
        let isabela = makeUser("Isabela")
        let carol   = makeUser("Carol")
        let anshu   = makeUser("Anshu")
        let dayo    = makeUser("Dayô") // sem tarefas: mostra o "Sem tarefas por hoje"

        // MARK: chores
        func makeChore(_ name: String, room: RoomModel, responsible: UserModel, duration: Double) -> ChoreModel {
            let chore = ChoreModel(
                name: name,
                description: "",
                dueDate: Date(),
                frequency: .daily,
                duration: duration,
                isPublic: true,
                priorityTag: .medium,
                currentResponsible: responsible.recordID.map { CKRecord.Reference(recordID: $0, action: .none) },
                roomReference: room.recordID.map { CKRecord.Reference(recordID: $0, action: .none) }
            )
            chore.recordID = CKRecord.ID(recordName: "preview-chore-\(UUID().uuidString)")
            return chore
        }

        let chores: [ChoreModel] = [
            // Jones
            makeChore("Lavar Box",               room: banheiro,      responsible: jones,   duration: 15),
            makeChore("Lavar louça do domingo",  room: cozinha,       responsible: jones,   duration: 20),
            makeChore("Regar as plantas",        room: quarto,        responsible: jones,   duration: 10),

            // Isabela
            makeChore("Lavar roupas brancas",    room: areaDeServico, responsible: isabela, duration: 40),
            makeChore("Lavar chão",              room: banheiro,      responsible: isabela, duration: 15),
            makeChore("Tirar o lixo",            room: banheiro,      responsible: isabela, duration: 5),

            // Carol
            makeChore("Lavar louça do jantar",   room: cozinha,       responsible: carol,   duration: 20),
            makeChore("Passar pano",             room: salaDeEstar,   responsible: carol,   duration: 15),
            makeChore("Dobrar as roupas",        room: areaDeServico, responsible: carol,   duration: 25),

            // Anshu (5 tarefas: testa o limite de 3 cards + faixa "+2 tarefas")
            makeChore("Jogar água nas plantas",  room: quarto,        responsible: anshu,   duration: 5),
            makeChore("Tirar o lixo",            room: cozinha,       responsible: anshu,   duration: 5),
            makeChore("Cozinhar almoço",         room: cozinha,       responsible: anshu,   duration: 45),
            makeChore("Lavar panelas",           room: cozinha,       responsible: anshu,   duration: 20),
            makeChore("Organizar geladeira",     room: cozinha,       responsible: anshu,   duration: 15),
        ]

        return HardwareDailyChoresViewModel(
            chores: chores,
            users: [jones, isabela, carol, anshu, dayo],
            rooms: [banheiro, cozinha, salaDeEstar, areaDeServico, quarto]
        )
    }
}

// MARK: - Preview

#Preview("Painel (paisagem)", traits: .fixedLayout(width: 800, height: 480)) {
    HardwareDailyChoresView(viewModel: HardwareDailyChoresPreviewData.makeViewModel())
        .background(Color.white)
}
