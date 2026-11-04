//
//  RankVehicle.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 27/10/26.
//

import SwiftUI

/// What a member flies in the ranking sky. Climbing to a higher rank unlocks the next vehicle:
/// a small kite, a big kite, a plane and, at the top, a rocket.
enum RankVehicle: CaseIterable {
    case smallKite
    case bigKite
    case plane
    case rocket

    /// The vehicle a member at `tier` flies.
    init(tier: Tier) {
        switch tier.position {
        case ...2: self = .smallKite
        case 3...6: self = .bigKite
        case 7...10: self = .plane
        default: self = .rocket
        }
    }

    /// The first rank that has this vehicle.
    var unlockTier: Tier {
        switch self {
        case .smallKite: return .novatoDaCasa
        case .bigKite: return .escudeiroDaFaxina
        case .plane: return .protetorDoLar
        case .rocket: return .lendaDaCasa
        }
    }

    /// Name of the artwork in the asset catalog. While there is none, ``RankVehicleView`` draws a
    /// stand-in, so dropping an image with this name into the catalog is enough to replace it.
    var assetName: String {
        switch self {
        case .smallKite: return "rankVehicleSmallKite"
        case .bigKite: return "rankVehicleBigKite"
        case .plane: return "rankVehiclePlane"
        case .rocket: return "rankVehicleRocket"
        }
    }

    /// Size of the vehicle on the card.
    var size: CGSize {
        switch self {
        case .smallKite: return CGSize(width: 30, height: 56)
        case .bigKite: return CGSize(width: 46, height: 84)
        case .plane: return CGSize(width: 64, height: 50)
        case .rocket: return CGSize(width: 44, height: 70)
        }
    }

    /// The name VoiceOver reads.
    var accessibilityName: String {
        switch self {
        case .smallKite: return L10n.tr("pipa pequena")
        case .bigKite: return L10n.tr("pipa grande")
        case .plane: return L10n.tr("avião")
        case .rocket: return L10n.tr("foguete")
        }
    }
}

/// A vehicle drawn at its size: the artwork from the asset catalog, or a stand-in.
struct RankVehicleView: View {

    /// The vehicle to draw.
    let vehicle: RankVehicle

    var body: some View {
        Group {
            if UIImage(named: vehicle.assetName) != nil {
                Image(vehicle.assetName)
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
        switch vehicle {
        case .smallKite:
            KiteArt(color: .choreOrange).rotationEffect(.degrees(18))
        case .bigKite:
            KiteArt(color: .chorePurple).rotationEffect(.degrees(-14))
        case .plane:
            Image(systemName: "airplane")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.chorePurple)
                .rotationEffect(.degrees(-30))
        case .rocket:
            Image(systemName: "paperplane.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.tagRed)
        }
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
