//
//  UserProfilePictureTag.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 25/08/26.
//

import SwiftUI
import CloudKit

/// A circular avatar badge for a single house member.
struct UserProfilePictureTag: View {

    /// The member whose avatar should be shown, or `nil` to render the placeholder.
    let user: UserModel?

    
    /// The avatar's size, as a fraction of the screen width.
    var widthMultiplier: Double

    /// The decoded avatar, populated asynchronously by ``UserProfileCache``.
    @State private var image: UIImage?

    /// The avatar's size in points.
    private var side: CGFloat { width * widthMultiplier }

    var body: some View {
        Group {
            // MARK: - Photo, or placeholder while loading / without a photo
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.gray)
                    .frame(width: side, height: side)
                    .background(.white)
                    .clipShape(Circle())
            }
        }
        // MARK: - Accessibility and loading the photo
        // Read as the member's name, not as "image" or the placeholder symbol.
        .accessibilityElement(children: .ignore)
        .voiceOverLabel(user?.name ?? L10n.tr("Morador"))
        .accessibilityAddTraits(.isImage)
        .task(id: user?.recordID) {
            image = await UserProfileCache.shared.image(for: user)
        }
    }
}

#Preview {
    let user: UserModel = {
        let user = UserModel(name: "Dayô", tier: .tier1, ownerRecordName: "preview-owner")

        if let image = UIImage(systemName: "figure.wave")?.withTintColor(.systemBlue),
           let data = image.pngData() {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("fish")
            try? data.write(to: url)
            user.profilePicture = CKAsset(fileURL: url)
        }

        return user
    }()

    return UserProfilePictureTag(user: user, widthMultiplier: 0.15)
}
