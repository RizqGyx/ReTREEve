//  OnboardingHeroView.swift
//  The five hero compositions, drawn to the Sketch onboarding.
//
//  Built only from the bitmaps already in the catalogue — `Tree`, `Squirrel`,
//  `Grimoire`, `Acorn`, `BookAcorn` — plus shapes. The phone on the first page, the
//  viewfinder, the search bar and the result cards are SwiftUI, so nothing here
//  needs a new asset and nothing looks wrong on a phone it was not drawn for.
//
//  Every size is a fraction of the box the hero is given, so one composition
//  holds from an SE to a Pro Max. Each hero is `accessibilityHidden`: the title
//  and body already say everything, so VoiceOver reads the page once.

import SwiftUI

struct OnboardingHeroView: View {
    let visual: OnboardingVisual
    /// True only for the page on screen, so off-screen pages are not animating.
    var isActive: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Group {
                switch visual {
                case .welcome:   welcome(size)
                case .save:      save(size)
                case .findAgain: findAgain(size)
                case .grow:      grow(size)
                case .ready:     ready(size)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .accessibilityHidden(true)
    }

    // MARK: - 1 · Welcome

    /// The squirrel inside a phone whose lower half fades into the page, so the
    /// title reads as the screen's own content rather than a caption under a
    /// picture of a device.
    private func welcome(_ size: CGSize) -> some View {
        let phoneWidth = min(size.width * 0.80, size.height * 0.70)
        let squirrelWidth = min(phoneWidth * 0.86, size.height * 0.62)

        return ZStack(alignment: .top) {
            PhoneOutline(radius: phoneWidth * 0.15, bezel: max(6, phoneWidth * 0.024))
                .frame(width: phoneWidth, height: size.height * 1.1)
                .padding(.top, size.height * 0.03)
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipped()
                // A mask reads only alpha, so the colours here are not palette.
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.55),
                                             .init(color: .clear, location: 0.97)],
                                     startPoint: .top, endPoint: .bottom))

            Image("Squirrel")
                .resizable()
                .scaledToFit()
                .frame(width: squirrelWidth)
                .padding(.top, size.height * 0.15)
                .gentleFloat(amplitude: 4, duration: 3.4, enabled: isActive)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    // MARK: - 2 · Save Insight

    private func save(_ size: CGSize) -> some View {
        let w = size.width, h = size.height
        let unit = min(w, h * 0.9)
        let fontSize = max(10, unit * 0.036)
        let dot = min(w * 0.125, h * 0.11)
        let finderHeight = max(0, h - dot * 1.55 - fontSize * 4.2 - h * 0.08)
        let finderWidth = min(w * 0.66, finderHeight * 0.98)

        return VStack(spacing: h * 0.025) {
            ZStack {
                ScanCorners(armRatio: 0.2)
                    .stroke(Grimoire.textDisabled,
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .square))
                    .frame(width: finderWidth, height: finderHeight)

                Image("BookAcorn")
                    .resizable()
                    .scaledToFit()
                    .frame(width: finderWidth * 0.84, height: finderHeight * 0.84)
                    .gentleFloat(amplitude: 4, duration: 3.6, enabled: isActive)
            }

            quoteCard(width: finderWidth * 1.03, fontSize: fontSize)

            stepRow(dot: dot, fontSize: max(10, unit * 0.034))
        }
        .frame(width: w, height: h)
    }

    private func quoteCard(width: CGFloat, fontSize: CGFloat) -> some View {
        HStack(alignment: .top, spacing: fontSize * 0.5) {
            Image(systemName: "quote.opening")
                .font(.system(size: fontSize * 1.3, weight: .bold))
                .foregroundStyle(Grimoire.accentMagic)
            Text("\u{201C}Abilities can develop through effort, strategy, and learning.\u{201D}")
                .font(.system(size: fontSize, design: .rounded))
                .foregroundStyle(Grimoire.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, fontSize * 0.8)
        .padding(.vertical, fontSize * 0.7)
        .frame(width: width)
        .background(Grimoire.surface, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .shadow(color: Grimoire.textPrimary.opacity(0.28), radius: 6, y: 3)
    }

    /// Scan → Capture → Save.
    private func stepRow(dot: CGFloat, fontSize: CGFloat) -> some View {
        HStack(alignment: .top, spacing: dot * 0.12) {
            step("camera.viewfinder", "Scan", dot: dot, fontSize: fontSize)
            stepArrow(dot: dot)
            step("doc.viewfinder", "Capture", dot: dot, fontSize: fontSize)
            stepArrow(dot: dot)
            step("bookmark.fill", "Save", dot: dot, fontSize: fontSize)
        }
    }

    private func step(_ symbol: String, _ label: String,
                      dot: CGFloat, fontSize: CGFloat) -> some View {
        VStack(spacing: dot * 0.1) {
            Circle()
                .fill(Grimoire.surface)
                .overlay(Circle().strokeBorder(Grimoire.primary, lineWidth: 1.2))
                .frame(width: dot, height: dot)
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: dot * 0.42, weight: .medium))
                        .foregroundStyle(Grimoire.primary))
            Text(label)
                .font(.system(size: fontSize, design: .rounded))
                .foregroundStyle(Grimoire.textSecondary)
                .fixedSize()
        }
        .frame(width: dot * 1.4)
    }

    private func stepArrow(dot: CGFloat) -> some View {
        HStack(spacing: -1) {
            Rectangle()
                .fill(Grimoire.primary)
                .frame(width: dot * 0.95, height: 1.2)
            Image(systemName: "arrowtriangle.right.fill")
                .font(.system(size: dot * 0.14))
                .foregroundStyle(Grimoire.primary)
        }
        .frame(height: dot)
    }

    // MARK: - 3 · Find Again

    private func findAgain(_ size: CGSize) -> some View {
        let w = size.width, h = size.height
        // 440pt is roughly the height the Sketch hero was drawn at; shorter
        // screens scale the whole composition down rather than overlapping.
        let k = min(1, h / 440)
        let squirrelWidth = min(w * 0.44, 176 * k)

        return ZStack {
            Image("Grimoire")
                .resizable()
                .scaledToFit()
                .frame(height: h * 0.95)
                .saturation(0.7)
                .opacity(0.35)
                .offset(y: h * 0.06)

            VStack(spacing: 24 * k) {
                searchBar(height: 48 * k, fontSize: max(12, 17 * k))
                    // The squirrel sits on the bar, feet just over its top edge.
                    .overlay(alignment: .topTrailing) {
                        // Both dimensions are fixed: an overlay proposes the
                        // bar's own 48pt height, which would shrink the art to fit.
                        Image("Squirrel")
                            .resizable()
                            .scaledToFit()
                            .frame(width: squirrelWidth, height: squirrelWidth * 1.05)
                            .offset(x: -w * 0.03, y: -squirrelWidth * 0.92)
                            .gentleFloat(amplitude: 3, duration: 3.1, enabled: isActive)
                    }
                    .padding(.top, squirrelWidth * 0.8)

                resultCard(k: k)
                resultCard(k: k)
            }
        }
        .frame(width: w, height: h)
    }

    private func searchBar(height: CGFloat, fontSize: CGFloat) -> some View {
        HStack(spacing: fontSize * 0.5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: fontSize * 1.05, weight: .medium))
            Text("Search")
                .font(.system(size: fontSize, design: .rounded))
            Spacer(minLength: 0)
            Image(systemName: "mic")
                .font(.system(size: fontSize))
        }
        .foregroundStyle(Grimoire.textSecondary)
        .padding(.horizontal, fontSize)
        .frame(height: height)
        .background(Grimoire.surface, in: Capsule())
        .shadow(color: Grimoire.textPrimary.opacity(0.25), radius: 6, y: 4)
    }

    private func resultCard(k: CGFloat) -> some View {
        let fontSize = max(10, 14 * k)
        return HStack(alignment: .top, spacing: 10 * k) {
            Image("Acorn")
                .resizable()
                .scaledToFit()
                .frame(width: 24 * k, height: 30 * k)

            VStack(alignment: .leading, spacing: 6 * k) {
                Text("\u{201C}Abilities can develop through effort, strategy, and learning.\u{201D}")
                    .font(.system(size: fontSize, design: .rounded))
                    .foregroundStyle(Grimoire.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4 * k) {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: fontSize * 0.78, weight: .medium))
                    Text("matched on trust")
                        .font(.system(size: fontSize * 0.78, design: .rounded))
                }
                .foregroundStyle(Grimoire.accentMystic)
            }

            Spacer(minLength: 0)

            // Match strength, full: three bars.
            HStack(spacing: 3 * k) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Grimoire.primary)
                        .frame(width: 5 * k, height: 18 * k)
                }
            }
            .padding(.top, 2 * k)
        }
        .padding(.horizontal, 14 * k)
        .padding(.vertical, 12 * k)
        .background(Grimoire.surface,
                    in: RoundedRectangle(cornerRadius: 16 * k, style: .continuous))
        .shadow(color: Grimoire.textPrimary.opacity(0.25), radius: 6, y: 4)
    }

    // MARK: - 4 · Grow Through Reading

    private func grow(_ size: CGSize) -> some View {
        let w = size.width, h = size.height
        let dot = min(w * 0.12, h * 0.11)

        return VStack(spacing: h * 0.03) {
            Image("Tree")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: .infinity)
                .gentleFloat(amplitude: 3, duration: 5.4, enabled: isActive)

            growthRow(dot: dot, width: w * 0.62)
        }
        .frame(width: w, height: h)
    }

    /// Acorn → leaf → tree: the seed the app counts in, growing.
    private func growthRow(dot: CGFloat, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            growthStop(fill: Grimoire.secondary, dot: dot) {
                Image("Acorn").resizable().scaledToFit().frame(height: dot * 0.5)
            }
            connector
            growthStop(fill: Grimoire.secondary, dot: dot) {
                Image("Leaf").resizable().scaledToFit().frame(height: dot * 0.52)
            }
            connector
            growthStop(fill: Grimoire.primarySoft, dot: dot) {
                Image("Tree").resizable().scaledToFit().frame(height: dot * 0.66)
            }
        }
        .frame(width: width)
    }

    private var connector: some View {
        Rectangle()
            .fill(Grimoire.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 1.5)
    }

    private func growthStop<Content: View>(fill: Color, dot: CGFloat,
                                           @ViewBuilder content: () -> Content) -> some View {
        Circle()
            .fill(fill)
            .overlay(Circle().strokeBorder(Grimoire.primary, lineWidth: 1))
            .frame(width: dot, height: dot)
            .overlay(content())
    }

    // MARK: - 5 · Ready

    private func ready(_ size: CGSize) -> some View {
        let w = size.width, h = size.height
        let unit = min(w, h * 0.95)

        return ZStack {
            // The tree recedes: this page is about the reader starting.
            Image("Tree")
                .resizable()
                .scaledToFit()
                .frame(height: h * 0.86)
                .saturation(0.55)
                .opacity(0.38)

            Image("Squirrel")
                .resizable()
                .scaledToFit()
                .frame(width: unit * 0.46)
                .offset(x: -w * 0.19, y: -h * 0.04)
                .gentleFloat(amplitude: 5, duration: 3.2, enabled: isActive)

            Image("Acorn")
                .resizable()
                .scaledToFit()
                .frame(height: unit * 0.24)
                .rotationEffect(.degrees(12))
                .offset(x: w * 0.22, y: -h * 0.25)
                .gentleFloat(amplitude: 4, duration: 2.8, delay: 0.4, enabled: isActive)

            Image("Grimoire")
                .resizable()
                .scaledToFit()
                .frame(height: unit * 0.30)
                .rotationEffect(.degrees(32))
                .offset(x: w * 0.20, y: h * 0.13)
                .gentleFloat(amplitude: 5, duration: 3.8, delay: 0.2, enabled: isActive)
        }
        .frame(width: w, height: h)
    }
}

/// A phone drawn in three nested rounded rectangles: metal rim, dark bezel,
/// parchment screen.
private struct PhoneOutline: View {
    let radius: CGFloat
    let bezel: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: [Grimoire.textDisabled, Grimoire.border, Grimoire.textDisabled],
                                     startPoint: .leading, endPoint: .trailing))
            RoundedRectangle(cornerRadius: radius - 2, style: .continuous)
                .fill(Grimoire.textPrimary)
                .padding(2.5)
            RoundedRectangle(cornerRadius: max(0, radius - bezel), style: .continuous)
                .fill(Grimoire.background)
                .padding(bezel)
        }
        .shadow(color: Grimoire.textPrimary.opacity(0.18), radius: 10, y: 6)
    }
}
