//
//  GamificationView.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 15/10/26.
//

import SwiftUI
import CloudKit

/// The rewards tab: the ranking sky, the coupons anyone can buy and the coupons the user holds.
struct GamificationView: View {
    
    /// Loads the coins, rank, rooms and coupons and buys coupons.
    @State private var viewModel: GamificationViewModel
    
    /// Id (``CouponEntry/id``) of the coupon brought to the center of the screen, if any.
    @State private var focusedKey: String?
    
    /// Whether the coin balance sheet is open.
    @State private var showsCoins = false
    
    /// Lets a ticket fly from the list to the center and back.
    @Namespace private var ticketNamespace
    
    /// Width of a ticket in the horizontal lists.
    private static let ticketWidth: CGFloat = 145
    
    /// Creates the screen. Pass a ready view model for previews.
    init(viewModel: GamificationViewModel? = nil) {
        self._viewModel = State(initialValue: viewModel ?? GamificationViewModel())
    }
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // MARK: - Title and actions
                    header
                    
                    // MARK: - Ranking
                    RankSkyCard(
                        groups: viewModel.catalog.tiers,
                        myOwnerRecordName: viewModel.myOwnerRecordName
                    )
                    .padding(.horizontal, 30)
                    
                    // MARK: - Coupons (or empty state)
                    if viewModel.catalog.entries.isEmpty {
                        if viewModel.hasLoaded {
                            CouponEmptyState(
                                title: "Nenhum cupom ainda",
                                message: "Quando a casa tiver tarefas, os cupons de cada uma aparecem aqui."
                            )
                            .frame(height: 360)
                        }
                    } else {
                        couponSection(
                            title: L10n.tr("Cupons disponíveis"),
                            entries: viewModel.availableEntries,
                            source: .available,
                            emptyText: L10n.tr("Nenhum cupom disponível agora.")
                        )
                        couponSection(
                            title: L10n.tr("Seus cupons"),
                            entries: viewModel.myEntries,
                            source: .mine,
                            emptyText: L10n.tr("Você ainda não tem cupons neste ciclo.")
                        )
                    }
                }
                .padding(.bottom, 24)
            }
            .background(Color.white.ignoresSafeArea())
            // MARK: - Loading and refreshing
            .task {
                guard !viewModel.hasLoaded else { return }
                await viewModel.setup()
            }
            .onReceive(NotificationCenter.default.publisher(for: .cloudKitDidChange)) { _ in
                viewModel.requestRefresh(catchUp: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                viewModel.requestRefresh()
            }
            // MARK: - Purchase error alert
            .alert(
                "Não foi possível comprar",
                isPresented: Binding(
                    get: { viewModel.alertMessage != nil },
                    set: { if !$0 { viewModel.alertMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.alertMessage ?? "")
            }
            // MARK: - Coin balance
            .sheet(isPresented: $showsCoins) {
                CoinsBalanceCard(coins: viewModel.coins)
                    .padding(24)
                    .presentationDetents([.height(170)])
            }
            .toolbar(.hidden, for: .navigationBar)
            .couponFocus(
                viewModel: viewModel,
                entries: viewModel.catalog.entries,
                focusedKey: $focusedKey,
                namespace: ticketNamespace
            )
        }
    }
    
    // MARK: - Header
    
    /// Page title laid out like the header of ``ShopListView``, with the coins and the room filter.
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Gamificação")
                    .font(.custom("Alan Sans", size: 34))
                    .fontWeight(.bold)
                    .accessibilityAddTraits(.isHeader)
                
                Spacer()
                
                HStack {
                    Text("\(viewModel.coins)")
                        .font(.system(size: 24))
                        .fontWeight(.bold)
                        .foregroundColor(.choreYellow)
                    Image("RetroPig")
                        .resizable()
                        .scaledToFit()
                        .frame(width: width * 0.07)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .foregroundColor(.lowOpacityYellow.opacity(0.35))
                )
            }
            
            Text(verbatim: itemsText)
                .font(.system(size: 18))
                .foregroundStyle(.subTitleGray)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 30)
        .padding(.top, 20)
    }
    
    /// "7 itens para comprar".
    private var itemsText: String {
        let count = viewModel.availableEntries.count
        return count == 1 ? L10n.tr("1 item para comprar") : L10n.tr("\(count) itens para comprar")
    }
    
    /// The room's name, capitalized, in the app's language.
    private func roomName(_ room: RoomModel) -> String {
        room.name.localizedDefault.capitalized(with: L10n.locale)
    }
    
    // MARK: - Coupons
    
    /// A titled row of tickets that scrolls sideways; the title opens every coupon in a grid.
    private func couponSection(
        title: String,
        entries: [CouponEntry],
        source: CouponGridView.Source,
        emptyText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                CouponGridView(title: title, source: source, viewModel: viewModel)
            } label: {
                HStack {
                    Text(verbatim: title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.black)
                        .accessibilityAddTraits(.isHeader)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.subTitleGray)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if entries.isEmpty {
                Text(verbatim: emptyText)
                    .font(.system(size: 15))
                    .foregroundStyle(.subTitleGray)
                    .padding(.horizontal, 30)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(entries) { entry in
                            CouponCell(
                                entry: entry,
                                viewModel: viewModel,
                                focusedKey: focusedKey,
                                namespace: ticketNamespace,
                                onSelect: { focusCoupon($0, in: $focusedKey) }
                            )
                            .frame(width: Self.ticketWidth)
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.vertical, 12)
                }
            }
        }
    }
}

#Preview {
    GamificationView(viewModel: GamificationViewModel(
        previewCoins: 45,
        previewPoints: 85,
        rooms: [DefaultRoomsOnboarding.kitchen, .livingRoom, .bathroom].map { room in
            RoomModel(name: room.rawValue, symbol: room.symbol, color: room.color, kind: room.rawValue)
        },
        couponsByRoomName: [
            DefaultRoomsOnboarding.kitchen.rawValue: [
                CouponModel(name: "Lavar a louça", isOnSale: true, price: 30, tier: .aprendiz),
                CouponModel(name: "Limpar o fogão", isOnSale: true, price: 80, tier: .cavaleiroDoRodo)
            ],
            DefaultRoomsOnboarding.livingRoom.rawValue: [
                CouponModel(name: "Aspirar a sala", isOnSale: true, price: 20, tier: .novatoDaCasa)
            ],
            DefaultRoomsOnboarding.bathroom.rawValue: [
                CouponModel(name: "Limpar o banheiro", isOnSale: true, price: 60, tier: .vigiaDaCozinha)
            ]
        ],
        users: [
            UserModel(name: "Ana", tier: .aprendiz, points: 30, ownerRecordName: "ana"),
            UserModel(name: "Bia", tier: .vigiaDaCozinha, points: 105, ownerRecordName: "bia"),
            UserModel(name: "Caio", tier: .almaDaCasa, points: 320, ownerRecordName: "caio")
        ],
        myOwnerRecordName: "ana"
    ))
}
