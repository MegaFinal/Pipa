//
//  PremiumWelcomeView.swift
//  Cognitive-Work
//
//  Created by Isabela Hissa Pinto on 18/11/26.
//

import SwiftUI

/// Shown once per house, the first time someone opens a house that has Premium: that Premium
/// belongs to the house (trial, or whoever pays), until when, and what it unlocks.
///
/// ``ContentView`` presents it as a sheet when ``PremiumWelcome/isDue`` is `true`.
struct PremiumWelcomeView: View {

    @Environment(\.dismiss) private var dismiss

    /// Whose Premium it is and when it ends. Read from ``PremiumManager`` by default; the
    /// previews pass sample ones.
    var status: Status = .current

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                statusCard

                VStack(alignment: .leading, spacing: 24) {
                    Text("O que a casa ganha")
                        .font(.system(size: 20).weight(.bold))
                        .accessibilityAddTraits(.isHeader)

                    ForEach(PremiumFeature.paywallFeatures) { feature in
                        PremiumFeatureRow(feature: feature)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            Button {
                dismiss()
            } label: {
                Text("Continuar")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(.black)
            .padding(.horizontal, 24)
            .padding(.bottom)
        }
    }

    // MARK: - Subviews

    /// The crown and "Sua casa é Premium".
    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 56))
                .foregroundStyle(.yellow.gradient)
                .accessibilityHidden(true)

            Text("Sua casa é Premium")
                .font(.custom("Alan Sans", fixedSize: 30))
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, 40)
    }

    /// Whose Premium it is and when it ends, in the paywall's gray card.
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(status.headline)
                    .font(.system(size: 17, weight: .semibold))
            } icon: {
                Image(systemName: status.systemImage)
                    .foregroundStyle(status.tint)
            }
            Text(status.detail)
                .font(.system(size: 15))
                .foregroundStyle(.subTitleGray)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.groupedBackground, in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Texts

    /// The texts and icon of the status card.
    struct Status {
        /// "Sua casa está no teste grátis até 18 de janeiro", "Fulano assina o Premium desta casa"…
        let headline: String
        /// What it unlocks and when it ends or renews.
        let detail: String
        /// `gift.fill` for the trial, `crown.fill` when someone pays.
        let systemImage: String
        /// The icon's color.
        let tint: Color

        /// The free trial, which belongs to the house.
        static func trial(endsAt: Date) -> Status {
            let date = endsAt.formatted(.dateTime.day().month(.wide).locale(L10n.locale))
            return Status(
                headline: L10n.tr("Sua casa está no teste grátis até \(date)"),
                detail: L10n.tr("Todos os recursos Premium estão liberados. Depois disso, alguém da casa precisa assinar para continuar."),
                systemImage: "gift.fill",
                tint: RoomColor.purple.uiColor
            )
        }

        /// A purchase, which belongs to whoever pays.
        ///
        /// - Parameters:
        ///   - payerName: The housemate who pays, or `nil` when it's this person.
        ///   - isLifetime: Whether it's the lifetime purchase.
        ///   - renewsAt: The next renewal of a subscription, when known.
        static func paid(by payerName: String?, isLifetime: Bool, renewsAt: Date?) -> Status {
            let headline: String
            if let payerName {
                headline = isLifetime
                    ? L10n.tr("O Premium vitalício de \(payerName) vale para esta casa")
                    : L10n.tr("\(payerName) assina o Premium desta casa")
            } else {
                headline = isLifetime
                    ? L10n.tr("Seu Premium vitalício vale para esta casa")
                    : L10n.tr("Você assina o Premium desta casa")
            }

            let everyone = L10n.tr("Todos os moradores aproveitam os recursos Premium.")
            let detail: String
            if isLifetime {
                detail = L10n.tr("Todos os moradores aproveitam os recursos Premium, sem data para acabar.")
            } else if let renewsAt {
                let date = renewsAt.formatted(date: .long, time: .omitted)
                detail = everyone + " " + L10n.tr("Próxima renovação em \(date).")
            } else {
                detail = everyone
            }

            return Status(headline: headline, detail: detail, systemImage: "crown.fill", tint: .yellow)
        }

        /// The house's Premium right now, from ``PremiumManager``.
        @MainActor
        static var current: Status {
            let premium = PremiumManager.shared
            if premium.isOnTrialOnly, let endsAt = premium.houseTrialEndsAt {
                return .trial(endsAt: endsAt)
            }
            return .paid(
                by: premium.isPaidByMe ? nil : (premium.payerName ?? L10n.tr("outro morador")),
                isLifetime: premium.currentPlan?.isLifetime == true,
                renewsAt: premium.expirationDate
            )
        }
    }
}

// MARK: - When to show

/// Remembers, per house and per device, that ``PremiumWelcomeView`` was shown.
enum PremiumWelcome {

    /// Whether the house has Premium and this device hasn't shown the welcome for it yet.
    @MainActor
    static var isDue: Bool {
        let premium = PremiumManager.shared
        guard premium.isPremium, let token = premium.currentHouseToken else { return false }
        return !UserDefaults.standard.bool(forKey: key(for: token))
    }

    /// Records that the welcome was shown for the current house.
    @MainActor
    static func markShown() {
        guard let token = PremiumManager.shared.currentHouseToken else { return }
        UserDefaults.standard.set(true, forKey: key(for: token))
    }

    /// One key per house (``PremiumManager/purchaseToken(for:)`` is the same on every device).
    private static func key(for token: UUID) -> String {
        "premium.welcomeShown.\(token.uuidString)"
    }
}

// MARK: - Previews

/// The tabs' place behind the sheet, so the previews look like the first time in the house.
private struct PremiumWelcomePreviewHost: View {
    let status: PremiumWelcomeView.Status
    @State private var isPresented = true

    var body: some View {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
            .overlay {
                // Verbatim: preview-only, kept out of Localizable.
                Button { isPresented = true } label: { Text(verbatim: "Abrir de novo") }
            }
            .sheet(isPresented: $isPresented) {
                PremiumWelcomeView(status: status)
            }
    }
}

#Preview("Teste grátis") {
    PremiumWelcomePreviewHost(
        status: .trial(endsAt: Calendar.current.date(byAdding: .month, value: 2, to: .now)!)
    )
}

#Preview("Assinado por outro morador") {
    PremiumWelcomePreviewHost(
        status: .paid(by: "Carol", isLifetime: false,
                      renewsAt: Calendar.current.date(byAdding: .month, value: 1, to: .now))
    )
}

#Preview("Vitalício próprio") {
    PremiumWelcomePreviewHost(status: .paid(by: nil, isLifetime: true, renewsAt: nil))
}
