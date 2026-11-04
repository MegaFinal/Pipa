//
//  RetroCoinsView.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 29/09/26.
//

import SwiftUI

/// Retrospective page with the coins the user earned in the cycle that just ended.
///
/// The amount comes from ``RetroCoinsViewModel`` (the cycle's payout, decided by the user's rank);
/// thresholds and messages live in ``RetroCoinsContent``. Navigation goes through `viewModel`.
struct RetroCoinsView: View {
    /// The retrospective's view model, for navigation.
    let viewModel: RetroViewModel
    /// The cycle's coins and the redeem action.
    let coinsViewModel: RetroCoinsViewModel

    /// `true` once the pig shows its coin.
    @State private var showCoinPig = false
    /// `true` once the coins float around the pig.
    @State private var showFloatingCoins = false

    /// This page's content, built from the cycle's coins.
    private var content: RetroCoinsContent {
        RetroCoinsContent.make(
            earned: coinsViewModel.cycleEarned,
            tier: coinsViewModel.cycleTier,
            maxFloatingCoins: RetroCoinsScatter.maxCount
        )
    }

    /// Whether this page is the one on screen.
    private var isActive: Bool { viewModel.isPageActive(.coins) }

    /// What restarts the pig animation: the page becoming visible or the content changing.
    private struct AnimationKey: Equatable {
        let isActive: Bool
        let content: RetroCoinsContent?
    }

    var body: some View {
        VStack {
            
            Spacer()
            
            // MARK: - Piggy bank (gets a coin, then coins float around it)
            ZStack {
                Image("RetroPig")
                    .resizable()
                    .opacity(showCoinPig ? 0 : 1)
                
                Image("RetroPigCoin")
                    .resizable()
                    .opacity(showCoinPig ? 1 : 0)
                    .scaleEffect(showCoinPig ? 1 : 0.8)
            }
            .frame(width: showCoinPig ? width * 0.6 : width * 0.55, height: showCoinPig ? width * 0.6 : height * 0.159)
            .foregroundStyle(.gray)
            .overlay {
                if showFloatingCoins {
                    RetroCoinsScatter(count: content.floatingCoinsCount)
                }
            }
            .padding(.bottom, height * 0.037)
            .accessibilityDecorative()
            // Starts once the page is visible and the coins are loaded; replays every time the page
            // becomes visible (the paged TabView builds it while the previous page is on screen).
            .task(id: AnimationKey(isActive: isActive, content: coinsViewModel.isLoaded ? content : nil)) {
                showCoinPig = false
                showFloatingCoins = false
                guard isActive, coinsViewModel.isLoaded, content.hasCoinPig else { return }
                try? await Task.sleep(for: .seconds(0.6))
                withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) {
                    showCoinPig = true
                }
                guard content.hasFloatingCoins else { return }
                try? await Task.sleep(for: .seconds(0.5))
                showFloatingCoins = true
            }
            
            // MARK: - Coins earned (spinner while loading)
            if coinsViewModel.isLoaded {
                Text(content.coinsLabel)
                    .bold()
                    .font(.system(size: 64))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 24)
                    .padding(.bottom, height * 0.014)
                    .accessibilityAddTraits(.isHeader)
            } else {
                ProgressView()
                    .frame(height: 76)
                    .padding(.bottom, height * 0.014)
                    .voiceOverLabel(L10n.tr("Carregando moedas"))
            }
            
            // MARK: - Subtitle and message
            Text(subtitle)
                .fontWeight(.regular)
                .font(.title)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, height * 0.014)
            
            Text(content.message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.gray) //arrumar o cinza depois
                .padding(.horizontal, 24)
                .padding(.bottom, height * 0.05)

            // MARK: - Redeem error
            if let errorText = coinsViewModel.errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.subTitleGray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, height * 0.014)
            }
            
            // MARK: - Actions: see later / redeem and conclude
            Button {
                withAnimation {
                    viewModel.skipRetrospective()
                }
            } label: {
                Text("ver depois")
                    .fontWeight(.semibold)
                    .font(.subheadline)
                    .foregroundStyle(.gray) //arrumar o cinza depois
            }
            
            // Redeems the pending coins (if any) and then moves on.
            Button {
                Task { await redeemAndContinue() }
            } label: {
                Group {
                    if coinsViewModel.isWorking {
                        ProgressView()
                    } else {
                        Text(buttonTitle)
                    }
                }
                .frame(minWidth: width * 0.69, minHeight: height * 0.037)
                .multilineTextAlignment(.center)
                .fontWeight(.medium)
                .font(.system(size: 17))
            }
            .voiceControlNames([L10n.tr("Concluir"), L10n.tr("Continuar"), L10n.tr("Resgatar")])
            .buttonStyle(.glassProminent)
            .glassEffectTransition(.identity)
            // Waits for the coins, so the redeem is never skipped by tapping too early.
            .disabled(!coinsViewModel.isLoaded || coinsViewModel.isWorking)
        }
    }

    /// "Resgatar e concluir" here, since this is the last page (follows `RetroPage` if it moves).
    private var buttonTitle: LocalizedStringKey {
        switch (hasCoinsToRedeem, RetroPage.coins.isLast) {
        case (true, true): "Resgatar e concluir"
        case (true, false): "Resgatar e continuar"
        case (false, true): "Concluir"
        case (false, false): "Continuar"
        }
    }

    /// Whether there are coins to redeem that weren't redeemed yet.
    private var hasCoinsToRedeem: Bool {
        coinsViewModel.pendingAmount > 0 && !coinsViewModel.didRedeem
    }

    /// Redeems first; only moves on (continues, or concludes on the last page) if there was nothing
    /// to redeem or the redeem worked.
    /// On failure it stays on the page, showing the error, so the user can try again.
    private func redeemAndContinue() async {
        if hasCoinsToRedeem {
            await coinsViewModel.redeem()
            guard coinsViewModel.didRedeem else { return }
            VoiceOver.announce(L10n.tr("Moedas resgatadas"))
        }
        withAnimation {
            viewModel.advance()
        }
    }

    /// "ganhas neste ciclo com o rank X", or without the rank when it is unknown.
    private var subtitle: String {
        if let tierName = content.tierName {
            return L10n.tr("ganhas neste ciclo com o rank \(tierName)")
        }
        return L10n.tr("ganhas neste ciclo")
    }
}

#if DEBUG
#Preview("Sem moedas") {
    RetroPreviewHost(page: .coins) {
        RetroCoinsView(viewModel: $0, coinsViewModel: .preview(earned: 0, tier: nil))
    }
}

#Preview("Bronze 1") {
    RetroPreviewHost(page: .coins) {
        RetroCoinsView(viewModel: $0, coinsViewModel: .preview(earned: Tier.novatoDaCasa.cycleCoins, tier: .novatoDaCasa))
    }
}

#Preview("Ouro 2") {
    RetroPreviewHost(page: .coins) {
        RetroCoinsView(viewModel: $0, coinsViewModel: .preview(earned: Tier.protetorDoLar.cycleCoins, tier: .protetorDoLar))
    }
}

#Preview("Mestre") {
    RetroPreviewHost(page: .coins) {
        RetroCoinsView(viewModel: $0, coinsViewModel: .preview(earned: Tier.almaDaCasa.cycleCoins, tier: .almaDaCasa))
    }
}
#endif
