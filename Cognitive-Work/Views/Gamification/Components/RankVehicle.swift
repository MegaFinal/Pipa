//
//  RankVehicle.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 27/10/26.
//

import SwiftUI

/// What a member flies in the ranking sky: each rank has its own kite, from the small
/// traditional one at the bottom to the Chinese dragon at the top.
///
/// The artwork lives in `Assets.xcassets/Ranking`, one image per rank (``assetName``). The ranks
/// that don't have one yet (14 Bis and the dragon) draw a stand-in, so dropping an image with
/// that name into the catalog is enough to replace it.
struct RankVehicle: Equatable {

    /// The rank this vehicle belongs to.
    let tier: Tier

    /// The vehicle a member at `tier` flies.
    init(tier: Tier) {
        self.tier = tier
    }

    /// Name of the artwork in the asset catalog, or `nil` while the rank has none.
    var assetName: String? {
        switch tier {
        case .novatoDaCasa: "tradicional"
        case .aprendiz: "tradicional_II"
        case .ajudanteOficial: "tradicional_III"
        case .escudeiroDaFaxina: "delta_I"
        case .vigiaDaCozinha: "delta_II"
        case .sentinelaDaSala: "delta_III"
        case .guardiaoDaCasa: "andorinha_I"
        case .protetorDoLar: "andorinha_II"
        case .cavaleiroDoRodo: "andorinha_III"
        case .mestreDaCasa, .sabioDoLar, .lendaDaCasa, .almaDaCasa: nil
        }
    }

    /// Size of the vehicle on the card, following each artwork's proportions. Within a family
    /// (traditional, delta, swallow) the higher rank is a bit bigger. Never wider than
    /// ``maxWidth``, the width of a member's marker.
    var size: CGSize {
        switch tier {
        // Traditional: tall diamonds with a long tail.
        case .novatoDaCasa: CGSize(width: 31, height: 80)
        case .aprendiz: CGSize(width: 31, height: 86)
        case .ajudanteOficial: CGSize(width: 37, height: 92)
        // Delta: wide triangles.
        case .escudeiroDaFaxina: CGSize(width: 76, height: 56)
        case .vigiaDaCozinha: CGSize(width: 80, height: 48)
        case .sentinelaDaSala: CGSize(width: 84, height: 44)
        // Swallow: wide, with long wings.
        case .guardiaoDaCasa: CGSize(width: 78, height: 45)
        case .protetorDoLar: CGSize(width: 80, height: 53)
        case .cavaleiroDoRodo: CGSize(width: 84, height: 47)
        // No artwork yet (stand-ins).
        case .mestreDaCasa, .sabioDoLar, .lendaDaCasa: CGSize(width: 84, height: 66)
        case .almaDaCasa: CGSize(width: 58, height: 92)
        }
    }

    /// The widest a vehicle gets: a member's marker is this wide.
    static let maxWidth: CGFloat = 84

    /// The name VoiceOver reads.
    var accessibilityName: String {
        switch tier {
        case .novatoDaCasa, .aprendiz, .ajudanteOficial: L10n.tr("pipa tradicional")
        case .escudeiroDaFaxina, .vigiaDaCozinha, .sentinelaDaSala: L10n.tr("pipa delta")
        case .guardiaoDaCasa, .protetorDoLar, .cavaleiroDoRodo: L10n.tr("pipa andorinha")
        case .mestreDaCasa, .sabioDoLar, .lendaDaCasa: L10n.tr("14 Bis")
        case .almaDaCasa: L10n.tr("pipa dragão chinês")
        }
    }
}

/// A vehicle drawn at its size: the artwork from the asset catalog, or a stand-in.
struct RankVehicleView: View {

    /// The vehicle to draw.
    let vehicle: RankVehicle

    var body: some View {
        Group {
            if let assetName = vehicle.assetName, UIImage(named: assetName) != nil {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
            } else {
                standIn
            }
        }
        .frame(width: vehicle.size.width, height: vehicle.size.height)
        .accessibilityHidden(true)
    }

    /// A drawing made of shapes and symbols, until the artwork exists.
    @ViewBuilder
    private var standIn: some View {
        switch vehicle.tier {
        case .almaDaCasa:
            KiteArt(color: .tagRed).rotationEffect(.degrees(-10))
        case .mestreDaCasa, .sabioDoLar, .lendaDaCasa:
            Image(systemName: "airplane")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.chorePurple)
                .rotationEffect(.degrees(-30))
        default:
            KiteArt(color: .choreOrange).rotationEffect(.degrees(18))
        }
    }
}

// MARK: - Previews

#Preview("Pipa de cada ranking") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 16)], spacing: 24) {
            ForEach(Tier.allCases, id: \.self) { tier in
                VStack(spacing: 10) {
                    RankVehicleView(vehicle: RankVehicle(tier: tier))
                        .frame(height: 96)
                    Text(verbatim: tier.displayName)
                        .font(.system(size: 12, weight: .bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color(red: 0.27, green: 0.38, blue: 0.64))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(red: 223 / 255, green: 238 / 255, blue: 254 / 255), in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .padding(20)
    }
}

// MARK: - Kite

/// A kite: the diamond, its two spars and a wavy tail.
private struct KiteArt: View {

    /// The color of the kite and its tail.
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let kiteHeight = height * 0.68

            KiteTail()
                .stroke(color.opacity(0.9), lineWidth: 1.5)
                .frame(width: width * 0.4, height: height * 0.32)
                .position(x: width / 2, y: kiteHeight + height * 0.16 - 1)

            KiteShape()
                .fill(color)
                .frame(width: width, height: kiteHeight)
                .position(x: width / 2, y: kiteHeight / 2)

            KiteSpars()
                .stroke(.white.opacity(0.6), lineWidth: 1)
                .frame(width: width, height: kiteHeight)
                .position(x: width / 2, y: kiteHeight / 2)
        }
    }
}

/// The kite's diamond.
private struct KiteShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.38))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.38))
        path.closeSubpath()
        return path
    }
}

/// The two crossing spars of the kite.
private struct KiteSpars: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.38))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.38))
        return path
    }
}

/// The kite's tail: a line that wiggles twice on its way down.
private struct KiteTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.midY),
            control1: CGPoint(x: rect.maxX, y: rect.height * 0.15),
            control2: CGPoint(x: rect.minX, y: rect.height * 0.35)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: rect.height * 0.65),
            control2: CGPoint(x: rect.minX, y: rect.height * 0.85)
        )
        return path
    }
}
