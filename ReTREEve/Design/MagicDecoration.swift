//  MagicSparkle.swift
//  The decoration, all of it drawn rather than shipped.
//
//  Three small pieces carry the whole "magical" register: a four-point sparkle,
//  a leaf, and the corner marks of a scanner. None is an asset, all of them
//  scale to any size, and each is one shape.
//
//  ── REDUCE MOTION ──────────────────────────────────────────────────────────
//
//  Everything that moves here checks `accessibilityReduceMotion` and simply
//  stops at a sensible resting value. A sparkle that cannot pulse is still a
//  sparkle; the page loses nothing a reader needs.

import SwiftUI

/// A four-point star, the classic "twinkle" silhouette.
///
/// A custom shape rather than `Image(systemName: "sparkles")` because the SF
/// symbol draws three stars of fixed relative size and position — usable once,
/// repetitive by the fourth. One point-shape can be placed, scaled and rotated
/// freely, which is what makes a scattering look scattered.
struct SparkleShape: Shape {
    /// 0…1. Lower values pinch the waist, giving a sharper, glintier star.
    var waist: CGFloat = 0.28

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * waist

        var path = Path()
        for step in 0..<8 {
            let radius = step.isMultiple(of: 2) ? outer : inner
            let angle = (Double(step) / 8) * 2 * .pi - .pi / 2
            let point = CGPoint(x: centre.x + cos(angle) * radius,
                                y: centre.y + sin(angle) * radius)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// One sparkle, optionally breathing.
struct MagicSparkle: View {
    var size: CGFloat = 14
    var opacity: Double = 0.9
    /// Staggers the pulse so a group does not blink in unison.
    var delay: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        SparkleShape()
            .fill(Grimoire.accentMagic)
            .frame(width: size, height: size)
            .opacity(pulsing ? opacity : opacity * 0.45)
            .scaleEffect(pulsing ? 1 : 0.82)
            .onAppear {
                guard !reduceMotion else {
                    // Rests at full strength rather than mid-pulse, so a still
                    // page looks finished instead of caught halfway.
                    pulsing = true
                    return
                }
                withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)
                    .delay(delay)) {
                    pulsing = true
                }
            }
            .accessibilityHidden(true)
    }
}

/// Two thin rules with a leaf between them — the separator under a page title.
///
/// The leaf scales with Dynamic Type so it keeps its proportion to the title
/// above it; the rules stay a fixed length so they never crowd the edges.
struct LeafDivider: View {
    @ScaledMetric(relativeTo: .title2) private var leafSize: CGFloat = 20
    var ruleLength: CGFloat = 64

    var body: some View {
        HStack(spacing: 12) {
            rule
            // The illustrated leaf from the catalogue, already drawn stem
            // bottom-left and tip up-right as the design has it.
            Image("Leaf")
                .resizable()
                .scaledToFit()
                .frame(width: leafSize, height: leafSize)
            rule
        }
        .padding(.vertical, 2)
        .accessibilityHidden(true)
    }

    private var rule: some View {
        Rectangle()
            .fill(Grimoire.secondary.opacity(0.55))
            .frame(width: ruleLength, height: 1)
    }
}

/// The four corner brackets of a viewfinder.
///
/// Drawn as one shape so the stroke is continuous and the corners cannot drift
/// apart when the frame resizes.
struct ScanCorners: Shape {
    var inset: CGFloat = 0
    /// How far each bracket runs along its edges, as a fraction of the shorter side.
    var armRatio: CGFloat = 0.26

    func path(in rect: CGRect) -> Path {
        let frame = rect.insetBy(dx: inset, dy: inset)
        let arm = min(frame.width, frame.height) * armRatio
        var path = Path()

        // Top-left
        path.move(to: CGPoint(x: frame.minX, y: frame.minY + arm))
        path.addLine(to: CGPoint(x: frame.minX, y: frame.minY))
        path.addLine(to: CGPoint(x: frame.minX + arm, y: frame.minY))
        // Top-right
        path.move(to: CGPoint(x: frame.maxX - arm, y: frame.minY))
        path.addLine(to: CGPoint(x: frame.maxX, y: frame.minY))
        path.addLine(to: CGPoint(x: frame.maxX, y: frame.minY + arm))
        // Bottom-right
        path.move(to: CGPoint(x: frame.maxX, y: frame.maxY - arm))
        path.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY))
        path.addLine(to: CGPoint(x: frame.maxX - arm, y: frame.maxY))
        // Bottom-left
        path.move(to: CGPoint(x: frame.minX + arm, y: frame.maxY))
        path.addLine(to: CGPoint(x: frame.minX, y: frame.maxY))
        path.addLine(to: CGPoint(x: frame.minX, y: frame.maxY - arm))

        return path
    }
}

// MARK: - Motion

extension View {
    /// A slow vertical drift, disabled under Reduce Motion.
    ///
    /// An extension rather than three copies: the squirrel, the grimoire and the
    /// tree all want the same gesture, and three hand-rolled versions would drift
    /// out of step with each other the first time the duration changed.
    func gentleFloat(amplitude: CGFloat = 6,
                     duration: Double = 3.2,
                     delay: Double = 0,
                     enabled: Bool = true) -> some View {
        modifier(GentleFloat(amplitude: amplitude, duration: duration,
                             delay: delay, enabled: enabled))
    }
}

private struct GentleFloat: ViewModifier {
    let amplitude: CGFloat
    let duration: Double
    let delay: Double
    let enabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lifted = false

    func body(content: Content) -> some View {
        content
            .offset(y: lifted ? -amplitude : amplitude)
            .onAppear {
                guard enabled, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: duration)
                    .repeatForever(autoreverses: true).delay(delay)) {
                    lifted = true
                }
            }
    }
}
