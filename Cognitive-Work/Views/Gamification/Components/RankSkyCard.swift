//
//  RankSkyCard.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 27/10/26.
//

import SwiftUI
import CloudKit
import UIKit

/// The rewards tab's ranking
///
/// The card scrolls inside the rewards tab, which scrolls too. Two things keep the two scrolls
/// from fighting:
/// - The card opens on the member's rank (``initialAnchor(width:viewport:)``) and moves only itself
///   when it changes (``ScrollPosition``). `ScrollViewReader` used to do it, and its `scrollTo`
///   scrolls every enclosing scroll view, so the whole tab jumped to the card.
/// - The card doesn't bounce at its ends (``ScrollEdgeHandoff``). While it can still move, a drag
///   on it scrolls the sky; once it reaches the top or the bottom, a drag that way scrolls the tab,
///   instead of the card bouncing in place and holding on to it.
struct RankSkyCard: View {

    /// Every rank, lowest first, with the members at it (``GamificationCatalog/tiers``).
    let groups: [TierGroup]

    /// ``UserModel/ownerRecordName`` of the signed-in member, whose vehicle is highlighted.
    var myOwnerRecordName: String?

    /// When the clouds started to move.
    @State private var windStart = Date()

    /// Where the sky is scrolled. Moved by code only to center the member's rank. It starts with
    /// no target, so the initial anchor (``initialAnchor(width:viewport:)``) decides where it opens.
    @State private var position = ScrollPosition()

    /// Whether the card already appeared once, so coming back to the tab centers it again.
    @State private var hasAppeared = false

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
            let viewport = proxy.size.height

            ScrollView(.vertical, showsIndicators: false) {
                ZStack(alignment: .top) {
                    artwork(width: width)
                    cloudsLayer(width: width)
                    rows(width: width)
                }
                .frame(width: width, height: contentHeight(width: width), alignment: .top)
                .clipped()
                .background(ScrollEdgeHandoff())
            }
            .scrollPosition($position)
            // Opens on the member's rank. Scrolling to it in `onAppear` came too early: the scroll
            // view didn't know the sky's height yet, cut the offset short and left the card at its
            // end. The initial anchor is applied by SwiftUI once the content is laid out.
            .defaultScrollAnchor(initialAnchor(width: width, viewport: viewport), for: .initialOffset)
            // Coming back to the tab: back to the member's rank (the first appearance is the
            // anchor's job).
            .onAppear {
                if hasAppeared {
                    scrollToMe(width: width, viewport: viewport, animated: false)
                }
                hasAppeared = true
            }
            // The members load after the card appears (jump there), and the rank can change later
            // on (glide there).
            .onChange(of: myTier) { previous, _ in
                scrollToMe(width: width, viewport: viewport, animated: previous != nil)
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

            markers(for: group)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 8)
        }
    }

    /// Most vehicles one line holds; a rank with more members splits them into two lines.
    private static let maxVehiclesPerLine = 3

    /// How big the vehicles are drawn when a rank needs two lines, so both fit in its row.
    private static let twoLineScale: CGFloat = 0.45

    /// The members' vehicles at the end of the rank's line.
    ///
    /// Up to ``maxVehiclesPerLine`` members fly in one line, resting on the rank's line. With more,
    /// they split into two smaller lines (the first one takes the extra member), and the pair is
    /// centered on the rank's line, so they never run over the rank's name.
    @ViewBuilder
    private func markers(for group: TierGroup) -> some View {
        let vehicle = RankVehicle(tier: group.tier)

        if group.users.count <= Self.maxVehiclesPerLine {
            markerLine(group.users, tier: group.tier, scale: 1)
                .offset(y: -(vehicle.size.height / 2) + 6)
        } else {
            let firstLineCount = (group.users.count + 1) / 2
            VStack(spacing: 0) {
                markerLine(Array(group.users.prefix(firstLineCount)), tier: group.tier, scale: Self.twoLineScale)
                markerLine(Array(group.users.dropFirst(firstLineCount)), tier: group.tier, scale: Self.twoLineScale)
            }
        }
    }

    /// One line of vehicles, slightly overlapped, with the signed-in member's on top.
    private func markerLine(_ users: [UserModel], tier: Tier, scale: CGFloat) -> some View {
        HStack(spacing: -8 * scale) {
            ForEach(users, id: \.id) { user in
                marker(of: user, tier: tier, scale: scale)
                    .zIndex(user.ownerRecordName == myOwnerRecordName ? 1 : 0)
            }
        }
    }

    /// A member's vehicle and first name.
    ///
    /// - Parameter scale: `1` normally; smaller when the rank's members take two lines.
    private func marker(of user: UserModel, tier: Tier, scale: CGFloat) -> some View {
        let vehicle = RankVehicle(tier: tier)
        let isMe = user.ownerRecordName == myOwnerRecordName

        return VStack(spacing: 2) {
            RankVehicleView(vehicle: vehicle)
                .scaleEffect((isMe ? 1 : 0.85) * scale)
                .frame(width: vehicle.size.width * scale, height: vehicle.size.height * scale)

            Text(verbatim: user.name.split(separator: " ").first.map(String.init) ?? user.name)
                .font(.system(size: scale < 1 ? 10 : 12, weight: .bold))
                .foregroundStyle(Self.lineColor)
                .lineLimit(1)
                .padding(.horizontal, scale < 1 ? 4 : 6)
                .padding(.vertical, 1)
                .background(.white.opacity(0.8), in: Capsule())
        }
        .frame(maxWidth: RankVehicle.maxWidth * scale)
    }

    // MARK: - Scrolling and accessibility

    /// How far down the sky must be scrolled to center the member's rank, or `nil` while their
    /// rank isn't known (or the card has no size yet).
    ///
    /// - Parameters:
    ///   - width: The card's width, which sets the size of everything in it.
    ///   - viewport: The card's visible height.
    private func offsetToMe(width: CGFloat, viewport: CGFloat) -> (offset: CGFloat, maxOffset: CGFloat)? {
        guard width > 0, viewport > 0,
              let myTier,
              let index = groups.firstIndex(where: { $0.tier == myTier })
        else { return nil }

        // Same layout as `rows(width:)`: the rows go from the highest rank down, and the first
        // one is centered at `firstRowCenter`.
        let row = groups.count - 1 - index
        let rowCenter = Self.firstRowCenter * width + CGFloat(row) * rowHeight(width: width)
        let maxOffset = max(contentHeight(width: width) - viewport, 0)
        return (min(max(rowCenter - viewport / 2, 0), maxOffset), maxOffset)
    }

    /// Where the sky opens: the member's rank in the middle, or the top while it isn't known.
    ///
    /// A unit point of the content lines up with the same point of the card, so the offset is
    /// expressed as a fraction of the most the sky can scroll.
    private func initialAnchor(width: CGFloat, viewport: CGFloat) -> UnitPoint {
        guard let target = offsetToMe(width: width, viewport: viewport), target.maxOffset > 0 else {
            return .top
        }
        return UnitPoint(x: 0.5, y: target.offset / target.maxOffset)
    }

    /// Centers the card on the member's rank, without moving the screen around it.
    ///
    /// - Parameters:
    ///   - width: The card's width.
    ///   - viewport: The card's visible height.
    ///   - animated: Whether the sky glides there (the rank changed) or jumps.
    private func scrollToMe(width: CGFloat, viewport: CGFloat, animated: Bool) {
        guard let target = offsetToMe(width: width, viewport: viewport) else { return }

        if animated {
            withAnimation(.snappy) { position.scrollTo(y: target.offset) }
        } else {
            position.scrollTo(y: target.offset)
        }
    }

    /// "Pipa dragão chinês: Ana. Pipa Tradicional II: Bia, Caio." — only the ranks that have members.
    private var accessibilitySummary: String {
        groups.reversed()
            .filter { !$0.users.isEmpty }
            .map { "\($0.tier.displayName): \($0.users.map(\.name).joined(separator: ", "))" }
            .joined(separator: ". ")
    }
}

