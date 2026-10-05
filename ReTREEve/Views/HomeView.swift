//  HomeView.swift
//  The tree is the screen, and the grimoire in its trunk is the way into the
//  library.
//
//  ── WHY TAPPING THE TREE DID NOTHING ───────────────────────────────────────
//
//  The previous hero was a `Button` with an EMPTY action wrapped around the art,
//  plus a `NavigationLink` laid over it whose label was `Color.clear`. A clear
//  colour is not hit-testable in SwiftUI, so every tap passed straight through
//  the link and landed on the empty button: the tree pressed, and nothing
//  happened. A drag gesture on top competed for the same touch.
//
//  It is now one `NavigationLink` whose label IS the tree, with the press effect
//  moved into a `ButtonStyle`. One control, one job, no layering to get wrong.
//
//  ── WHY THE TREE WAS SO SMALL ──────────────────────────────────────────────
//
//  Its height was a fixed share of the screen — 38%, capped at 400pt — so on a
//  standard iPhone the tree stopped at about 324pt tall, and at the art's 4:5
//  proportions that made it about 260pt wide on a 393pt screen. The design has
//  it spanning the width.
//
//  Now the tree simply takes whatever vertical space the stats and buttons leave
//  over, and is sized to the largest rectangle of its own proportions that fits.
//  On a tall phone it fills the width; on an SE it fills the height. The wordmark
//  header went with it: the design does not have one, and it was spending the
//  height the tree needed.
//
//  ── THE TREE NO LONGER DRAWS ITSELF ────────────────────────────────────────
//
//  `TreeCanvas` grew branch by branch out of `GrowthSummary`; the illustration is
//  one fixed picture. The growth survives the only way an image can express it —
//  a subtle 92% → 100% scale across the stages. The stats say the numbers.

import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

struct HomeView: View {
    @Query(sort: \ReadingInsight.createdAt, order: .reverse)
    private var insights: [ReadingInsight]

    @State private var showingCapture = false
    @State private var showingAcorn = false
    /// A short pulse on the Saved count as the acorn lands, so the number that
    /// changed is the one the eye goes to.
    @State private var savedBump = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var summary: GrowthSummary { GrowthSummary(insights: insights) }

    /// Read from the asset rather than written down, so replacing the art with a
    /// differently proportioned tree does not quietly stretch or shrink it.
    private static let treeAspect: CGFloat = {
        #if canImport(UIKit)
        if let size = UIImage(named: "Tree")?.size, size.height > 0 {
            return size.width / size.height
        }
        #endif
        return 0.8
    }()

