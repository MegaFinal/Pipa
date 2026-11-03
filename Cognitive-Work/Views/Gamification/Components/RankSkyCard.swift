//
//  RankSkyCard.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 27/10/26.
//

import SwiftUI
import CloudKit

/// The rewards tab's ranking
struct RankSkyCard: View {

    /// Every rank, lowest first, with the members at it (``GamificationCatalog/tiers``).
    let groups: [TierGroup]

    /// ``UserModel/ownerRecordName`` of the signed-in member, whose vehicle is highlighted.
    var myOwnerRecordName: String?

    /// When the clouds started to move.
    @State private var windStart = Date()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Height of the card.
    static let height: CGFloat = 315

    private static let firstRowCenter: CGFloat = 0.690
    private static let rowSpacing: CGFloat = 0.3

    /// The color of the rank names and lines
    private static let lineColor = Color(red: 0.27, green: 0.38, blue: 0.64)
    private static let artworkName = "rankBackground"
    private static let artworkSize = CGSize(width: 1029, height: 3767)
    private static let backHillPeakY: CGFloat = 3350
    private static let lowestRankOnHill: CGFloat = 0.1
    private static var lowestRankY: CGFloat {
        backHillPeakY + (artworkSize.height - backHillPeakY) * lowestRankOnHill
    }

    /// Where the artwork is split to insert more sky
    private static let skySplitY: CGFloat = 2700

    /// The flat color of the artwork's sky at ``skySplitY``.
    private static let skyColor = Color(red: 223 / 255, green: 238 / 255, blue: 254 / 255)

    /// The clouds, placed as in the design
    private static let clouds: [RankCloud] = [
        RankCloud(asset: "rankCloudDark", x: 0.170, row: 0.41, width: 0.936),
        RankCloud(asset: "rankCloudMid", x: 0.831, row: 0.93, width: 0.994),
        RankCloud(asset: "rankCloudLight", x: 0.167, row: 2.61, width: 0.912),
        RankCloud(asset: "rankCloudLight", x: 1.012, row: 2.74, width: 0.729),
        RankCloud(asset: "rankCloudLight", x: 0.278, row: 4.35, width: 0.708),
        RankCloud(asset: "rankCloudLight", x: 0.986, row: 4.11, width: 0.556),
        RankCloud(asset: "rankCloudLight", x: 0.704, row: 5.51, width: 0.708),
        RankCloud(asset: "rankCloudLight", x: 0.243, row: 5.50, width: 0.164),
        RankCloud(asset: "rankCloudLight", x: 0.740, row: 6.54, width: 0.222),
        RankCloud(asset: "rankCloudLight", x: 0.360, row: 7.18, width: 0.471),
        RankCloud(asset: "rankCloudLight", x: 0.743, row: 8.15, width: 0.471),
        RankCloud(asset: "rankCloudLight", x: 0.483, row: 8.52, width: 0.225),
        RankCloud(asset: "rankCloudLight", x: 0.163, row: 9.35, width: 0.477),
        RankCloud(asset: "rankCloudLight", x: 0.839, row: 9.63, width: 0.474),
        RankCloud(asset: "rankCloudLight", x: 0.347, row: 10.25, width: 0.249)
    ]

    /// The rank of the signed-in member.
    private var myTier: Tier? {
        guard let myOwnerRecordName else { return nil }
        return groups.first { $0.users.contains { $0.ownerRecordName == myOwnerRecordName } }?.tier
    }

    private func artworkScale(width: CGFloat) -> CGFloat { width / Self.artworkSize.width }

    private func extraSkyHeight(width: CGFloat) -> CGFloat {
        let lowestRowCenter = (Self.firstRowCenter + CGFloat(max(groups.count - 1, 0)) * Self.rowSpacing) * width
        let lowestRankY = Self.lowestRankY * artworkScale(width: width)
        return max(0, lowestRowCenter - lowestRankY)
    }

    private func contentHeight(width: CGFloat) -> CGFloat {
        Self.artworkSize.height * artworkScale(width: width) + extraSkyHeight(width: width)
    }

