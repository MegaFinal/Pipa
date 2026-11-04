//
//  RetroRankView.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 21/10/26.
//

import SwiftUI

/// Retrospective page with the rank the user reached in the cycle that just ended.
///
/// Same look as the rewards tab (``RankArc`` with the rank icon). The rank and points come from
/// ``RetroCoinsViewModel`` (the cycle's payout); texts live in ``RetroRankContent``.
/// Navigation goes through `viewModel`.
struct RetroRankView: View {
    /// The retrospective's view model, for navigation.
    let viewModel: RetroViewModel
    /// The cycle's rank and points.
    let coinsViewModel: RetroCoinsViewModel

    /// `true` once the rank icon popped in.
    @State private var showIcon = false
    /// When on, the icon appears without the pop animation.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// This page's content, built from the cycle's rank and points.
    private var content: RetroRankContent {
        RetroRankContent.make(tier: coinsViewModel.cycleTier, points: coinsViewModel.cyclePoints)
    }

    var body: some View {
        VStack {
            
            Spacer()
            
            // MARK: - Rank arc with the rank icon, and the rank's name (spinner while loading)
            if coinsViewModel.isLoaded {
                ZStack(alignment: .bottom) {
                    if let tier = content.tier {
                        Image(tier.imageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: width * 0.3, height: width * 0.3)
                            .scaleEffect(showIcon ? 1 : 0.4)
                            .opacity(showIcon ? 1 : 0)
                    }
                }
                .padding(.bottom, height * 0.037)
                .accessibilityHidden(true)
                // Pops the icon in every time the page appears (and if the rank changes).
                .task(id: content) {
                    showIcon = false
                    if reduceMotion { showIcon = true; return }
                    try? await Task.sleep(for: .seconds(0.3))
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) {
                        showIcon = true
                    }
                }
                
                Text(content.tierName)
                    .bold()
                    .font(.system(size: 56))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 24)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, height * 0.014)
                    .accessibilityAddTraits(.isHeader)
                
                Spacer()
                
            } else {
                ProgressView()
                    .frame(height: width * 0.4)
                    .padding(.bottom, height * 0.037)
                    .voiceOverLabel(L10n.tr("Carregando rank"))
            }
            
            // MARK: - Subtitle and points detail
            Text(content.subtitle)
                .fontWeight(.regular)
                .font(.title)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, height * 0.014)
            
            Text(content.detail)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.gray) //arrumar o cinza depois
                .padding(.horizontal, 24)
            
            Spacer()
            
            // MARK: - Message
            Text(content.message)
                .bold()
                .font(.title2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, height * 0.03)
            
            // MARK: - Actions: see later or continue
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
            .padding(.bottom, height * 0.014)
            
            Button {
                withAnimation {
                    viewModel.advance()
                }
            } label: {
                Text("Continuar")
                    .frame(minWidth: width * 0.69, minHeight: height * 0.037)
                    .multilineTextAlignment(.center)
                    .fontWeight(.medium)
                    .font(.system(size: 17))
            }
            .voiceControlNames([L10n.tr("Continuar"), L10n.tr("Próxima")])
            .buttonStyle(.glassProminent)
            .glassEffectTransition(.identity)
        }
    }
}

// MARK: - Content

/// What `RetroRankView` shows. Pure, so the texts are easy to tune and test.
struct RetroRankContent: Equatable {
    /// `nil` when the cycle has no payout yet (nothing was settled).
    let tier: Tier?
    /// The rank's name, or "Sem rank".
    let tierName: String
    /// The line under the name.
    let subtitle: String
    /// Points of the cycle and how far they were from the next step.
    let detail: String
    /// A message that depends on the rank group.
    let message: String
    /// How full the arc is: the share of the division done, or full at Mestre (as in the rewards tab).
    let arcFraction: Double
    /// The arc's color: red to green by progress, pink at Mestre.
    let tint: Color

    /// The content for `tier` and `points`.
    /// - Parameters:
    ///   - tier: The rank of the cycle, or `nil` when it wasn't calculated.
    ///   - points: The points made in the cycle.
    static func make(tier: Tier?, points: Int) -> RetroRankContent {
        guard let tier else {
            return RetroRankContent(
                tier: nil,
                tierName: L10n.tr("Sem rank"),
                subtitle: L10n.tr("neste ciclo"),
                detail: L10n.tr("O rank deste ciclo ainda não foi calculado."),
                message: L10n.tr("Bora subir no próximo ciclo!"),
                arcFraction: 0,
                tint: .choreYellow
            )
        }

        let progress = Tier.progress(forPoints: points)
        let fraction = progress.nextTier == nil
            ? 1
            : Double(progress.pointsIntoDivision) / Double(Tier.pointsPerDivision)

        let pointsText = points == 1 ? L10n.tr("1 ponto") : L10n.tr("\(points) pontos")
        let detail: String
        if let next = progress.nextTier, let missing = progress.pointsToNext {
            detail = L10n.tr("\(pointsText) no ciclo. Faltaram \(missing) para \(next.displayName).")
        } else {
            detail = L10n.tr("\(pointsText) no ciclo. Você chegou ao rank máximo!")
        }

        return RetroRankContent(
            tier: tier,
            tierName: tier.displayName,
            subtitle: L10n.tr("foi o rank que você alcançou neste ciclo"),
            detail: detail,
            message: message(for: tier),
            arcFraction: fraction,
            tint: tint(for: tier, fraction: fraction)
        )
    }

    /// One message per rank group (início, meio, topo da escada).
    private static func message(for tier: Tier) -> String {
        let step = Tier.allCases.firstIndex(of: tier) ?? 0
        switch step {
        case _ where tier == .almaDaCasa: return L10n.tr("Você chegou ao topo, parabéns!")
        case 9...: return L10n.tr("Que ciclo! Poucos chegam tão longe")
        case 3...: return L10n.tr("Mandou bem! Dá para subir ainda mais")
        default: return L10n.tr("Todo começo conta")
        }
    }

    /// Same colors as the rewards tab's arc: red (far from the next division) → green (almost),
    /// pink at Mestre.
    private static func tint(for tier: Tier, fraction: Double) -> Color {
        if tier == .almaDaCasa { return .rankMasterPink }
        switch fraction {
        case ..<0.25: return .tagRed
        case ..<0.5: return .choreOrange
        case ..<0.75: return .choreYellow
        default: return .choreGreen
        }
    }
}

#if DEBUG
#Preview("Sem rank") {
    RetroPreviewHost(page: .rank) {
        RetroRankView(viewModel: $0, coinsViewModel: .preview(earned: 0, tier: nil))
    }
}

#Preview("Bronze 2") {
    RetroPreviewHost(page: .rank) {
        RetroRankView(viewModel: $0, coinsViewModel: .preview(earned: Tier.aprendiz.cycleCoins, tier: .aprendiz, points: 30))
    }
}

#Preview("Ouro 2") {
    RetroPreviewHost(page: .rank) {
        RetroRankView(viewModel: $0, coinsViewModel: .preview(earned: Tier.protetorDoLar.cycleCoins, tier: .protetorDoLar, points: 192))
    }
}

#Preview("Mestre") {
    RetroPreviewHost(page: .rank) {
        RetroRankView(viewModel: $0, coinsViewModel: .preview(earned: Tier.almaDaCasa.cycleCoins, tier: .almaDaCasa, points: 410))
    }
}
#endif
