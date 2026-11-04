//
//  CouponCelebration.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 20/10/26.
//

import SwiftUI

/// A full-screen celebration for a coupon just bought (``FocusedCouponView``): a burst of
/// confetti, stars and sparkles from the ticket, two confetti cannons from the bottom corners and
/// a rain of confetti from the top.
///
/// Every piece is thrown, falls with gravity, spins, flutters and fades out; all of it is drawn
/// in one `Canvas`, driven by a `TimelineView` that pauses once it's over (``duration``). Purely
/// decorative: hidden from accessibility and from touches.
struct CouponCelebration: View {

    /// Colors the pieces are picked from.
    var colors: [Color]

    /// Where the burst comes from, in global coordinates (the ticket's center); the middle of the
    /// view when `nil`.
    var burstCenter: CGPoint? = nil

    /// Seconds from the start to the last piece fading out.
    static let duration: Double = 3

    /// The shape of a piece.
    private enum Kind {
        case strip, dot, star, symbolStar, sparkle, heart

        /// The SF Symbol for symbol pieces, or `nil` for pieces drawn by hand.
        var symbolName: String? {
            switch self {
            case .symbolStar: return "star.fill"
            case .sparkle: return "sparkle"
            case .heart: return "heart.fill"
            default: return nil
            }
        }
    }

    /// Where a piece is thrown from.
    private enum Start {
        case burst, bottomLeading, bottomTrailing
        /// Above the top edge, at this fraction of the width.
        case top(Double)
    }

    /// One piece of confetti and how it moves.
    private struct Piece {
        /// Its shape.
        let kind: Kind
        /// Index into ``colors``.
        let color: Int
        /// Where it starts.
        let start: Start
        /// Initial velocity, points per second.
        let velocity: CGVector
        /// Downward acceleration, points per second squared.
        let gravity: Double
        /// Side-to-side drift while falling: amplitude (points) and frequency (radians per second).
        let sway: Double
        /// How fast it drifts side to side.
        let swayRate: Double
        /// Radians per second.
        let spin: Double
        /// How fast it flips around its vertical axis.
        let flutter: Double
        /// Its size, in points.
        let size: Double
        /// Seconds before it appears.
        let delay: Double
        /// Seconds it stays on screen after appearing.
        let lifetime: Double
    }

    /// Every piece of the celebration, made once in ``launch()``.
    @State private var pieces: [Piece] = []
    /// When the celebration started.
    @State private var start = Date.now
    /// Stops the timeline once the celebration is over.
    @State private var isRunning = true
    /// This view's frame on screen, to turn ``burstCenter`` into local points.
    @State private var globalFrame: CGRect = .zero