    var body: some View {
        VStack(spacing: 12) {
            treeHero
                // The one flexible element: everything else takes what it needs
                // and the tree takes the rest.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

            tapHint

            stats
                .padding(.horizontal, 20)
        }
        .padding(.bottom, 12)
        // A background MODIFIER, not a ZStack layer. As a layer, the
        // illustration's own `ignoresSafeArea()` widened the stack's bounds past
        // the screen and the bottom `safeAreaInset` attached to those bounds,
        // pushing the action bar off the display.
        .magicalBackground(.normal)
        .overlay {
            if showingAcorn {
                AcornSavedFeedback()
                    .transition(.opacity)
            }
        }
        .safeAreaInset(edge: .bottom) { actions }
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showingCapture) {
            CaptureFlowView(onSaved: celebrate)
        }
    }

    // MARK: - Pieces

    /// The whole hero is the link. Hit-testing only the painted book inside the
    /// trunk would be a rectangle guessed against an illustration; a reader who
    /// missed it by ten points would conclude the app was broken.
    private var treeHero: some View {
        NavigationLink(value: Route.library) {
            GeometryReader { proxy in
                let area = proxy.size
                // The largest tree of the art's own proportions that fits here.
                let treeHeight = min(area.height, area.width / Self.treeAspect)
                let treeWidth = treeHeight * Self.treeAspect

                ZStack {
                    Circle()
                        .fill(Grimoire.accentMagicSoft.opacity(0.55))
                        .frame(width: treeWidth * 0.85, height: treeWidth * 0.85)
                        .blur(radius: 40)

                    Image("Tree")
                        .resizable()
                        .scaledToFit()
                        .frame(width: treeWidth, height: treeHeight)
                        .scaleEffect(treeScale)

                    // Positions are fractions of the drawn tree, not the screen,
                    // so the squirrel stays at the roots on every phone.
                    Image("Squirrel")
                        .resizable()
                        .scaledToFit()
                        .frame(width: treeWidth * 0.34)
                        .offset(x: -treeWidth * 0.29, y: treeHeight * 0.30)
                        .gentleFloat(amplitude: 3, duration: 3.6)

                    MagicSparkle(size: treeWidth * 0.05, delay: 0.1)
                        .offset(x: treeWidth * 0.40, y: -treeHeight * 0.34)
                    MagicSparkle(size: treeWidth * 0.036, opacity: 0.75, delay: 0.7)
                        .offset(x: -treeWidth * 0.42, y: -treeHeight * 0.16)
                }
                .frame(width: area.width, height: area.height)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(TreePressStyle())
        .accessibilityLabel("Open My Grimoire")
        .accessibilityValue("\(summary.saved) saved, \(summary.foundAgain) found again, across \(summary.books) books")
        .accessibilityHint("Opens your library of saved passages")
    }

    /// 0.92 at Sprout through 1.0 at Bearing — see the file header.
    private var treeScale: CGFloat {
        let stages = max(TreeStage.allCases.count - 1, 1)
        return 0.92 + 0.08 * CGFloat(summary.stage.rawValue) / CGFloat(stages)
    }

    private var tapHint: some View {
        Text("Tap the tree to open your grimoire")
            .font(.grimoire(.footnote))
            .foregroundStyle(Grimoire.textSecondary)
            .accessibilityHidden(true)
    }

    private var stats: some View {
        HStack(spacing: 0) {
            stat(summary.saved, "Saved", showsAcorn: true)
            divider
            stat(summary.foundAgain, "Found Again")
            divider
            stat(summary.books, "Books")
        }
        .grimoireCard(padding: 16, radius: 20)
    }

    private func stat(_ value: Int, _ label: String, showsAcorn: Bool = false) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                if showsAcorn {
                    Image("Acorn")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 15, height: 15)
                        .accessibilityHidden(true)
                }
                Text("\(value)")
                    .font(.grimoire(.title2, .emphasized))
                    .foregroundStyle(Grimoire.primary)
                    .monospacedDigit()
            }
            Text(label)
                .font(.grimoire(.caption1))
                .foregroundStyle(Grimoire.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .scaleEffect(showsAcorn && savedBump ? 1.15 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }

    private var divider: some View {
        Rectangle().fill(Grimoire.border).frame(width: 1, height: 32)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                showingCapture = true
            } label: {
                Label("New Insight", systemImage: "plus")
            }
            .buttonStyle(GrimoirePrimaryButton())
            .accessibilityLabel("Create a new insight")

            NavigationLink(value: Route.search) {
                Label("Search", systemImage: "magnifyingglass")
            }
            .buttonStyle(GrimoireSecondaryButton())
            .accessibilityLabel("Search saved insights")
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private func celebrate() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
        withAnimation(.easeOut(duration: 0.2)) { showingAcorn = true }
        if !reduceMotion {
            Task {
                // Timed to the acorn settling onto the tree.
                try? await Task.sleep(for: .seconds(0.55))
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { savedBump = true }
                try? await Task.sleep(for: .seconds(0.3))
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { savedBump = false }
            }
        }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(.easeIn(duration: 0.3)) { showingAcorn = false }
        }
    }
}

/// The tree's pressed state: a small settle, and nothing under Reduce Motion.
///
/// A `ButtonStyle` rather than a gesture recogniser, because the style receives
/// the link's own `isPressed` — the press and the navigation can never disagree
/// about whether a tap happened.
private struct TreePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressedTree(configuration: configuration)
    }

    private struct PressedTree: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
                .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
        }
    }
}
