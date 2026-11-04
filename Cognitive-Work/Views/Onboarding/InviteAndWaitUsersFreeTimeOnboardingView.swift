//
//  DoneSelectingFreeTimeView.swift
//  Cognitive-Work
//
//  Created by Carolina Sun on 10/09/26.
//

import CloudKit
import SwiftUI

/// The step where the house creator invites the roomies and waits until every member has set
/// their free time. Also opened from the house settings ("Adicionar moradores").
///
/// The member list is refreshed by polling, by CloudKit pushes and when the app comes back. Those
/// refreshes can overlap, so only the latest one is allowed to show its result.
struct InviteAndWaitUsersFreeTimeOnboardingView: View {
    
    // MARK: - Properties
    
    /// State shared by every step of the flow.
    @Binding var viewModel: OnboardingViewModel
    
    /// Every member of the house.
    @State private var houseUsers: [UserModel] = []
    /// Members who already set their free time.
    @State private var completedUsers: [UserModel] = []
    /// Members who still need to set their free time.
    @State private var pendingUsers: [UserModel] = []
    
    /// Grows on each refresh, so an older refresh can't overwrite a newer one.
    @State private var refreshGeneration: Int = 0
    /// `true` while the invite link is being prepared.
    @State private var resolveShare = true
    /// The invite link, once ready.
    @State private var shareURL: URL? = nil
    /// Shows the "Tentar novamente" button when the link couldn't be made.
    @State private var didFailToPrepareInvite = false
    /// The house's CloudKit share.
    @State private var houseShare: CKShare? = nil
    
    
    /// `false` until the first fetch returns.
    @State private var hasLoadedUsers = false
    
    /// How often the member list is refreshed.
    private let pollingInterval: Duration = .seconds(5)
    
    /// Maximum number of residents shown on each row.
    private let maxUsersPerRow = 4
    
    /// CloudKit can't run in Xcode previews (no iCloud entitlement there), and touching it
    /// crashes the preview process. Every network call below is skipped when this is `true`.
    private var isRunningForPreviews: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
    
    
    /// `true` when opened from the house settings ("Adicionar moradores"). There is no flow to
    /// advance there, so the onboarding-only controls ("Continuar" and its hint) are hidden.
    var isFromSettings: Bool
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // MARK: - Title and description (the view is already inset by `width * 0.84`, the header's own side margin)
            OnboardingHeader(
                title: "Adicione seus roomies!",
                description: "Envie o convite para quem mora com você",
                containerInset: width * 0.08
            )
            .padding(.bottom, height * 0.028)
            
            // MARK: - Member count and loading
            Text("Na casa \(Text("\(houseUsers.count)").fontWeight(.black))")
                .font(.body)
                .frame(width: width * 0.84, alignment: .leading)
                .padding(.top, 30)
                .padding(.bottom, width * 0.02)
                .accessibilityLabel(Text(L10n.tr("\(houseUsers.count) moradores na casa")))
            
            if !hasLoadedUsers {
                ProgressView()
                    .controlSize(.regular)
                    .accessibilityLabel(Text(L10n.tr("Carregando moradores")))
            }
                    
            // MARK: - Pending and ready members
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !pendingUsers.isEmpty {
                        Text("Em configuração")
                        .font(.subheadline)
                        .fontWeight(.thin)
                        .accessibilityAddTraits(.isHeader)
                        pendingUsersView
                    }
                    
                    if !completedUsers.isEmpty {
                        Text("Moradores prontos")
                        .font(.subheadline)
                        .fontWeight(.thin)
                        .accessibilityAddTraits(.isHeader)
                        completedUsersView
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)

            // MARK: - Hint, invite button and "Continuar"
            VStack {
                if !isFromSettings {
                    Text("Certifique-se de que todos os moradores estão dentro do app antes de continuar")
                        .frame(width: width * 0.8)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.gray)
                }
            
