//
//  RoomTextureBackground.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 28/09/26.
//

import SwiftUI

/// A room card's background: the room's palette color with its texture on top.
struct RoomTextureBackground: View {
    /// The background color.
    let color: RoomColor
    /// The texture drawn over the color.
    let pattern: RoomTexturePattern
    
    /// Enlargement of this texture; each card picks the one that fits its size.
    let zoom: CGFloat
    
    /// When set, the texture is drawn in a square of this size, regardless of the frame
    /// of whoever uses it.
    let fixedSize: CGFloat?
    
    /// The texture is always drawn at this opacity, over the room's color.
    var textureOpacity: Double = 0.2
    
    /// Higher means bigger, fewer shapes.
    static let textureZoom: CGFloat = 2.5
    
    /// Creates the background from a color and a texture.
    init(color: RoomColor, pattern: RoomTexturePattern,
         zoom: CGFloat = textureZoom, fixedSize: CGFloat? = nil) {
        self.color = color
        self.pattern = pattern
        self.zoom = zoom
        self.fixedSize = fixedSize
    }
    
    /// Creates the background of `room` (its color and texture), optionally at a fixed size.
    init(room: RoomModel, zoom: CGFloat = textureZoom, fixedSize: CGFloat? = nil) {
        self.init(
            color: room.color,
            pattern: room.texturePattern,
            zoom: zoom,
            fixedSize: fixedSize,
        )
    }
    
    /// Creates the background of `room` (its color and texture).
    init(room: RoomModel, zoom: CGFloat = textureZoom) {
        self.init(color: room.color, pattern: room.texturePattern, zoom: zoom)
    }
    
    var body: some View {
        // MARK: - Room color with the texture on top
        color.uiColor
            .overlay { texture }
            .clipped()
    }
    
    /// The texture image, either at a fixed size or filling the available space.
    @ViewBuilder
    private var texture: some View {
        let image = Image(pattern.assetName(for: color))
            .resizable()
            .scaledToFill()
        
        Group {
            if let fixedSize {
                image
                    .frame(width: fixedSize, height: fixedSize)
                    .clipped()
            } else {
                image
            }
        }
        .scaleEffect(zoom)
        .opacity(textureOpacity)
        .allowsHitTesting(false)
        // Purely decorative: the asset name ("purple.clouds") must not be read aloud.
        .accessibilityDecorative()
    }
}

#Preview {
    HStack {
        RoomTextureBackground(color: .purple, pattern: .clouds)
        RoomTextureBackground(color: .orange, pattern: .stars)
        RoomTextureBackground(color: .green, pattern: .worms)
    }
    .frame(height: 300)
    .padding()
}
