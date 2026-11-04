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

    /// The feature that opened the paywall, listed first. `nil` when opened from the profile.
    var highlighted: PremiumFeature?

    @Environment(\.dismiss) private var dismiss
    
    /// SwiftUI's purchase action: shows the App Store sheet on top of this screen.
    @Environment(\.purchase) private var purchase

    private var premium = PremiumManager.shared
    private var storeManager = StoreManager.shared

    // Student plan: turned off for now. To bring it back, uncomment this, the toggle in
    // `yearlyCard`, `studentDiscount`, the line in `planName` and the student plans in
    // `PremiumPlan.allSubscriptions` (and add them back to Premium.storekit / App Store Connect).
    // - Important: honor system — nothing checks that the person studies.
    // @AppStorage("premium.isStudent") private var isStudent = false

    /// The card picked by the person. Annual by default: it's the best deal.
    @State private var selectedPeriod: PremiumPlan.Period = .yearly

    @State private var isPurchasing = false
    @State private var purchaseErrorMessage: String?
    @State private var isShowingManageSubscription = false
    @State private var isRestoring = false
    @State private var restoreMessage: String?

    init(highlighted: PremiumFeature? = nil) {
        self.highlighted = highlighted
    }

    var body: some View {
        NavigationStack {
            Group {
                if !premium.isPremium || premium.isOnTrialOnly {
                    // On the free trial nobody pays yet: the plans stay on screen.
                    store(isUpgrade: false)
                } else if premium.isPaidByMe && premium.needsUpgrade {
                    // The house grew: same screen, now with the bigger bracket's prices. All
                    // plans share one subscription group, so the App Store treats it as an upgrade.
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
                        Image(systemName: "chevron.left")
                    }
                    .voiceOverLabel(L10n.tr("Fechar"))
                    .voiceControlNames([L10n.tr("Fechar"), L10n.tr("Voltar")])
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
            .alert(
                "Não foi possível comprar",
                isPresented: Binding(
                    get: { purchaseErrorMessage != nil },
                    set: { if !$0 { purchaseErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(purchaseErrorMessage ?? "")
            }
        }
        .animation(.snappy, value: premium.isPremium)
        .task { await storeManager.loadProducts() }
    }

    // MARK: - Plans

    /// The house's price bracket.
    private var tier: HouseSizeTier { premium.requiredTier }

    private var monthlyPlan: PremiumPlan? {
        PremiumPlan.subscription(for: tier, period: .monthly, isStudent: false)
    }

    private var yearlyPlan: PremiumPlan? {
        PremiumPlan.subscription(for: tier, period: .yearly, isStudent: false)
    }

    /// The plan of the selected card.
    private var selectedPlan: PremiumPlan? {
        switch selectedPeriod {
        case .monthly: return monthlyPlan
        case .yearly: return yearlyPlan
        case .lifetime: return .lifetime
        }
    }

    // MARK: - Store

    /// Logo, house bracket, features and the three plan cards, with the purchase button pinned
    /// to the bottom.
    private func store(isUpgrade: Bool) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                logo

                Text(isUpgrade
                     ? L10n.tr("Sua casa agora tem \(premium.memberCount) moradores. O Premium continua ativo, mas o plano atual cobre uma casa menor.")
                     : L10n.tr("Uma assinatura libera todos os benefícios para a casa inteira"))
                    .foregroundStyle(.subTitleGray)
                    .multilineTextAlignment(.center)

                if premium.isOnTrialOnly, let endsAt = premium.houseTrialEndsAt {
                    trialNotice(endsAt: endsAt)
                }

                if premium.hasSubscriptionElsewhere {
                    subscriptionElsewhereNotice
                }

                houseBracket

                VStack(alignment: .leading, spacing: 24) {
                    ForEach(orderedFeatures) { feature in
                        PremiumFeatureRow(feature: feature)
                    }
                }

                VStack(spacing: 8) {
                    monthlyCard
                    yearlyCard
                    lifetimeCard
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .manageSubscriptionsSheet(isPresented: $isShowingManageSubscription)
        .safeAreaInset(edge: .bottom) {
            purchaseFooter
        }
    }

    /// "pipa" with the crown, and "premium" under it.
    private var logo: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Image("pipaWordmark")
                .resizable()
                .scaledToFit()
                .frame(width: 220)
                .foregroundStyle(.black)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.yellow.gradient)
                        .rotationEffect(.degrees(15))
                        .offset(x: 6, y: -22)
                }

            Text(verbatim: "premium")
                .font(.system(size: 30, weight: .light))
        }
        .padding(.top, 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Pipa Premium"))
        .accessibilityAddTraits(.isHeader)
    }

    /// "Sua casa está no teste grátis até 4 de janeiro": what happens when it ends.
    private func trialNotice(endsAt: Date) -> some View {
        let date = endsAt.formatted(.dateTime.day().month(.wide).locale(L10n.locale))
        return VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(L10n.tr("Sua casa está no teste grátis até \(date)"))
                    .font(.headline)
            } icon: {
                Image(systemName: "gift.fill")
                    .foregroundStyle(RoomColor.purple.uiColor)
            }
            Text("Todos os recursos Premium estão liberados. Depois disso, alguém da casa precisa assinar para continuar.")
                .font(.subheadline)
                .foregroundStyle(.subTitleGray)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.groupedBackground, in: .rect(cornerRadius: 24))
    }

    /// For someone who subscribed in another house and moved: the subscription stays with that
    /// house, so it doesn't cover this one (and they keep being charged until they cancel it).
    private var subscriptionElsewhereNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sua assinatura é da casa onde você assinou")
                .font(.headline)
            Text("Ela não vale para esta casa. Se não quiser mais ser cobrado por ela, cancele em Gerenciar assinatura.")
                .font(.subheadline)
                .foregroundStyle(.subTitleGray)
                .fixedSize(horizontal: false, vertical: true)
            Button("Gerenciar assinatura") {
                isShowingManageSubscription = true
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.groupedBackground, in: .rect(cornerRadius: 24))
    }

    /// "1 morador na casa · Preço para até 3 moradores".
    private var houseBracket: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "person.3.fill")
                .accessibilityHidden(true)
            // Two keys instead of one: "%lld moradores" varies by plural ("1 morador"), and
            // a plural variation only works on a string with a single number.
            Text(L10n.tr("\(premium.memberCount) moradores")
                 + " · "
                 + L10n.tr("Preço para \(tier.title.lowercased())"))
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.groupedBackground, in: .rect(cornerRadius: 24))
    }

    /// The feature that opened the paywall first, then the others.
    private var orderedFeatures: [PremiumFeature] {
        let rest = PremiumFeature.paywallFeatures.filter { $0 != highlighted }
        guard let highlighted, !highlighted.isComingSoon else { return rest }
        return [highlighted] + rest
    }

    // MARK: Plan cards

    private var monthlyCard: some View {
        PremiumPlanCard(
            title: "Premium Mensal",
            subtitle: priceText(for: monthlyPlan),
            isSelected: selectedPeriod == .monthly
        ) {
            selectedPeriod = .monthly
        }
    }

    private var yearlyCard: some View {
        PremiumPlanCard(
            title: "Premium Anual",
            subtitle: priceText(for: yearlyPlan),
            isSelected: selectedPeriod == .yearly
        ) {
            selectedPeriod = .yearly
        }
        // Student plan (turned off): the switch went in this card, under the price.
        // } extra: {
        //     Divider()
        //
        //     Toggle(isOn: $isStudent.animation(.snappy)) {
        //         VStack(alignment: .leading, spacing: 2) {
        //             Text("Sou estudante")
        //                 .font(.headline)
        //             Text("\(Self.studentDiscount) de desconto no plano anual")
        //                 .font(.footnote)
        //                 .foregroundStyle(.subTitleGray)
        //         }
        //     }
        //     .onChange(of: isStudent) { _, isOn in
        //         // Turning the discount on is a choice for the annual plan.
        //         if isOn { selectedPeriod = .yearly }
        //     }
        // }
    }

    private var lifetimeCard: some View {
        PremiumPlanCard(
            title: "Premium Vitalício",
            subtitle: priceText(for: .lifetime),
            isSelected: selectedPeriod == .lifetime
        ) {
            selectedPeriod = .lifetime
        }
    }

    // MARK: Footer

    /// Legal links, "Aceitar Oferta" and "Restaurar compras".
    private var purchaseFooter: some View {
        VStack(spacing: 12) {
            // Required by App Review: links to the terms of use (EULA) and the privacy policy.
            HStack(spacing: 4) {
                Link("Termos de Serviço", destination: Self.termsURL)
                Text("e")
                // TODO: replace with the app's privacy policy page.
                Link("Política de Privacidade", destination: Self.privacyURL)
            }
            .font(.caption.weight(.semibold))

            Button {
                Task { await buySelectedPlan() }
            } label: {
                VStack(spacing: 2) {
                    if isPurchasing {
                        ProgressView().tint(.white)
                    } else {
                        Text("Aceitar Oferta")
                            .font(.title3.weight(.semibold))
                        Text(priceText(for: selectedPlan))
                            .font(.caption)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(.blue, in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing || selectedPlan.flatMap { storeManager.product(for: $0) } == nil)
            .voiceControlNames([L10n.tr("Aceitar Oferta"), L10n.tr("Assinar"), L10n.tr("Comprar")])

            restoreButton
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .background(Color(.systemBackground))
    }

    private static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    private static let privacyURL = URL(string: "https://www.apple.com/legal/privacy/")!

    // MARK: Prices

    /// Prices come from the App Store, in the person's currency; "Carregando…" until they arrive.
    private func priceText(for plan: PremiumPlan?) -> String {
        guard let plan, let product = storeManager.product(for: plan) else { return L10n.tr("Carregando…") }
        let price = product.displayPrice

        switch plan.period {
        case .lifetime:
            return L10n.tr("Pague uma vez e tenha o Premium para sempre por apenas \(price)")
        case .monthly, .yearly:
            let isMonthly = plan.period == .monthly
            guard storeManager.isEligibleForTrial, let trial = trialText(for: product) else {
                return isMonthly ? L10n.tr("\(price)/mês") : L10n.tr("\(price)/ano")
            }
            return isMonthly
                ? L10n.tr("\(trial) grátis, depois de \(price)/mês")
                : L10n.tr("\(trial) grátis, depois de \(price)/ano")
        }
    }

    /// The free trial's length in the app's language ("1 semana", "1 week"), or `nil` when the
    /// product has none.
    private func trialText(for product: Product) -> String? {
        guard let offer = product.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        var components = DateComponents()
        switch offer.period.unit {
        case .day: components.day = offer.period.value
        case .week: components.weekOfMonth = offer.period.value
        case .month: components.month = offer.period.value
        case .year: components.year = offer.period.value
        @unknown default: return nil
        }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        var calendar = Calendar.current
        calendar.locale = L10n.locale
        formatter.calendar = calendar
        return formatter.string(from: components)
    }

    // Student plan (turned off): "30%" written the way the app's language writes percentages.
    // private static var studentDiscount: String {
    //     0.3.formatted(.percent.precision(.fractionLength(0)).locale(L10n.locale))
    // }

    // MARK: Actions

    /// Buys the selected plan. A completed purchase unlocks the house right away (the screen
    /// switches to "Sua casa é Premium"); cancelling does nothing; "Ask to Buy" arrives later
    /// through `Transaction.updates`.
    private func buySelectedPlan() async {
        guard let plan = selectedPlan, let product = storeManager.product(for: plan) else { return }
        // The house's token goes with the purchase: the App Store keeps it on every renewal, so
        // the subscription stays tied to this house (see ``PremiumManager``).
        guard let houseToken = premium.currentHouseToken else {
            purchaseErrorMessage = L10n.tr("Não foi possível encontrar sua casa. Tente novamente.")
            return
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            if case .success(let verification) = try await purchase(product, options: [.appAccountToken(houseToken)]) {
                await storeManager.handle(verification)
                HapticsManager.notify(.success)
            }
        } catch {
            purchaseErrorMessage = L10n.tr("Não foi possível concluir a compra. Tente de novo.")
        }
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

    /// "Anual · até 3 moradores" or "Vitalício".
    private func planName(_ plan: PremiumPlan) -> String {
        let period: String
        switch plan.period {
        case .lifetime: return L10n.tr("Vitalício")
        case .monthly: period = L10n.tr("Mensal")
        case .yearly: period = L10n.tr("Anual")
        // Student plan (turned off):
        // case .yearly: period = plan.isStudent ? L10n.tr("Anual Estudante") : L10n.tr("Anual")
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

/// One benefit on the paywall: colored icon, title and explanation.
private struct PremiumFeatureRow: View {
    let feature: PremiumFeature

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: feature.systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(feature.tint)
                .frame(width: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title)
                    .font(.title3.weight(.semibold))
                Text(feature.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.subTitleGray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Plan card

/// A plan to pick: gray rounded card with the title, the price line and a round check. The
/// selected one gets a blue border. `extra` goes under the price (it held the student switch).
private struct PremiumPlanCard<Extra: View>: View {
    let title: LocalizedStringKey
    let subtitle: String
    let isSelected: Bool
    let onSelect: () -> Void
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.title3.bold())
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.blue : Color.secondary)
                    .accessibilityHidden(true)
            }

            Text(subtitle)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)

            extra()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.groupedBackground, in: .rect(cornerRadius: 32))
        .overlay {
            RoundedRectangle(cornerRadius: 32)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        }
        // A tap gesture instead of a Button, so the Toggle inside the annual card keeps working.
        .contentShape(.rect(cornerRadius: 32))
        .onTapGesture {
            HapticsManager.selection()
            withAnimation(.snappy) { onSelect() }
        }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { onSelect() }
    }
}

extension PremiumPlanCard where Extra == EmptyView {
    init(title: LocalizedStringKey, subtitle: String, isSelected: Bool, onSelect: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, isSelected: isSelected, onSelect: onSelect) { EmptyView() }
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

/// Shown where an Apple Intelligence feature would be, for free houses on a device that can run
/// it: "✨ Preencher com IA 👑". Tapping opens the paywall.
struct PremiumAIHint: View {
    /// What the AI would do here.
    var text: LocalizedStringKey = "Preencher com IA"
    @Binding var paywall: PremiumFeature?

    /// Whether to show it: the model can run here and the house isn't Premium.
    static var isNeeded: Bool {
        IntelligenceManager.shared.isAvailable && !PremiumManager.shared.isPremium
    }

    var body: some View {
        Button {
            HapticsManager.selection()
            paywall = .intelligence
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text(text)
                PremiumBadge()
            }
            .font(.footnote.weight(.semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.subTitleGray)
        .frame(maxWidth: .infinity, alignment: .leading)
        .voiceControlNames([L10n.tr("Preencher com IA"), L10n.tr("Premium")])
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
