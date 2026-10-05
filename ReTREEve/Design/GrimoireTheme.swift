//  GrimoireTheme.swift
//  The design system: colour, type, metrics and the shared control styles.
//
//  These began life inside the onboarding, then the main app adopted the same
//  palette. Leaving them in a file called `OnboardingTheme` would have made
//  every screen in the app import "onboarding" to draw a button — so they moved
//  here, unchanged, when the second caller appeared.
//
//  Every colour the app's Grimoire surfaces use is named here. No hex literal
//  appears in a view: a token spelled out in five files is a token that will
//  disagree with itself in three of them the first time it changes.
//
//  ── WHY THESE COLOURS DO NOT ADAPT TO DARK MODE ────────────────────────────
//
//  The design defines one warm parchment scheme, and it is the app's only
//  palette — the older `Forest` palette is gone. Because the
//  background and every text colour are painted explicitly, these surfaces look
//  the same in either system appearance rather than half-inheriting one.

import SwiftUI

enum Grimoire {

    // MARK: - Colour

    /// Buttons, active indicator, headline ink for branded words.
    static let primary        = Color(hex: 0x315C45)
    static let primaryPressed = Color(hex: 0x274B38)
    static let primarySoft    = Color(hex: 0xE5EDDF)

    static let secondary      = Color(hex: 0xA8BC92)
    static let secondarySoft  = Color(hex: 0xEEF3E8)

    static let background     = Color(hex: 0xF7F0DF)
    static let surface        = Color(hex: 0xFFF9ED)

    /// Sparkles and gilt edges.
    static let accentMagic     = Color(hex: 0xD6AE58)
    static let accentMagicSoft = Color(hex: 0xF8ECCB)
    /// Rediscovery — used where the product is about remembering, not keeping.
    static let accentMystic    = Color(hex: 0x8873A5)

    static let textPrimary    = Color(hex: 0x24251F)
    static let textSecondary  = Color(hex: 0x66675E)
    static let textDisabled   = Color(hex: 0xAAA99F)

    static let border         = Color(hex: 0xDED7C8)

    static let destructive     = Color(hex: 0xB85C4A)
    static let destructiveSoft = Color(hex: 0xF5DEDA)

    // MARK: - Type
    //
    // Text uses `Font.grimoire(_:_:)` — see the bottom of this file.

    // MARK: - Metrics

    static let cornerRadius: CGFloat = 18
    static let buttonHeight: CGFloat = 54
    static let horizontalMargin: CGFloat = 24
}

/// The one button style the onboarding uses.
struct GrimoirePrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.grimoire(.headline))
            .foregroundStyle(Grimoire.surface)
            .frame(maxWidth: .infinity, minHeight: Grimoire.buttonHeight)
            .background(configuration.isPressed ? Grimoire.primaryPressed : Grimoire.primary,
                        in: RoundedRectangle(cornerRadius: Grimoire.cornerRadius, style: .continuous))
            // Small and faint on purpose. A heavy shadow here would read as a
            // floating card rather than a button resting on parchment.
            .shadow(color: Grimoire.primary.opacity(configuration.isPressed ? 0.10 : 0.18),
                    radius: 8, y: 3)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

extension View {
    /// A centred inline title in the rounded Title 3 style the Sketch screens use.
    ///
    /// `navigationTitle` is still set, so the back-button menu and VoiceOver keep
    /// the screen's name; the principal item only changes how it is drawn.
    func grimoireNavigationTitle(_ title: String) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.grimoire(.title3, .emphasized))
                        .foregroundStyle(Grimoire.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityAddTraits(.isHeader)
                }
            }
    }
}

// MARK: - Text styles

/// The eleven Apple text styles, as named in the Sketch library
/// (LargeTitleText … Caption2Text), every one set in SF Pro Rounded.
///
/// ── WHY TEXT STYLES AND NOT POINT SIZES ──────────────────────────────────
///
/// The Sketch table is Apple's own Dynamic Type scale: Body is 14pt at
/// xSmall, 17pt at Large (the default) and larger again above it. A text style
/// reproduces that whole table from one token, so the size a reader chose in
/// Settings is honoured everywhere. Writing `.system(size: 17)` would match
/// the default column and ignore every other one.
enum GrimoireTextStyle {
    case largeTitle, title1, title2, title3
    case headline, body, callout, subhead
    case footnote, caption1, caption2

    var textStyle: Font.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title1:     .title
        case .title2:     .title2
        case .title3:     .title3
        case .headline:   .headline
        case .body:       .body
        case .callout:    .callout
        case .subhead:    .subheadline
        case .footnote:   .footnote
        case .caption1:   .caption
        case .caption2:   .caption2
        }
    }

    /// The "Emphasized weight" column: Bold for the three largest styles,
    /// Semibold for everything else.
    var emphasizedWeight: Font.Weight {
        switch self {
        case .largeTitle, .title1, .title2: .bold
        default: .semibold
        }
    }
}

/// The two weights the Sketch library defines for each style. There is no
/// Medium: anything that was Medium before is Regular now.
enum GrimoireTextWeight {
    case regular, emphasized
}

extension Font {
    static func grimoire(_ style: GrimoireTextStyle,
                         _ weight: GrimoireTextWeight = .regular) -> Font {
        let base = Font.system(style.textStyle, design: .rounded)
        switch weight {
        // Headline is Semibold even at its Regular weight, per the table.
        case .regular:    return style == .headline ? base.weight(.semibold) : base
        case .emphasized: return base.weight(style.emphasizedWeight)
        }
    }
}
