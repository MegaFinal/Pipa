//
//  PremiumView.swift
//  Cognitive-Work
//

import SwiftUI
import StoreKit

/// Pipa Premium: the plans when the house isn't Premium, or the subscription status when it is.
///
/// The plans shown depend on the house size (``HouseSizeTier``): a house with 5 residents only
/// sees the "4 a 6 moradores" prices. Open it as a sheet with
/// ``SwiftUI/View/premiumPaywall(_:)`` when a free user taps a Premium feature, or from the profile.
struct PremiumView: View {

    /// The feature that opened the paywall, shown first. `nil` when opened from the profile.
    var highlighted: PremiumFeature?

    @Environment(\.dismiss) private var dismiss

    private var premium = PremiumManager.shared

    /// Shows the student yearly plan (-30%).
    ///
    /// - Important: Honor system for now — nothing checks that the person studies. See the notes
    ///   on verifying students before shipping.
    @AppStorage("premium.isStudent") private var isStudent = false

    @State private var isShowingManageSubscription = false
    @State private var isRestoring = false
    @State private var restoreMessage: String?

    init(highlighted: PremiumFeature? = nil) {
        self.highlighted = highlighted
    }

    var body: some View {
        NavigationStack {
            Group {
                if !premium.isPremium {
                    store(isUpgrade: false)
                } else if premium.isPaidByMe && premium.needsUpgrade {
                    // The house grew: same screen, now offering the bigger bracket. Because all
                    // plans share one subscription group, the App Store treats it as an upgrade.
                    store(isUpgrade: true)
                } else {
                    activeSubscription
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .voiceOverLabel(L10n.tr("Fechar"))
                }
            }
            .alert(
                "Restaurar compras",
                isPresented: Binding(
                    get: { restoreMessage != nil },
                    set: { if !$0 { restoreMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(restoreMessage ?? "")
            }
        }
        .animation(.snappy, value: premium.isPremium)
    }

    // MARK: - Store

    /// The products of the house's bracket (plus the student plan when toggled on).
    private var productIDs: [String] {
        premium.requiredTier.productIDs(includingStudent: isStudent)
    }

    /// StoreKit's own subscription screen with our content on top. It loads the products,
    /// shows the localized prices, the free trial, the legal text and runs the purchase.
    private func store(isUpgrade: Bool) -> some View {
        SubscriptionStoreView(productIDs: productIDs) {
            marketingContent(isUpgrade: isUpgrade)
        }
        // A new list of products needs a new store view (it reads them only once).
        .id(productIDs)
        .subscriptionStoreControlStyle(.prominentPicker)
        .subscriptionStoreButtonLabel(.multiline)
        .storeButton(.hidden, for: .cancellation)
        // Required by App Review: links to the terms of use (EULA) and the privacy policy.
        .subscriptionStorePolicyDestination(
            url: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!,
            for: .termsOfService
        )
        // TODO: replace with the app's privacy policy page.
        .subscriptionStorePolicyDestination(
            url: URL(string: "https://www.apple.com/legal/privacy/")!,
            for: .privacyPolicy
        )
        // Also covers the lifetime `ProductView` inside the marketing content.
        .onInAppPurchaseCompletion { _, result in
            // `.success(.success)` is a completed purchase; cancelled, pending ("Ask to Buy") and
            // errors need nothing here (a pending one arrives later via `Transaction.updates`).
            if case .success(.success(let verification)) = result {
                await StoreManager.shared.handle(verification)
                HapticsManager.notify(.success)
            }
        }
        .safeAreaInset(edge: .bottom) {
            restoreButton
        }
    }

    /// Title, house bracket, student toggle, features and the lifetime option.
    private func marketingContent(isUpgrade: Bool) -> some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.yellow.gradient)
                    .accessibilityHidden(true)

                Text(isUpgrade ? L10n.tr("Atualize seu plano") : L10n.tr("Pipa Premium"))
                    .font(.custom("Alan Sans", size: 34))
                    .fontWeight(.bold)
                    .accessibilityAddTraits(.isHeader)

                Text(isUpgrade
                     ? L10n.tr("Sua casa agora tem \(premium.memberCount) moradores. O Premium continua ativo, mas o plano atual cobre uma casa menor.")
                     : L10n.tr("Uma assinatura libera tudo para a casa inteira."))
                    .font(.system(size: 17))
                    .foregroundStyle(.subTitleGray)
                    .multilineTextAlignment(.center)
            }

            houseBracket

            if !isUpgrade {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(orderedFeatures) { feature in
                        PremiumFeatureRow(feature: feature, isHighlighted: feature == highlighted)
                    }
                }

                lifetimeOption
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }

    /// "5 moradores · faixa 4 a 6" and the student switch.
    private var houseBracket: some View {
        VStack(spacing: 12) {
            Label {
                // Two keys instead of one: "%lld moradores" varies by plural ("1 morador"), and
                // a plural variation only works on a string with a single number.
                Text(L10n.tr("\(premium.memberCount) moradores")
                     + " · "
                     + L10n.tr("Preço para \(premium.requiredTier.title.lowercased())"))
            } icon: {
                Image(systemName: "person.3.fill")
            }
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.groupedBackground))

