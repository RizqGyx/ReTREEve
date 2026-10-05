//  MagicalBackground.swift
//  The botanical frame, used as a backdrop without becoming the subject.
//
//  ── WHY THE INTENSITY DIAL EXISTS ──────────────────────────────────────────
//
//  `C5Background` is a busy illustration: leaves, gold sparkles, a moon, a
//  forest floor. Behind a Home screen with one tree and two buttons it reads as
//  atmosphere. Behind a list of twenty passages, or a form, it reads as noise —
//  and text sitting over a painted leaf is text a reader has to work at.
//
//  So the same asset is used everywhere, at a strength each screen chooses.
//  `.subtle` keeps the identity while fading the illustration far enough back
//  that a card of body text sits cleanly on top; `.none` draws nothing at all,
//  which is what a live camera needs.
//
//  The scrim is a flat wash of the palette's own background colour rather than
//  a blur: blurring a full-screen image every frame costs more than it buys, and
//  a wash keeps the warm parchment note the design is built on.

import SwiftUI

enum BackgroundIntensity {
    /// Home, method picker, success — the illustration is part of the moment.
    case normal
    /// Library, forms, detail — identity without competing with the content.
    case subtle
    /// Camera. Nothing is drawn.
    case none

    /// How much of the flat parchment wash sits over the illustration.
    var scrim: Double {
        switch self {
        case .normal: 0.14
        case .subtle: 0.55
        case .none:   0
        }
    }

    /// Drawing the image at less than full strength as well as washing it keeps
    /// the leaves from reading as hard edges behind a card.
    var imageOpacity: Double {
        switch self {
        case .normal: 1.0
        case .subtle: 0.45
        case .none:   0
        }
    }
}

struct MagicalBackgroundView: View {
    var intensity: BackgroundIntensity = .normal

    var body: some View {
        if intensity != .none {
            ZStack {
                // The palette colour sits underneath as well as over: the asset
                // is `scaledToFill`, and on a very wide layout its edges can
                // stop short of the safe area.
                Grimoire.background

                Image("C5Background")
                    .resizable()
                    .scaledToFill()
                    .opacity(intensity.imageOpacity)

                Grimoire.background.opacity(intensity.scrim)
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
    }
}

extension View {
    /// Places the botanical frame behind this view.
    func magicalBackground(_ intensity: BackgroundIntensity = .normal) -> some View {
        background(MagicalBackgroundView(intensity: intensity))
    }
}

// MARK: - Surfaces

/// The one card treatment the Grimoire screens use: warm surface, hairline
/// border, a shadow just strong enough to lift it off the illustration.
struct GrimoireCard: ViewModifier {
    var padding: CGFloat = 16
    var radius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Grimoire.surface,
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Grimoire.border, lineWidth: 1))
            .shadow(color: Grimoire.textPrimary.opacity(0.06), radius: 10, y: 4)
    }
}

extension View {
    func grimoireCard(padding: CGFloat = 16, radius: CGFloat = 18) -> some View {
        modifier(GrimoireCard(padding: padding, radius: radius))
    }
}

/// A rule with a gold glint at its centre. Separates sections without the hard
/// line of a `Divider`, which looks like a form on a parchment ground.
struct MagicDivider: View {
    var body: some View {
        HStack(spacing: 10) {
            line
            SparkleShape()
                .fill(Grimoire.accentMagic)
                .frame(width: 9, height: 9)
            line
        }
        .accessibilityHidden(true)
    }

    private var line: some View {
        Rectangle()
            .fill(
                LinearGradient(colors: [Grimoire.border.opacity(0), Grimoire.border],
                               startPoint: .leading, endPoint: .trailing))
            .frame(height: 1)
    }
}

// MARK: - Buttons

/// The bordered counterpart to `GrimoirePrimaryButton`.
struct GrimoireSecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.grimoire(.headline))
            .foregroundStyle(Grimoire.primary)
            .frame(maxWidth: .infinity, minHeight: Grimoire.buttonHeight)
            .background(configuration.isPressed ? Grimoire.primarySoft : Grimoire.surface,
                        in: RoundedRectangle(cornerRadius: Grimoire.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Grimoire.cornerRadius, style: .continuous)
                .strokeBorder(Grimoire.primary, lineWidth: 1.5))
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