    var body: some View {
        // MARK: - Draws every piece on each frame
        TimelineView(.animation(minimumInterval: nil, paused: !isRunning)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start)
            Canvas { context, size in
                let burst = burstCenter.map {
                    CGPoint(x: $0.x - globalFrame.minX, y: $0.y - globalFrame.minY)
                } ?? CGPoint(x: size.width / 2, y: size.height / 2)
                for piece in pieces {
                    draw(piece, at: elapsed - piece.delay, burst: burst, size: size, in: context)
                }
            }
        }
        // MARK: - Full screen, no touches, no VoiceOver
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { globalFrame = $0 }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear(perform: launch)
    }

    // MARK: - Drawing

    /// The point a piece is thrown from.
    private func position(of start: Start, burst: CGPoint, size: CGSize) -> CGPoint {
        switch start {
        case .burst: return burst
        case .bottomLeading: return CGPoint(x: -10, y: size.height + 10)
        case .bottomTrailing: return CGPoint(x: size.width + 10, y: size.height + 10)
        case .top(let fraction): return CGPoint(x: size.width * fraction, y: -20)
        }
    }

    /// Draws one piece at `time` seconds after it appeared (moves, spins, flutters and fades it).
    private func draw(_ piece: Piece, at time: Double, burst: CGPoint, size: CGSize, in context: GraphicsContext) {
        guard time > 0, time < piece.lifetime, !colors.isEmpty else { return }

        let origin = position(of: piece.start, burst: burst, size: size)
        let x = origin.x + piece.velocity.dx * time + piece.sway * sin(time * piece.swayRate)
        let y = origin.y + piece.velocity.dy * time + 0.5 * piece.gravity * time * time

        var context = context
        context.opacity = min(1, (piece.lifetime - time) / 0.6)
        context.translateBy(x: x, y: y)
        context.rotate(by: .radians(piece.spin * time))

        let color = colors[piece.color % colors.count]
        let size = piece.size
        switch piece.kind {
        case .strip:
            context.scaleBy(x: cos(time * piece.flutter), y: 1)
            let strip = CGRect(x: -size * 0.3, y: -size * 0.7, width: size * 0.6, height: size * 1.4)
            context.fill(Path(roundedRect: strip, cornerRadius: 1.5), with: .color(color))
        case .dot:
            let dot = CGRect(x: -size / 2, y: -size / 2, width: size, height: size)
            context.fill(Path(ellipseIn: dot), with: .color(color))
        case .star:
            context.fill(Self.star(radius: size), with: .color(color))
        case .symbolStar, .sparkle, .heart:
            guard let name = piece.kind.symbolName else { return }
            var image = context.resolve(Image(systemName: name))
            image.shading = .color(color)
            let side = size * 2
            context.draw(image, in: CGRect(x: -side / 2, y: -side / 2, width: side, height: side))
        }
    }

    // MARK: - Launching

    /// Creates all the pieces and starts the animation; stops it after ``duration``.
    private func launch() {
        var all: [Piece] = []

        // Burst from the ticket, mostly upward.
        for _ in 0..<80 {
            let angle = Double.random(in: 0...1) < 0.8
                ? Double.random(in: -.pi ... 0)
                : Double.random(in: 0 ... .pi)
            let speed = Double.random(in: 300...900)
            all.append(piece(
                start: .burst,
                velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                gravity: 1000, delay: .random(in: 0...0.1), lifetime: .random(in: 1.8...2.4)
            ))
        }

        // Cannons from the bottom corners, aimed up and inward.
        for (side, direction) in [(Start.bottomLeading, 1.0), (.bottomTrailing, -1.0)] {
            for _ in 0..<40 {
                // About 60° up, toward the middle.
                let angle = -Double.pi / 3 + .random(in: -0.25...0.25)
                let speed = Double.random(in: 900...1400)
                all.append(piece(
                    start: side,
                    velocity: CGVector(dx: cos(angle) * speed * direction, dy: sin(angle) * speed),
                    gravity: 900, delay: .random(in: 0.15...0.35), lifetime: .random(in: 2.2...2.7)
                ))
            }
        }

        // Rain from the top.
        for _ in 0..<60 {
            all.append(piece(
                start: .top(.random(in: 0...1)),
                velocity: CGVector(dx: 0, dy: .random(in: 140...280)),
                gravity: 80, delay: .random(in: 0.2...0.9), lifetime: Self.duration - 0.9,
                sway: .random(in: 15...45)
            ))
        }

        pieces = all
        start = .now
        isRunning = true
        Task {
            try? await Task.sleep(for: .seconds(Self.duration + 0.2))
            isRunning = false
        }
    }

    /// Creates one piece with a random shape, color, spin and size.
    private func piece(
        start: Start,
        velocity: CGVector,
        gravity: Double,
        delay: Double,
        lifetime: Double,
        sway: Double = 0
    ) -> Piece {
        // Mostly confetti, with stars, sparkles and hearts mixed in.
        let roll = Double.random(in: 0...1)
        let kind: Kind = switch roll {
        case ..<0.45: .strip
        case ..<0.6: .dot
        case ..<0.75: .star
        case ..<0.87: .symbolStar
        case ..<0.95: .sparkle
        default: .heart
        }
        let isSymbol = kind.symbolName != nil
        return Piece(
            kind: kind,
            color: Int.random(in: 0..<max(colors.count, 1)),
            start: start,
            velocity: velocity,
            gravity: gravity,
            sway: sway,
            swayRate: .random(in: 2...4),
            spin: isSymbol ? .random(in: -3...3) : .random(in: -10...10),
            flutter: .random(in: 6...14),
            size: isSymbol || kind == .star ? .random(in: 8...13) : .random(in: 7...12),
            delay: delay,
            lifetime: lifetime
        )
    }

    /// A five-pointed star centered on the origin.
    private static func star(radius: Double) -> Path {
        var path = Path()
        let inner = radius * 0.45
        for point in 0..<10 {
            let r = point.isMultiple(of: 2) ? radius : inner
            let angle = Double(point) * .pi / 5 - .pi / 2
            let vertex = CGPoint(x: cos(angle) * r, y: sin(angle) * r)
            if point == 0 { path.move(to: vertex) } else { path.addLine(to: vertex) }
        }
        path.closeSubpath()
        return path
    }
}

#Preview {
    CouponCelebration(colors: [.chorePurple, .choreYellow, .choreOrange, .choreGreen, .choreBlue])
        .ignoresSafeArea()
}