            Toggle(isOn: $isStudent.animation(.snappy)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sou estudante")
                        .font(.system(size: 16, weight: .semibold))
                    Text("\(Self.studentDiscount) de desconto no plano anual")
                        .font(.system(size: 13))
                        .foregroundStyle(.subTitleGray)
                }
            }
            .tint(.black)
        }
    }

    /// "Vitalício (por conta)": a one-time purchase that covers any house size.
    private var lifetimeOption: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ou pague uma vez")
                .font(.system(size: 16, weight: .semibold))
            ProductView(id: PremiumPlan.lifetime.productID)
                .productViewStyle(.compact)
            Text("Vale para a sua conta, em qualquer casa e com qualquer número de moradores.")
                .font(.system(size: 13))
                .foregroundStyle(.subTitleGray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "30%" written the way the app's language writes percentages.
    private static var studentDiscount: String {
        0.3.formatted(.percent.precision(.fractionLength(0)).locale(L10n.locale))
    }

    /// The highlighted feature first, then what exists today, then "Em breve".
    private var orderedFeatures: [PremiumFeature] {
        let rest = PremiumFeature.allCases.filter { $0 != highlighted }
        let available = rest.filter { !$0.isComingSoon }
        let comingSoon = rest.filter(\.isComingSoon)
        return (highlighted.map { [$0] } ?? []) + available + comingSoon
    }

    private var restoreButton: some View {
        Button {
            Task { await restore() }
        } label: {
            if isRestoring {
                ProgressView()
            } else {
                Text("Restaurar compras")
                    .font(.footnote.weight(.semibold))
            }
        }
        .tint(.secondary)
        .disabled(isRestoring)
        .padding(.bottom, 4)
    }

    private func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await StoreManager.shared.restore()
            if !premium.isPremium {
                restoreMessage = L10n.tr("Não encontramos uma assinatura ativa para este ID Apple.")
            }
        } catch {
            restoreMessage = L10n.tr("Não foi possível restaurar. Tente novamente.")
        }
    }

    // MARK: - Active subscription

    /// What a Premium house sees: who pays, which plan, until when, and (for the payer) how to
    /// manage it.
    private var activeSubscription: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "crown.fill")
                .font(.system(size: 64))
                .foregroundStyle(.yellow.gradient)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Sua casa é Premium")
                    .font(.custom("Alan Sans", size: 30))
                    .fontWeight(.bold)
                    .accessibilityAddTraits(.isHeader)

                if let plan = premium.currentPlan {
                    Text(planName(plan))
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.groupedBackground))
                }

                Text(statusText)
                    .font(.system(size: 17))
                    .foregroundStyle(.subTitleGray)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            if premium.isPaidByMe, premium.currentPlan?.isLifetime == false {
                Button("Gerenciar assinatura") {
                    isShowingManageSubscription = true
                }
                .buttonStyle(.glass)
            }

            Spacer()

            if highlighted != nil {
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
        .manageSubscriptionsSheet(isPresented: $isShowingManageSubscription)
    }

    /// "Anual · até 3 moradores", "Anual Estudante · …" or "Vitalício".
    private func planName(_ plan: PremiumPlan) -> String {
        let period: String
        switch plan.period {
        case .lifetime: return L10n.tr("Vitalício")
        case .monthly: period = L10n.tr("Mensal")
        case .yearly: period = plan.isStudent ? L10n.tr("Anual Estudante") : L10n.tr("Anual")
        }
        guard let tier = plan.tier else { return period }
        return "\(period) · \(tier.title.lowercased())"
    }

    /// Who pays, the renewal date, and a nudge when the house outgrew the plan.
    private var statusText: String {
        var text: String
        let date = premium.expirationDate.map { $0.formatted(date: .long, time: .omitted) }
        if premium.isPaidByMe {
            if let date {
                text = L10n.tr("Você assina o Premium. Próxima renovação em \(date).")
            } else {
                text = L10n.tr("Você tem o Premium vitalício.")
            }
        } else {
            let name = payerName ?? L10n.tr("outro morador")
            text = L10n.tr("Assinado por \(name). Todos os moradores aproveitam os recursos Premium.")
            if premium.needsUpgrade {
                text += " " + L10n.tr("A casa cresceu: peça para \(name) atualizar o plano.")
            }
        }
        return text
    }

    /// The housemate who pays, looked up in the loaded house data.
    private var payerName: String? {
        guard let owner = premium.houseOwnerRecordName else { return nil }
        return HouseDataStore.shared.snapshot?.users.first { $0.ownerRecordName == owner }?.name
    }
}

// MARK: - Feature row

/// One line of the paywall: icon, title, explanation and an "Em breve" tag when not built yet.
private struct PremiumFeatureRow: View {
    let feature: PremiumFeature
    let isHighlighted: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: feature.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isHighlighted ? Color.white : Color.black)
                .frame(width: 40, height: 40)
                .background(Circle().fill(isHighlighted ? Color.black : Color.groupedBackground))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(feature.title)
                        .font(.system(size: 16, weight: .semibold))
                    if feature.isComingSoon {
                        Text("Em breve")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.groupedBackground))
                            .foregroundStyle(.subTitleGray)
                    }
                }
                Text(feature.subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.subTitleGray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Gate

extension View {
    /// Presents ``PremiumView`` whenever `feature` is set, highlighting it.
    ///
    /// ```swift
    /// @State private var paywall: PremiumFeature?
    ///
    /// Button("Pendências") {
    ///     if PremiumManager.shared.allows(.debts) { showDebts = true } else { paywall = .debts }
    /// }
    /// .premiumPaywall($paywall)
    /// ```
    func premiumPaywall(_ feature: Binding<PremiumFeature?>) -> some View {
        sheet(item: feature) { feature in
            PremiumView(highlighted: feature)
        }
    }
}

/// Small crown shown next to a Premium control while the house is on the free plan.
struct PremiumBadge: View {
    var body: some View {
        Image(systemName: "crown.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.yellow)
            .accessibilityLabel(L10n.tr("Premium"))
    }
}

#Preview("Paywall") {
    PremiumView(highlighted: .debts)
}
