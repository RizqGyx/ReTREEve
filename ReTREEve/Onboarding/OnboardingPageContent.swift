//  OnboardingPageContent.swift
//  What changes from page to page: the picture, the title and the words.
//
//  The dots and the button are not here. They belong to `OnboardingView`, which
//  keeps them still while this content is swapped.
//
//  ── HOW THIS STAYS UPRIGHT ON EVERY IPHONE ─────────────────────────────────
//
//  1. THE HERO IS A FRACTION, NOT A NUMBER. Its height is a share of the space
//     above the footer, clamped at both ends, and cut further at accessibility
//     text sizes where the words need the room more than the picture does.
//
//  2. ALWAYS A SCROLLVIEW, WITH A MINIMUM HEIGHT. Short content stretches to fill
//     and centres, so there is nothing to scroll on a normal phone —
//     `.basedOnSize` even removes the bounce — and long content at the largest
//     text sizes simply becomes scrollable, never pushing the button off screen.
//     (`ViewThatFits` was tried first: a stack containing `Spacer` always "fits",
//     so it never chose the scrolling layout.)

import SwiftUI

struct OnboardingPageContent: View {
    let page: OnboardingPage

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    OnboardingHeroView(visual: page.visual, isActive: true)
                        .frame(height: heroHeight(for: proxy.size.height))
                        .padding(.horizontal, 20)

                    Spacer(minLength: 16)

                    VStack(spacing: 12) {
                        Text(page.title)
                            .font(.grimoire(.title2, .emphasized))
                            .foregroundStyle(Grimoire.textPrimary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        LeafDivider()

                        Text(page.body)
                            .font(.grimoire(.callout))
                            .foregroundStyle(Grimoire.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, Grimoire.horizontalMargin + 16)
                    // Title and body are read as one statement; splitting them
                    // makes VoiceOver stop in the middle of a sentence.
                    .accessibilityElement(children: .combine)

                    Spacer(minLength: 12)
                }
                .padding(.top, 8)
                .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// The Sketch heroes take roughly two thirds of the space above the footer.
    /// A short phone gets a smaller share so the words still fit without
    /// scrolling, and accessibility sizes cut it hard — a large picture is the
    /// first thing a reader would trade away for legible text.
    private func heroHeight(for available: CGFloat) -> CGFloat {
        let share: CGFloat = available < 600 ? 0.54 : 0.64
        let base = min(max(available * share, 150), 480)
        return typeSize.isAccessibilitySize ? base * 0.62 : base
    }
}