    private func rowHeight(width: CGFloat) -> CGFloat {
        Self.rowSpacing * width
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            ScrollViewReader { reader in
                ScrollView(.vertical, showsIndicators: false) {
                    ZStack(alignment: .top) {
                        artwork(width: width)
                        cloudsLayer(width: width)
                        rows(width: width)
                    }
                    .frame(width: width, height: contentHeight(width: width), alignment: .top)
                    .clipped()
                }
                .onAppear { scrollToMe(reader, animated: false) }
                .onChange(of: myTier) { scrollToMe(reader, animated: true) }
            }
        }
        .frame(height: Self.height)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
        // MARK: - VoiceOver
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: L10n.tr("Ranking da casa")))
        .accessibilityValue(Text(verbatim: accessibilitySummary))
    }

    // MARK: - Artwork

    /// The background artwork
    private func artwork(width: CGFloat) -> some View {
        let scale = artworkScale(width: width)
        let fullHeight = Self.artworkSize.height * scale
        let topHeight = Self.skySplitY * scale

        return VStack(spacing: 0) {
            artworkImage(width: width, height: fullHeight)
                .frame(width: width, height: topHeight, alignment: .top)
                .clipped()

            Self.skyColor.frame(width: width, height: extraSkyHeight(width: width))

            artworkImage(width: width, height: fullHeight)
                .frame(width: width, height: fullHeight - topHeight, alignment: .bottom)
                .clipped()
        }
        .background(Self.skyColor)
        .accessibilityHidden(true)
    }

    private func artworkImage(width: CGFloat, height: CGFloat) -> some View {
        Image(Self.artworkName)
            .resizable()
            .frame(width: width, height: height)
    }

    /// The clouds, over the artwork and under the ranks' names
    private func cloudsLayer(width: CGFloat) -> some View {
        let height = contentHeight(width: width)
        return TimelineView(.animation(paused: reduceMotion)) { timeline in
            let seconds = timeline.date.timeIntervalSince(windStart)
            ZStack(alignment: .topLeading) {
                ForEach(Array(Self.clouds.enumerated()), id: \.offset) { index, cloud in
                    let size = cloud.width * width
                    let left = cloud.x * width - size / 2
                    Image(cloud.asset)
                        .resizable()
                        .frame(width: size, height: size * RankCloud.aspectRatio)
                        .offset(
                            x: left + wind(cloud, index: index, width: width, seconds: reduceMotion ? 0 : seconds),
                            y: (Self.firstRowCenter + cloud.row * Self.rowSpacing) * width - size * RankCloud.aspectRatio / 2
                        )
                }
            }
            .frame(width: width, height: height, alignment: .topLeading)
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipped()
        .accessibilityHidden(true)
    }

    /// How far the wind has moved a cloud from its place in the design after `seconds`.
    private func wind(_ cloud: RankCloud, index: Int, width: CGFloat, seconds: TimeInterval) -> CGFloat {
        let size = cloud.width * width
        let speed = (0.016 + CGFloat((index * 3) % 5) * 0.006) * width
        let travel = speed * CGFloat(seconds)

        if cloud.width > 0.9 {
            return CGFloat(sin(seconds * 2 * .pi / 40 + Double(index))) * width * 0.08
        }

        let left = cloud.x * width - size / 2
        let span = width + size
        let moved = (left + travel + size).truncatingRemainder(dividingBy: span)
        return moved - size - left
    }

    // MARK: - Ranks

    /// The ranks as lines
    private func rows(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: Self.firstRowCenter * width - rowHeight(width: width) / 2)

            ForEach(groups.reversed()) { group in
                row(for: group, width: width)
                    .frame(width: width, height: rowHeight(width: width))
                    .id(group.tier)
            }
        }
        .frame(width: width)
    }

    /// One rank: its name followed by a dotted line, and its members' vehicles at the end of it.
    private func row(for group: TierGroup, width: CGFloat) -> some View {
        let color = group.tier.position >= Tier.allCases.count - 2 ? Color.white.opacity(0.9) : Self.lineColor

        return ZStack {
            HStack(spacing: 7) {
                Text(verbatim: group.tier.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                    .fixedSize()

                RankLine()
                    .stroke(color.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [1.5, 3]))
                    .frame(height: 1)
            }
            .padding(.horizontal, 20)

            HStack(spacing: -8) {
                ForEach(group.users, id: \.id) { user in
                    marker(of: user, tier: group.tier)
                        .zIndex(user.ownerRecordName == myOwnerRecordName ? 1 : 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 8)
        }
    }

    /// A member's vehicle
    private func marker(of user: UserModel, tier: Tier) -> some View {
        let vehicle = RankVehicle(tier: tier)
        let isMe = user.ownerRecordName == myOwnerRecordName

        return VStack(spacing: 2) {
            RankVehicleView(vehicle: vehicle)
                .scaleEffect(isMe ? 1 : 0.85)
                .shadow(color: .black.opacity(isMe ? 0.25 : 0.12), radius: 3, x: 0, y: 2)

            Text(verbatim: user.name.split(separator: " ").first.map(String.init) ?? user.name)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Self.lineColor)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.white.opacity(0.8), in: Capsule())
        }
        .frame(maxWidth: 64)
        .offset(y: -(vehicle.size.height / 2) + 6)
    }

    // MARK: - Scrolling and accessibility

    /// Centers the card on the member's rank.
    private func scrollToMe(_ reader: ScrollViewProxy, animated: Bool) {
        guard let myTier else { return }
        if animated {
            withAnimation(.snappy) { reader.scrollTo(myTier, anchor: .center) }
        } else {
            reader.scrollTo(myTier, anchor: .center)
        }
    }

    /// "Alma da casa: Ana. Aprendiz: Bia, Caio." — only the ranks that have members.
    private var accessibilitySummary: String {
        groups.reversed()
            .filter { !$0.users.isEmpty }
            .map { "\($0.tier.displayName): \($0.users.map(\.name).joined(separator: ", "))" }
            .joined(separator: ". ")
    }
}

/// A cloud's place on the card, from the design.
private struct RankCloud {
    static let aspectRatio: CGFloat = 434.0 / 880.0
    let asset: String
    let x: CGFloat
    let row: CGFloat
    let width: CGFloat
}

/// A horizontal line through the middle of its rectangle, stroked dashed by the caller.
private struct RankLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

#Preview {
    let users = [
        UserModel(name: "Ana", tier: .aprendiz, points: 30, ownerRecordName: "ana"),
        UserModel(name: "Bia", tier: .vigiaDaCozinha, points: 105, ownerRecordName: "bia"),
        UserModel(name: "Caio Souza", tier: .vigiaDaCozinha, points: 110, ownerRecordName: "caio"),
        UserModel(name: "Davi", tier: .cavaleiroDoRodo, points: 210, ownerRecordName: "davi"),
        UserModel(name: "Edu", tier: .almaDaCasa, points: 320, ownerRecordName: "edu")
    ]
    RankSkyCard(
        groups: Tier.allCases.map { tier in TierGroup(tier: tier, users: users.filter { $0.tier == tier }) },
        myOwnerRecordName: "ana"
    )
    .padding(30)
}
