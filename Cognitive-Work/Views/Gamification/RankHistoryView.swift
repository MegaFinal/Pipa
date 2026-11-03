//
//  RankHistoryView.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 16/10/26.
//

import SwiftUI

/// The signed-in user's current rank, how far the next division is, and their rank at the end of
/// every past cycle (``RankHistoryModel``), most recent first.
struct RankHistoryView: View {

    /// The user's points in the current cycle, or `nil` before loading.
    @State private var points: Int?
    /// Past cycles, most recent first.
    @State private var entries: [RankHistoryModel] = []
    /// Whether the first load finished.
    @State private var hasLoaded = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: - Current rank card
                if let points {
                    currentRankCard(points: points)
                }

                // MARK: - Past cycles
                Text("Ciclos anteriores")
                    .font(.system(size: 20))
                    .fontWeight(.bold)
                    .accessibilityAddTraits(.isHeader)

                if entries.isEmpty {
                    Text(hasLoaded
                         ? "Seu histórico aparece aqui quando o primeiro ciclo terminar."
                         : "Carregando…")
                        .foregroundStyle(.subTitleGray)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(entries, id: \.cycleKey) { entry in
                            row(entry)
                        }
                    }
                }
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 20)
        }
        .navigationTitle("Histórico de ranks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        // Reloads on every data change, local or from another device (the CloudKit push bumps
        // `dataRevision`), e.g. when a cycle is settled and the rank starts over.
        .task(id: CloudKitManager.shared.dataRevision) { await load() }
    }

    /// Loads the current points (from the server) and the history.
    private func load() async {
        defer { hasLoaded = true }
        guard let user = await CloudKitManager.shared.currentHouseUser(),
              let userID = user.recordID
        else { return }
        // Read from the score itself: the cached user's copy may be from before the change.
        points = await UserScoreModel.points(for: user)
        entries = await RankHistoryModel.fetchHistory(for: userID)
    }

    // MARK: - Current rank

    /// The current rank: its icon and name, and the progress to the next one.
    private func currentRankCard(points: Int) -> some View {
        let progress = Tier.progress(forPoints: points)
        return HStack(spacing: 16) {
            Image(progress.tier.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(progress.tier.displayName)
                    .font(.system(size: 22))
                    .fontWeight(.bold)
                    .foregroundStyle(.titleGray)

                if let next = progress.nextTier, let missing = progress.pointsToNext {
                    ProgressView(
                        value: Double(progress.pointsIntoDivision),
                        total: Double(Tier.pointsPerDivision)
                    )
                    .tint(.choreYellow)

                    Text(L10n.tr("Faltam \(missing) pontos para \(next.displayName)"))
                        .font(.system(size: 14))
                        .foregroundStyle(.subTitleGray)
                } else {
                    Text("Você chegou ao rank máximo")
                        .font(.system(size: 14))
                        .foregroundStyle(.subTitleGray)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            Color(.systemGray6).opacity(0.5),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - History row

    /// One past cycle: rank icon and name, the cycle's dates, and its points.
    private func row(_ entry: RankHistoryModel) -> some View {
        HStack(spacing: 12) {
            Image(entry.tier.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.tier.displayName)
                    .font(.system(size: 17))
                    .fontWeight(.semibold)
                    .foregroundStyle(.titleGray)
                Text(cycleText(entry))
                    .font(.system(size: 14))
                    .foregroundStyle(.subTitleGray)
            }

            Spacer(minLength: 8)

            Text(L10n.tr("\(entry.points) pts"))
                .font(.system(size: 15))
                .fontWeight(.semibold)
                .foregroundStyle(.titleGray)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color(.systemGray6).opacity(0.5),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    /// The cycle's dates, e.g. "28 de set. – 11 de out.".
    private func cycleText(_ entry: RankHistoryModel) -> String {
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted).locale(L10n.locale)
        return "\(entry.cycleStart.formatted(style)) – \(entry.cycleEnd.formatted(style))"
    }
}

#Preview {
    NavigationStack {
        RankHistoryView()
    }
}