                HStack {
                    Spacer()
                    inviteButton
                        .frame(alignment: .center)
                    
                    if !isFromSettings {
                        Button("Continuar", systemImage: "chevron.right") {
                            Task { viewModel.goToNextView() }
                        }
                        .bold()
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .disabled(!pendingUsers.isEmpty)
                        .voiceControlNames([L10n.tr("Continuar"), L10n.tr("Próximo"), L10n.tr("Avançar")])
                        .voiceOverHint(pendingUsers.isEmpty ? "" : L10n.tr("Disponível quando todos os moradores terminarem a configuração"))
                    }
                    Spacer()
                }
            }
        }
        .frame(width: width * 0.84)
        .navigationBarBackButtonHidden(!isFromSettings)
        // MARK: - Back button
        // Going back deletes the house created in the previous step; ask first when roomies
        // already joined it, since they lose access too.
        .onboardingBackButton(
            viewModel: viewModel,
            confirmationMessage: houseUsers.count > 1
                ? LocalizedStringKey("A casa criada será apagada e os roomies que já entraram perderão o acesso.")
                : nil,
            isHidden: isFromSettings
        )
        // MARK: - Prepares the invite and keeps the member list fresh
        .task(id: viewModel.currentHouse?.recordID) {
            await prepareInvite()
        }
        .task(id: viewModel.currentHouse?.recordID) {
            if !isFromSettings && !isRunningForPreviews {
                await viewModel.flushPendingFreeTimeIfNeeded()
            }
            await updateUsers()
            
            while !Task.isCancelled {
                try? await Task.sleep(for: pollingInterval)
                guard !Task.isCancelled else { break }
                await updateUsers()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cloudKitDidChange)) { _ in
            Task {
                await updateUsers()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task {
                await updateUsers()
            }
        }
        .hidesTabBar()
    }
    
    
    // MARK: - Subviews
    
    /// Members who already completed their free time.
    private var completedUsersView: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(Array(completedUsers.chunked(into: maxUsersPerRow).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 20) {
                    ForEach(row) { user in
                        ZStack {
                            Circle()
                                .foregroundColor(.green)
                                .frame(width: width * 0.17)
                            
                            UserProfilePictureTag(user: user, widthMultiplier: 0.15)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(L10n.tr("\(user.name), pronto")))
                    }
                }
            }
        }
    }
    
    /// Members who still need to complete their free time.
    private var pendingUsersView: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(Array(pendingUsers.chunked(into: maxUsersPerRow).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 20) {
                    ForEach(row) { user in
                        ZStack {
                            Circle()
                                .foregroundColor(.red)
                                .frame(width: width * 0.17)
                            
                            UserProfilePictureTag(user: user, widthMultiplier: 0.15)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(L10n.tr("\(user.name), ainda configurando o tempo livre")))
                    }
                }
            }
        }
    }
    
    
    /// The invite button: share the link, try again, or a spinner while it's being made.
    @ViewBuilder
    private var inviteButton: some View {
        if let shareURL, !resolveShare {
            ShareLink(item: shareURL) {
                inviteCapsule(color: .black) {
                    Text("Compartilhar Convite")
                }
            }
            .voiceControlNames([L10n.tr("Compartilhar Convite"), L10n.tr("Compartilhar"), L10n.tr("Convidar")])
        } else if didFailToPrepareInvite && !resolveShare {
            Button {
                Task { await prepareInvite() }
            } label: {
                inviteCapsule(color: .black) {
                    Label("Tentar novamente", systemImage: "arrow.clockwise")
                }
            }
            .voiceControlNames([L10n.tr("Tentar novamente"), L10n.tr("Recarregar")])
        } else {
            inviteCapsule(color: .gray) {
                ProgressView()
                    .tint(.white)
            }
            .accessibilityLabel(Text("Preparando convite"))
        }
    }
    
    /// The black (or gray) capsule shared by the invite button's states.
    private func inviteCapsule<Content: View>(color: Color, @ViewBuilder label: () -> Content) -> some View {
        label()
            .font(.system(size: 17))
            .frame(width: width * 0.539, height: height * 0.058, alignment: .center)
            .foregroundColor(.white)
            .background {
                Capsule()
                    .foregroundColor(color)
                    .glassEffect()
            }
    }
    
    // MARK: - Actions
    
    /// Resolves the house's CKShare and its link.
    private func prepareInvite() async {
        guard !isRunningForPreviews else { return }
        resolveShare = true
        didFailToPrepareInvite = false
        defer { resolveShare = false }
        
        var house = viewModel.currentHouse
        if house == nil {
            do {
                house = try await CloudKitManager.shared.currentHouse()
            }
            catch {
                print(CloudKitManager.shared.errorMessage as Any)
                return
            }
        }
        guard let house else {
            didFailToPrepareInvite = true
            return
        }
        
        if let share = await CloudKitManager.shared.resolveShare(for: house) {
            houseShare = share
            do {
                shareURL = try await CloudKitManager.shared.generateShareLink(share: share)
            } catch {
                print("Erro ao gerar link: \(error.localizedDescription)")
            }
        }
        
        didFailToPrepareInvite = shareURL == nil
    }
    
    /// Fetches the members and splits them into ready and pending.
    private func updateUsers() async {
        guard !isRunningForPreviews else {
            hasLoadedUsers = true
            return
        }
        
        // Sync fix: tag this run so a slower, older run can't overwrite a newer result.
        refreshGeneration += 1
        let generation = refreshGeneration
        
        let fetchedUsers = await viewModel.fetchHouseUsers()
        
        var completed: [UserModel] = []
        var pending: [UserModel] = []
        
        for user in fetchedUsers {
            let availableTimes = await user.availableTime
            
            if availableTimes.isEmpty {
                pending.append(user)
            } else {
                completed.append(user)
            }
        }
        
        // Sync fix: publish only if no newer refresh started meanwhile.
        guard generation == refreshGeneration else { return }
        let wasLoaded = hasLoadedUsers
        let previousCompletedCount = completedUsers.count
        houseUsers = fetchedUsers
        completedUsers = completed
        pendingUsers = pending
        hasLoadedUsers = true
        announceProgress(isFirstLoad: !wasLoaded, previousCompletedCount: previousCompletedCount)
    }
    
    /// VoiceOver: says where the wait stands on the first load, then whenever someone finishes
    /// (the screen polls every few seconds, so it only speaks when something changed).
    private func announceProgress(isFirstLoad: Bool, previousCompletedCount: Int) {
        guard !isFromSettings else { return }
        guard isFirstLoad || completedUsers.count > previousCompletedCount else { return }
        if pendingUsers.isEmpty {
            VoiceOver.announce(L10n.tr("Todos os moradores estão prontos"))
        } else {
            VoiceOver.announce(L10n.tr("Aguardando os moradores: \(completedUsers.count) de \(houseUsers.count) prontos"))
        }
    }
}

#Preview {
    @Previewable @State var mockViewModel = OnboardingViewModel()
    
    InviteAndWaitUsersFreeTimeOnboardingView(
        viewModel: $mockViewModel,
        isFromSettings: false
    )
}

private extension Array {
    /// Splits the array into consecutive slices of at most `size` elements.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
