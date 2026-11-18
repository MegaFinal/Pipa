//
//  NotificationsView.swift
//  Cognitive-Work
//
//  Created by Isabela Hissa Pinto on 30/09/26.
//

import SwiftUI

/// The notifications screen, opened from the bell on the chores screen: notifications of the
/// last 14 days, grouped by day. Tapping one goes where it points (chores, retrospective,
/// progress...).
struct NotificationsView: View {
    /// Runs on a "tarefas a pegar" notification. ``ChoresView`` decides what to do (it owns the carousel).
    var onPickChores: () -> Void = {}
    /// Runs on a chore notification, with the chore and its occurrence.
    var onOpenChore: (ChoreModel, RecurrentAssignmentModel?) -> Void = { _, _ in }
    /// Runs on a "entrou na casa" notification (offers to divide again).
    var onNewMember: () -> Void = {}
    
    /// Builds the notifications.
    @State private var viewModel = NotificationsViewModel()
    /// Loaded together with the notifications, so the retrospective opens ready.
    @State private var retroCoinsViewModel = RetroCoinsViewModel()
    /// Shows the retrospective.
    @State private var isShowingRetro = false
    /// Opens the progress tab's screen.
    @State private var isShowingDashboard = false
    /// Opens the Premium screen (from "a casa voltou ao plano grátis").
    @State private var isShowingPremium = false
    /// Closes this screen.
    @Environment(\.dismiss) private var dismiss
    #if DEBUG
    /// Result of the last shopping list seeding or cleanup (debug builds only).
    @State private var seedStatus: String?
    /// Whether the shopping list seeder is running (debug builds only).
    @State private var isSeeding = false
    // TODO: PROVISÓRIO — remover. Suporte ao botão de desbloquear todas as badges.
    /// Result of the last "desbloquear todas as badges" tap (debug builds only).
    @State private var badgeUnlockStatus: String?
    /// Whether the badge unlock is running (debug builds only).
    @State private var isUnlockingBadges = false
    #endif
    
    var body: some View {
        // No NavigationStack here: we are already inside ChoresView's stack.
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // MARK: - Title and new count
                header
                
                #if DEBUG
                simulateRetroSection
                #endif
                
                // MARK: - Loading, empty message, or the sections
                if viewModel.isLoading {
                    ProgressView()
                        .voiceOverLabel(L10n.tr("Carregando notificações"))
                } else if viewModel.sections.isEmpty {
                    Text("Nada por aqui nos últimos 14 dias")
                        .foregroundStyle(.subTitleGray)
                } else {
                    ForEach(viewModel.sections) { section in
                        sectionView(section)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        // MARK: - Loading, refreshing and marking as seen
        .task { await viewModel.load() }
        .task { await retroCoinsViewModel.load() }
        .refreshable {
            // Looks for new records in the database, schedules the ones for this user, and then
            // reloads the list with them.
            await NotificationManager.shared.processIncoming()
            await NotificationManager.shared.refreshReminders()
            await viewModel.load(force: true)
            await retroCoinsViewModel.reload()
        }
        .onDisappear { viewModel.markAllAsSeen() }
        // MARK: - Destinations: progress screen and retrospective
        .navigationDestination(isPresented: $isShowingDashboard) {
            DashboardView()
        }
        .sheet(isPresented: $isShowingPremium) {
            PremiumView()
        }
        .fullScreenCover(isPresented: $isShowingRetro) {
            RetroView(coinsViewModel: retroCoinsViewModel) {
                isShowingRetro = false
            }
                .presentationBackground(.clear)
        }
    }
    
    // MARK: - Subviews
    
    /// "Notificações" and how many are new.
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Notificações")
                .font(.custom("Alan Sans", fixedSize: 34))
                .fontWeight(.bold)
                .accessibilityAddTraits(.isHeader)
            Text(viewModel.newCountText)
                .font(.system(size: 17))
                .foregroundStyle(.subTitleGray)
        }
    }
    
    /// One day's group: the day's title and its notifications.
    private func sectionView(_ section: NotificationSection) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(viewModel.title(for: section))
                .font(.system(size: 17))
                .foregroundStyle(.subTitleGray)
                .accessibilityAddTraits(.isHeader)

