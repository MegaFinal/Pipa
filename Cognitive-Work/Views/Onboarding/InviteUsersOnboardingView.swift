//
//  FitfhOnboardingView.swift
//  Cognitive-Work
//
//  Created by Carolina Sun on 25/08/26.
//

import SwiftUI
import CloudKit

/// Onboarding step where the house owner shares the invite link.
///
/// Resolves the CloudKit share on appear and keeps the list of members who
/// already joined up to date through `.cloudKitDidChange`.
struct InviteUsersOnboardingView: View {
    
    // MARK: - Properties
    
    /// State shared by every step of the flow.
    @Binding var viewModel: OnboardingViewModel
    
    /// The house's share, once resolved.
    @State private var houseShare: CKShare? = nil
    /// `true` while the share and its link are being prepared.
    @State private var resolvendoShare = true
    /// `true` when the invite couldn't be prepared (shows "Tentar novamente").
    @State private var didFailToPrepareInvite = false
    /// The invite link.
    @State private var shareURL: URL? = nil
    /// Members who already joined.
    @State private var houseUsers: [UserModel] = []
    
    /// `true` when opened from the house settings (no "next" button, system back button).
    var isFromSettings: Bool
    
    // MARK: - Body
    
    var body: some View {
        VStack {
            Spacer()
            
            // MARK: - Members who joined
            if !houseUsers.isEmpty {
                joinedUsers
            }
            
            Spacer()
            
            // MARK: - Instructions
            Text("Assim que todos os moradores estiverem no app, clique em continuar.")
                .frame(width: width * 0.8)
                .multilineTextAlignment(.center)
                .foregroundStyle(.gray)
            
            // MARK: - Invite button and "next"
            HStack {
                inviteButton
                
                if !isFromSettings {
                    OnboardingProgressButton(width: width * 0.12, height: width * 0.12, text: "chevron.forward", isSystemImage: true) {
                        viewModel.goToNextView()
                    }
                    .multilineTextAlignment(.trailing)
                }
            }
        }
        .frame(width: width * 0.84)
        .navigationBarBackButtonHidden(!isFromSettings)
        .onboardingBackButton(viewModel: viewModel, isHidden: isFromSettings)
        // MARK: - Keeping the members up to date and preparing the invite
        .onReceive(NotificationCenter.default.publisher(for: .cloudKitDidChange)) { _ in
            Task {
                houseUsers = await viewModel.fetchHouseUsers()
            }
        }
        .task(id: viewModel.currentHouse?.recordID) {
            await prepareInvite()
        }
        .onChange(of: houseUsers.count) { oldCount, newCount in
            // Someone accepted the invite while the user waits on this screen.
            if newCount > oldCount && oldCount > 0 {
                VoiceOver.announce(L10n.tr("\(newCount) moradores na casa"))
            }
        }
        .onChange(of: didFailToPrepareInvite) { _, didFail in
            if didFail { VoiceOver.announce(L10n.tr("Não foi possível preparar o convite")) }
        }
    }
    
    // MARK: - Actions
    
    /// Resolves the house's CKShare and its link.
    private func prepareInvite() async {
        resolvendoShare = true
        didFailToPrepareInvite = false
        shareURL = nil
        houseShare = nil
        defer { resolvendoShare = false }
        
        var house = viewModel.currentHouse
        if house == nil {
            house = try? await CloudKitManager.shared.currentHouse()
        }
        guard let house else {
            didFailToPrepareInvite = true
            return
        }
        
        async let resolvedShare = CloudKitManager.shared.resolveShare(for: house)
        async let users = viewModel.fetchHouseUsers()
        
        if let share = await resolvedShare {
            houseShare = share
            do {
                shareURL = try await CloudKitManager.shared.generateShareLink(share: share)
            } catch {
                print("Erro ao gerar link: \(error.localizedDescription)")
            }
        }
        
        houseUsers = await users
        didFailToPrepareInvite = shareURL == nil
    }
    
    // MARK: - Subviews
    
    /// The share button, a retry button, or a spinner while the link is prepared.
    @ViewBuilder
    private var inviteButton: some View {
        if let shareURL, !resolvendoShare {
            ShareLink(item: shareURL) {
                inviteCapsule(color: .blue) {
                    Text("Compartilhar Convite")
                }
            }
            .voiceControlNames([L10n.tr("Compartilhar Convite"), L10n.tr("Compartilhar"), L10n.tr("Convidar")])
        } else if didFailToPrepareInvite && !resolvendoShare {
            Button {
                Task { await prepareInvite() }
            } label: {
                inviteCapsule(color: .blue) {
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
    
    /// The capsule style shared by the invite button's states.
    private func inviteCapsule<Content: View>(color: Color, @ViewBuilder label: () -> Content) -> some View {
        label()
            .font(.system(size: 17))
            .frame(width: width * 0.5, height: height * 0.057, alignment: .center)
            .foregroundColor(.white)
            .background {
                Capsule()
                    .foregroundColor(color)
                    .glassEffect()
            }
    }
    /// The avatars of the members who already joined, each in a green circle.
    private var joinedUsers: some View {
        HStack(spacing: 20) {
            ForEach(houseUsers) { user in
                ZStack {
                    Circle()
                        .foregroundColor(.green)
                        .frame(width: width * 0.17)
                    UserProfilePictureTag(user: user, widthMultiplier: 0.15)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(user.name))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(L10n.tr("Moradores que já entraram")))
    }
}

#Preview {
    @Previewable @State var mockViewModel = OnboardingViewModel()
    
    InviteUsersOnboardingView(viewModel: $mockViewModel, isFromSettings: false)
}
