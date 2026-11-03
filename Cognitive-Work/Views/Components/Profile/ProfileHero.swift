//
//  ProfileHero.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 21/10/26.
//

import SwiftUI

/// The top of the profile screens; picture and banner
struct ProfileHero<AvatarOverlay: View>: View {
    let banner: ProfileBanner
    let image: UIImage?
    let avatarOverlay: AvatarOverlay
    
    // MARK: - Layout
    
    private let height: CGFloat = 290
    private let avatarSize: CGFloat = 180
    private let curveDepth: CGFloat = 65
    private let avatarBottomInset: CGFloat = 21
    
    init(banner: ProfileBanner, image: UIImage?, @ViewBuilder avatarOverlay: () -> AvatarOverlay) {
        self.banner = banner
        self.image = image
        self.avatarOverlay = avatarOverlay()
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            bannerBackground
            avatar
                .overlay(alignment: .bottomTrailing) {
                    avatarOverlay
                }
                .padding(.bottom, avatarBottomInset)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }
    
    private var bannerBackground: some View {
        RoomTextureBackground(color: banner.color, pattern: banner.pattern, zoom: 3)
            .id("\(banner.color.rawValue).\(banner.pattern.rawValue)")
            .transition(.opacity)
            .frame(height: height)
            .clipShape(ProfileHeroShape(curveDepth: curveDepth))
            .shadow(color: .black.opacity(0.14), radius: 16.47, x: 0, y: 4.69)
    }
    
    private var avatar: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.white
                Image(systemName: "person.fill")
                    .font(.system(size: avatarSize * 0.4))
                    .foregroundStyle(.gray)
            }
        }
        .frame(width: avatarSize, height: avatarSize)
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.25), radius: 6.85, x: 0, y: 4)
    }
}

extension ProfileHero where AvatarOverlay == EmptyView {
    init(banner: ProfileBanner, image: UIImage?) {
        self.init(banner: banner, image: image) { EmptyView() }
    }
}

#Preview {
    VStack {
        ProfileHero(banner: .default, image: nil)
        Spacer()
    }
    .ignoresSafeArea()
}
