//  OnboardingView.swift
//  One screen whose content changes.
//
//  ── PERSISTENCE ────────────────────────────────────────────────────────────
//
//  Completion lives in `@AppStorage("hasCompletedOnboarding")`, in UserDefaults
//  rather than SwiftData: the schema has no migration plan, and whether someone
//  has read five screens is not part of their reading memory.
//
//  It shows once per install: a fresh download has no stored value, so the
//  introduction appears; finishing it writes `true`, and every later launch goes
//  straight to Home.
//
//  ── ONE SCREEN, NOT FIVE ───────────────────────────────────────────────────
//
//  The introduction used to be a paged `TabView`, where each page slid in whole,
//  carrying its own dots and its own button. That reads like being pushed to a
//  new screen five times. It is one screen: the frame, the page dots and the
//  button never move. Only the picture and the words change, with a short fade
//  that drifts toward the direction of travel. Swiping on the content still
//  moves between pages, the way a photo carousel does.

import SwiftUI

nonisolated enum Onboarding {
    /// Set by finishing the introduction. Absent on a fresh install.
    static let completedKey = "hasCompletedOnboarding"
}

struct OnboardingView: View {
    /// Called once the reader finishes. The caller owns what happens next, so
    /// this view never knows about Home.
    var onFinish: () -> Void

    @AppStorage(Onboarding.completedKey) private var hasCompletedOnboarding = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    /// Which way the last change went, so new content arrives from the side the
    /// reader is moving toward and the old content leaves the other way.
    @State private var movingForward = true

    private let pages = OnboardingPage.all
    private var page: OnboardingPage { pages[index] }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                OnboardingPageContent(page: page)
                    // A new identity per page is what lets the old content
                    // transition out while the new one transitions in.
                    .id(page.id)
                    .transition(contentTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .simultaneousGesture(swipe)
            // VoiceOver's three-finger swipe does what a swipe does.
            .accessibilityScrollAction { edge in
                switch edge {
                case .trailing: go(to: index + 1)
                case .leading:  go(to: index - 1)
                default:        break
                }
            }

            footer
        }
        .magicalBackground(.normal)
    }

    /// Fixed in place on every page — only its dot and its label change.
    private var footer: some View {
        VStack(spacing: 18) {
            OnboardingPageIndicator(count: pages.count, current: index)

            Button(page.buttonTitle, action: advance)
                .buttonStyle(GrimoirePrimaryButton())
                .padding(.horizontal, 20)
                .accessibilityHint(page.isFinal
                                   ? "Finishes the introduction and opens ReTREEve"
                                   : "Shows the next page")
        }
        // Clears the home indicator on tall phones and the bare screen edge on
        // an SE, which has no inset of its own to sit above.
        .padding(.top, 8)
        .padding(.bottom, 18)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let dx = value.translation.width
                // Clearly sideways, and far enough to be deliberate, so a
                // vertical scroll of long text never turns the page.
                guard abs(dx) > 60, abs(dx) > abs(value.translation.height) else { return }
                go(to: dx < 0 ? index + 1 : index - 1)
            }
    }

    private var contentTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let shift: CGFloat = movingForward ? 36 : -36
        return .asymmetric(insertion: .opacity.combined(with: .offset(x: shift)),
                           removal: .opacity.combined(with: .offset(x: -shift)))
    }

    private func advance() {
        if page.isFinal { finish() } else { go(to: index + 1) }
    }

    /// Clamped, so swiping past either end does nothing. Swiping never finishes
    /// the introduction — only the button does.
    private func go(to target: Int) {
        let next = min(max(target, 0), pages.count - 1)
        guard next != index else { return }
        movingForward = next > index
        // One turn later, so the leaving content has already been rendered with
        // the new direction before its removal transition is taken.
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: reduceMotion ? 0.2 : 0.35)) { index = next }
            AccessibilityNotification.LayoutChanged().post()
        }
    }

    private func finish() {
        hasCompletedOnboarding = true
        onFinish()
    }
}