/// Turns off the bounce of the scroll view it is placed in, so that scroll hands the drag over to
/// the scroll view around it once it reaches an end (UIKit only lets the outer one take a drag
/// when the inner one can't move, and a bouncing scroll view always can).
///
/// SwiftUI has no modifier for it: ``SwiftUI/View/scrollBounceBehavior(_:axes:)`` only stops the
/// bounce when the content fits, and the sky never does. Placed as the content's background, it
/// finds the `UIScrollView` among its superviews, and sets it again on every layout in case
/// SwiftUI resets it.
private struct ScrollEdgeHandoff: UIViewRepresentable {

    func makeUIView(context: Context) -> UIView {
        let view = FinderView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    /// Looks up the enclosing scroll view whenever it is placed or laid out.
    private final class FinderView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            disableBounce()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            disableBounce()
        }

        private func disableBounce() {
            var view = superview
            while let current = view, !(current is UIScrollView) {
                view = current.superview
            }
            guard let scrollView = view as? UIScrollView, scrollView.bounces else { return }
            scrollView.bounces = false
        }
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

#Preview("Uma linha por ranking") {
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

#Preview("Mais de 3 no mesmo ranking") {
    let names = ["Ana", "Bia", "Caio", "Davi", "Edu", "Fê", "Gabi"]
    let crowded = names.enumerated().map { index, name in
        UserModel(name: name, tier: .vigiaDaCozinha, points: 100 + index, ownerRecordName: name.lowercased())
    }
    let users = crowded + [
        UserModel(name: "Hugo", tier: .aprendiz, points: 30, ownerRecordName: "hugo"),
        UserModel(name: "Iara", tier: .aprendiz, points: 32, ownerRecordName: "iara"),
        UserModel(name: "João", tier: .aprendiz, points: 34, ownerRecordName: "joao"),
        UserModel(name: "Lia", tier: .aprendiz, points: 36, ownerRecordName: "lia")
    ]
    RankSkyCard(
        groups: Tier.allCases.map { tier in TierGroup(tier: tier, users: users.filter { $0.tier == tier }) },
        myOwnerRecordName: "bia"
    )
    .padding(30)
}

#Preview("Uma pessoa em cada ranking") {
    let names = ["Ana", "Bia", "Caio", "Davi", "Edu", "Fê", "Gabi", "Hugo", "Iara", "João", "Lia", "Malu", "Nina"]
    let users = Tier.allCases.enumerated().map { index, tier in
        UserModel(name: names[index], tier: tier, points: index * 30, ownerRecordName: names[index].lowercased())
    }
    // The card scrolls: drag it to see every rank's kite.
    RankSkyCard(
        groups: Tier.allCases.map { tier in TierGroup(tier: tier, users: users.filter { $0.tier == tier }) },
        myOwnerRecordName: "edu"
    )
    .padding(30)
}
