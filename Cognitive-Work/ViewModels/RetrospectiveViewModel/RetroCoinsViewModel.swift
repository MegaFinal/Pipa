//
//  RetroCoinsViewModel.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 19/10/26.
//

import Foundation
import CloudKit
import Observation

/// What the retrospective reads from CloudKit about the cycle that just ended: the rank the user
/// reached (rank page), the coins it paid (coins page) and the coins they can still redeem.
///
/// Owned by the screen that presents the retrospective (``NotificationsView``), which calls
/// ``load()`` as soon as it appears, so the retrospective opens with everything ready. Loading also
/// settles the closed cycles (``CycleSettlementService/prepareClosedCycles(_:members:houseID:today:)``):
/// payouts, rank history and the reset of every member's rank exist even if nobody opened the
/// rewards tab.
@MainActor
@Observable
final class RetroCoinsViewModel {

    /// Coins from closed cycles not redeemed yet.
    private(set) var pendingAmount = 0
    /// Coins earned in the most recent closed cycle (the one the retrospective is about),
    /// redeemed or not. `0` when that cycle has no payout.
    private(set) var cycleEarned = 0
    /// Rank the user reached in that cycle, which decided ``cycleEarned``.
    private(set) var cycleTier: Tier?
    /// Points the user had when that cycle closed (what ``cycleTier`` came from).
    private(set) var cyclePoints = 0
    /// `true` once the first load finished, even if it found nothing.
    private(set) var isLoaded = false
    /// `true` once the user redeemed the pending coins in this session.
    private(set) var didRedeem = false
    /// `true` while redeeming.
    private(set) var isWorking = false
    /// A user-facing error from the last redeem, or `nil`.
    private(set) var errorText: String?

    /// What ``redeem()`` needs, kept from the last load.
    private struct Context {
        let houseID: CKRecord.ID
        let user: UserModel
        let cycles: [HouseCycleModel]
    }

    /// The house, member and cycles of the last load. `nil` before loading or when it failed.
    @ObservationIgnored private var context: Context?
    /// The load running or done, so ``load()`` runs only once.
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// Previews only: ``redeem()`` simulates the redeem instead of touching CloudKit.
    @ObservationIgnored private var isPreview = false

    // MARK: - Loading

    /// Loads once. Calls made while (or after) it runs wait for that same load instead of
    /// starting another one.
    func load() async {
        if let loadTask {
            await loadTask.value
            return
        }
        let task = Task { await self.performLoad() }
        loadTask = task
        await task.value
    }

    /// Loads again from scratch (pull to refresh).
    func reload() async {
        loadTask = nil
        await load()
    }

    /// Settles the closed cycles and reads the member's payouts (see ``load()``).
    private func performLoad() async {
        defer { isLoaded = true }
        guard let houseID = try? await CloudKitManager.shared.currentHouse()?.recordID,
              let user = await CloudKitManager.shared.currentHouseUser(),
              let userID = user.recordID
        else { return }

        async let fetchedCycles = HouseCycleModel.fetchAll(inHouseZone: houseID.zoneID)
        async let fetchedMembers = CloudKitManager.shared.fetchHouseUsers()
        let (cycles, members) = await (fetchedCycles, fetchedMembers)

        let service = CycleSettlementService()
        await service.prepareClosedCycles(cycles, members: members, houseID: houseID)

        let payouts = await service.payouts(for: userID, cycles: cycles)
        context = Context(houseID: houseID, user: user, cycles: cycles)
        pendingAmount = payouts.filter { $0.status == .pending }.reduce(0) { $0 + $1.amount }
        // Sorted by cycle key (oldest first): the last one is the cycle that just ended.
        let latest = payouts.last
        cycleEarned = latest?.amount ?? 0
        cycleTier = latest?.tier
        cyclePoints = latest?.points ?? 0
    }

    // MARK: - Redeeming

    /// Confirms the user's pending payouts and credits them to their wallet.
    func redeem() async {
        #if DEBUG
        if isPreview {
            guard !isWorking, pendingAmount > 0 else { return }
            isWorking = true
            try? await Task.sleep(for: .seconds(0.8))
            isWorking = false
            didRedeem = true
            pendingAmount = 0
            return
        }
        #endif
        guard let context, let userID = context.user.recordID, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            _ = try await CycleSettlementService().confirmPendingPayouts(
                for: userID,
                cycles: context.cycles,
                houseID: context.houseID,
                legacyCoins: context.user.coins
            )
            didRedeem = true
            pendingAmount = 0
            errorText = nil
        } catch {
            errorText = L10n.tr("Não foi possível resgatar agora. Tente de novo.")
        }
    }
}

// MARK: - Coins page content

/// What `RetroCoinsView` shows. Pure, so the thresholds are easy to tune and test.
struct RetroCoinsContent: Equatable {
    /// Coins earned in the cycle (never negative).
    let coins: Int
    /// ``coins`` as text ("1 moeda", "30 moedas"), translated.
    let coinsLabel: String
    /// The rank that paid the coins, or `nil` when unknown.
    let tierName: String?
    /// Whether the pig gets a coin (the member earned anything).
    let hasCoinPig: Bool
    /// How many coins float around the pig.
    let floatingCoinsCount: Int
    /// The encouraging message under the number.
    let message: String

    /// Whether any coin floats around the pig.
    var hasFloatingCoins: Bool { floatingCoinsCount > 0 }

    /// Every this many coins reveals one more coin around the pig
    /// (Bronze: none, Prata: 1, Ouro: 2, Platina: 3, Diamante: 4, Mestre: max).
    static let coinsPerFloatingCoin = 15

    /// The content for `earned` coins.
    /// - Parameters:
    ///   - earned: Coins earned in the cycle.
    ///   - tier: The rank that paid them.
    ///   - maxFloatingCoins: The most coins the pig animation can show (``RetroCoinsScatter/maxCount``).
    static func make(earned: Int, tier: Tier?, maxFloatingCoins: Int) -> RetroCoinsContent {
        let coins = max(earned, 0)
        let floating = min(coins / coinsPerFloatingCoin, maxFloatingCoins)

        let message: String
        switch coins {
        case 0:
            message = L10n.tr("Nenhuma moeda neste ciclo, bora no próximo!")
        case ..<(coinsPerFloatingCoin * 2):
            message = L10n.tr("Cada tarefa feita te deixa mais perto do próximo rank!")
        default:
            message = L10n.tr("Seu esforço virou recompensa, parabéns!")
        }

        return RetroCoinsContent(
            coins: coins,
            coinsLabel: coins == 1 ? L10n.tr("1 moeda") : L10n.tr("\(coins) moedas"),
            tierName: tier?.displayName,
            hasCoinPig: coins > 0,
            floatingCoinsCount: floating,
            message: message
        )
    }
}

#if DEBUG
extension RetroCoinsViewModel {
    /// Already "loaded" with fixed values, for previews (never touches CloudKit).
    static func preview(earned: Int, tier: Tier?, points: Int? = nil, pending: Int? = nil) -> RetroCoinsViewModel {
        let viewModel = RetroCoinsViewModel()
        viewModel.cycleEarned = earned
        viewModel.cycleTier = tier
        viewModel.cyclePoints = points ?? tier?.minimumPoints ?? 0
        viewModel.pendingAmount = pending ?? earned
        viewModel.isLoaded = true
        viewModel.loadTask = Task {}
        viewModel.isPreview = true
        return viewModel
    }
}
#endif