            ForEach(section.items) { notification in
                Button {
                    handleTap(notification.destination)
                } label: {
                    NotificationComponent(
                        color: notification.kind.color,
                        symbol: notification.kind.symbol,
                        title: notification.title,
                        subtitle: notification.subtitle
                    )
                }
                .buttonStyle(.plain) // keeps the text black
                // Voice Control: say just the title, not title + subtitle.
                .voiceControlNames([notification.title])
            }
        }
    }
    
    #if DEBUG
    // TODO: PROVISÓRIO — remover. Abre a retrospectiva na hora, sem esperar o fim do ciclo.
    // Mesma aparência de uma notificação; não existe em builds de Release.
    /// A notification-style row that opens the retrospective right away (debug builds only).
    private var simulateRetroSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(verbatim: "Testes")
                .font(.system(size: 17))
                .foregroundStyle(.subTitleGray)
                .accessibilityAddTraits(.isHeader)
            
            Button {
                isShowingRetro = true
            } label: {
                NotificationComponent(
                    color: Notifications.retrospective.color,
                    symbol: Notifications.retrospective.symbol,
                    title: "Simular retrospectiva",
                    subtitle: "Provisório: abre a retro agora, com os dados reais"
                )
            }
            .buttonStyle(.plain) // keeps the text black
            .voiceControlNames(["Simular retrospectiva"])
            
            Button {
                Task { await seedShopList() }
            } label: {
                NotificationComponent(
                    color: Notifications.itemBought.color,
                    symbol: Notifications.itemBought.symbol,
                    title: "Popular lista de compras",
                    subtitle: "Cria 4–5 itens por categoria, com preço, para os moradores da casa"
                )
            }
            .buttonStyle(.plain)
            .disabled(isSeeding)
            .voiceControlNames(["Popular lista de compras"])
            
            Button {
                Task { await removeSeededShopList() }
            } label: {
                NotificationComponent(
                    color: Notifications.itemBought.color,
                    symbol: Notifications.itemBought.symbol,
                    title: "Remover dados de teste",
                    subtitle: "Apaga os itens criados pelo botão acima"
                )
            }
            .buttonStyle(.plain)
            .disabled(isSeeding)
            .voiceControlNames(["Remover dados de teste"])
            
            Button {
                Task { await unlockAllBadges() }
            } label: {
                NotificationComponent(
                    color: Notifications.retrospective.color,
                    symbol: Notifications.retrospective.symbol,
                    title: "Desbloquear todas as badges",
                    subtitle: "Provisório: aplica progresso suficiente em cada cômodo para o usuário atual"
                )
            }
            .buttonStyle(.plain)
            .disabled(isUnlockingBadges)
            .voiceControlNames(["Desbloquear todas as badges"])
            
            Button {
                Task { await removeAllBadges() }
            } label: {
                NotificationComponent(
                    color: Notifications.retrospective.color,
                    symbol: Notifications.retrospective.symbol,
                    title: "Remover todas as badges",
                    subtitle: "Provisório: zera o progresso e bloqueia todas as badges do usuário atual"
                )
            }
            .buttonStyle(.plain)
            .disabled(isUnlockingBadges)
            .voiceControlNames(["Remover todas as badges"])
            
            Button {
                Task { await seedPartialBadges() }
            } label: {
                NotificationComponent(
                    color: Notifications.retrospective.color,
                    symbol: Notifications.retrospective.symbol,
                    title: "Badges parcialmente feitas",
                    subtitle: "Provisório: cada cômodo fica entre 5% e 90% da primeira badge, sem desbloquear nenhuma"
                )
            }
            .buttonStyle(.plain)
            .disabled(isUnlockingBadges)
            .voiceControlNames(["Badges parcialmente feitas"])
            
            if let seedStatus {
                Text(verbatim: seedStatus)
                    .font(.system(size: 15))
                    .foregroundStyle(.subTitleGray)
            }
            if let badgeUnlockStatus {
                Text(verbatim: badgeUnlockStatus)
                    .font(.system(size: 15))
                    .foregroundStyle(.subTitleGray)
            }
        }
    }
    
    /// Fills the shopping list with sample items and made-up housemates (debug builds only).
    private func seedShopList() async {
        isSeeding = true
        defer { isSeeding = false }
        do {
            let result = try await ShopListDebugSeeder.seed()
            seedStatus = "\(result.itemCount) itens criados. Moradores: \(result.housemates.joined(separator: ", "))"
        } catch {
            seedStatus = error.localizedDescription
        }
    }
    
    /// Deletes what ``seedShopList()`` created (debug builds only).
    private func removeSeededShopList() async {
        isSeeding = true
        defer { isSeeding = false }
        guard ShopListDebugSeeder.hasSeededData else {
            seedStatus = "Não há dados de teste para remover."
            return
        }
        seedStatus = await ShopListDebugSeeder.removeSeededData()
            ? "Dados de teste removidos."
            : "Não deu para remover tudo; tente de novo."
    }

    // TODO: PROVISÓRIO — remover. Aplica progresso suficiente em todo cômodo para destravar
    // todas as ``RoomBadge`` do usuário atual (debug builds only).
    /// Adds enough check-offs to every default room to unlock every badge of the signed-in user.
    private func unlockAllBadges() async {
        isUnlockingBadges = true
        defer { isUnlockingBadges = false }

        guard let user = await CloudKitManager.shared.currentHouseUser() else {
            badgeUnlockStatus = "Nenhum usuário encontrado."
            return
        }

        let maxThreshold = RoomBadge.allCases.map(\.threshold).max() ?? 0
        let changes = DefaultRoomsOnboarding.allCases.map {
            RoomBadgeChange(room: $0, delta: maxThreshold, isOneOff: false)
        }
        let unlocked = await BadgeManager.shared.apply(changes, to: user)
        badgeUnlockStatus = unlocked.isEmpty
            ? "Nenhuma badge nova (talvez já estivessem todas destravadas)."
            : "\(unlocked.count) badge(s) destravada(s)."
    }

    // TODO: PROVISÓRIO — remover. Zera o progresso das ``RoomBadge`` do usuário atual.
    /// Resets every room count to 0 and locks every badge of the signed-in user (debug builds only).
    private func removeAllBadges() async {
        isUnlockingBadges = true
        defer { isUnlockingBadges = false }

        guard let user = await CloudKitManager.shared.currentHouseUser() else {
            badgeUnlockStatus = "Nenhum usuário encontrado."
            return
        }
        let saved = await BadgeManager.shared.debugReplaceProgress(of: user, counts: [:], unlocked: [])
        badgeUnlockStatus = saved
            ? "Todas as badges foram removidas."
            : "Não deu para salvar; tente de novo."
    }

    // TODO: PROVISÓRIO — remover. Deixa cada cômodo a caminho da primeira ``RoomBadge``,
    // uns mais adiantados que outros, para testar a ordem de "Minhas Badges" no perfil.
    /// Share of its first badge each room gets, in ``DefaultRoomsOnboarding/onboardingOrder``.
    private static let partialBadgeShares: [Double] = [0.9, 0.75, 0.6, 0.45, 0.3, 0.15, 0.05, 0.8, 0.5, 0.35, 0.2]

    /// Sets every default room part of the way to its first badge, some further than others,
    /// with every badge locked (debug builds only).
    private func seedPartialBadges() async {
        isUnlockingBadges = true
        defer { isUnlockingBadges = false }

        guard let user = await CloudKitManager.shared.currentHouseUser() else {
            badgeUnlockStatus = "Nenhum usuário encontrado."
            return
        }

        var counts: [String: Int] = [:]
        for (index, room) in DefaultRoomsOnboarding.onboardingOrder.enumerated() {
            guard let first = room.badges.first else { continue }
            let share = Self.partialBadgeShares[index % Self.partialBadgeShares.count]
            // At least 1 check-off, and always 1 short of the threshold, so nothing unlocks.
            counts[room.rawValue] = min(max(Int(Double(first.threshold) * share), 1), first.threshold - 1)
        }
        let saved = await BadgeManager.shared.debugReplaceProgress(of: user, counts: counts, unlocked: [])
        badgeUnlockStatus = saved
            ? "Progresso parcial aplicado em \(counts.count) cômodos, nenhuma badge desbloqueada."
            : "Não deu para salvar; tente de novo."
    }
    #endif
    
    // MARK: - Actions
    
    /// Goes where the tapped notification points.
    private func handleTap(_ destination: NotificationDestination) {
        switch destination {
        case .pickChores:
            dismiss()
            onPickChores()
        case .retrospective:
            isShowingRetro = true
        case .dashboard:
            isShowingDashboard = true
        case .chore(let chore, let assignment):
            dismiss()
            onOpenChore(chore, assignment)
        case .newMember:
            dismiss()
            onNewMember()
        case .shopList, .pendingPayments, .calendarSync:
            // Screens of other tabs: the same path as a tapped system notification
            // (``AppNavigation``) switches the tab and opens them.
            dismiss()
            NotificationManager.shared.route(to: destination)
        case .premium:
            isShowingPremium = true
        }
    }
}

#Preview {
    NavigationStack { NotificationsView() }
}
