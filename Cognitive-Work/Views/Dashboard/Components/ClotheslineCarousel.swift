//
//  ClotheslineCarousel.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 26/10/26.
//

import SwiftUI

/// Chores hanging by clothespins on a sagging rope that runs across the card. Swipe sideways to
/// see more of them; each one follows the rope's curve as it moves along it.
struct ClotheslineCarousel: View {
    let tiles: [ClotheslineViewModel.Tile]
    let onSelect: (String) -> Void
    
    static let height: CGFloat = 112
    
    private static let scrollSpace = "clothesline"
    private static let ropeEndHeight: CGFloat = 14
    private static let ropeSag: CGFloat = 18
    private static let tileSpacing: CGFloat = 34
    private static let firstTileInset: CGFloat = 24
    private static let tilts: [Double] = [-6, 3, -2, 6]
    
    var body: some View {
        GeometryReader { proxy in
            let rope = Rope(width: proxy.size.width, endHeight: Self.ropeEndHeight, sag: Self.ropeSag)
            
            ZStack(alignment: .topLeading) {
                rope.path
                    .stroke(.black, lineWidth: 1.2)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Self.tileSpacing) {
                        ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                            hangingTile(tile, tilt: Self.tilts[index % Self.tilts.count], on: rope)
                        }
                    }
                    .scrollTargetLayout()
                }
                .frame(height: Self.height)
                .coordinateSpace(name: Self.scrollSpace)
                .scrollTargetBehavior(.viewAligned)
                .contentMargins(.horizontal, Self.firstTileInset, for: .scrollContent)
            }
        }
        .frame(height: Self.height)
    }
    
    private func hangingTile(_ tile: ClotheslineViewModel.Tile, tilt: Double, on rope: Rope) -> some View {
        GeometryReader { tileProxy in
            let x = tileProxy.frame(in: .named(Self.scrollSpace)).midX
            
            Button { onSelect(tile.id) } label: { HangingTile(tile: tile) }
                .buttonStyle(.plain)
                .rotationEffect(.degrees(tilt), anchor: HangingTile.pinAnchor)
                .offset(y: rope.height(atX: x) - HangingTile.pinCenterY)
                .accessibilityLabel(tile.name)
                .accessibilityAddTraits(tile.isSelected ? .isSelected : [])
        }
        .frame(width: HangingTile.width, height: Self.height)
    }
}

/// A rope hanging between two points at the same height, sagging in the middle.
private struct Rope {
    let width: CGFloat
    let endHeight: CGFloat
    let sag: CGFloat
    
    var path: Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: endHeight))
            path.addQuadCurve(
                to: CGPoint(x: width, y: endHeight),
                control: CGPoint(x: width / 2, y: endHeight + 2 * sag)
            )
        }
    }
    
    func height(atX x: CGFloat) -> CGFloat {
        guard width > 0 else { return endHeight }
        let progress = min(max(x / width, 0), 1)
        return endHeight + 4 * sag * progress * (1 - progress)
    }
}

/// A chore on the line: a fixed-size tile with its icon, held by a clothespin.
private struct HangingTile: View {
    let tile: ClotheslineViewModel.Tile
    
    static let width: CGFloat = 58
    private static let bodyHeight: CGFloat = 68
    private static let pinSize = CGSize(width: 12, height: 26)
    private static let iconSize: CGFloat = 36
    
    static let pinCenterY = pinSize.height / 2
    static let pinAnchor = UnitPoint(x: 0.5, y: pinCenterY / (pinCenterY + bodyHeight))
    
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tile.fillColor)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.5), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.1), radius: 3, y: 2)
                .frame(width: Self.width, height: Self.bodyHeight)
                .overlay {
                    SymbolImage(name: tile.symbol)
                        .foregroundStyle(.black.opacity(0.8))
                        .frame(width: Self.iconSize, height: Self.iconSize)
                }
                .padding(.top, Self.pinCenterY)
            
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(tile.pinColor)
                .frame(width: Self.pinSize.width, height: Self.pinSize.height)
        }
        .frame(width: Self.width, height: Self.pinCenterY + Self.bodyHeight)
    }
}
