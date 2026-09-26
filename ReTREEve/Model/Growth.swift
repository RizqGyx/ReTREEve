//  Growth.swift
//  Turns what the reader has actually done into a tree.
//
//  Two behaviours feed the tree, because two behaviours are all the product
//  actually asks of a reader: keeping a passage, and finding it again later.
//
//  Weighting is the anti-spam mechanism: saving is the cheapest action to fake
//  and is worth the least. Finding again cannot be faked — it requires a passage
//  worth looking for months later, and the reader has to confirm it was the one
//  they meant. The formula is never shown to the reader.
//
//  ── WHY CONNECTIONS ARE GONE ───────────────────────────────────────────────
//
//  `connectionCount` used to be weighted ×6 here — the heaviest signal in the
//  formula — for a feature that was never built. Nothing in the app ever
//  incremented it, so the only non-zero values were seeded, and a third of the
//  growth formula was permanently unreachable. It no longer contributes.
//
//  The property stays on `ReadingInsight` rather than being deleted: the schema
//  has no migration plan, and a dormant column costs nothing next to the risk of
//  removing one.

import Foundation

enum TreeStage: Int, CaseIterable, Comparable {
    case sprout = 0, sapling, young, full, bearing

    static func < (a: TreeStage, b: TreeStage) -> Bool { a.rawValue < b.rawValue }

    var name: String {
        switch self {
        case .sprout:  "Sprout"
        case .sapling: "Sapling"
        case .young:   "Young tree"
        case .full:    "Full tree"
        case .bearing: "Bearing tree"
        }
    }

    /// Plain-language description. No numbers, no thresholds, no progress bars.
    var note: String {
        switch self {
        case .sprout:  "Just planted. Keep something that mattered and it starts."
        case .sapling: "Taking hold. A few ideas are keeping each other company."
        case .young:   "Filling out. Acorns are visible in the canopy now."
        case .full:    "Established. This is a reading memory with weight to it."
        case .bearing: "Bearing fruit. Passages you kept are finding their way back."
        }
    }

    /// How many levels of branching to draw.
    var depth: Int {
        switch self {
        case .sprout: 1; case .sapling: 3; case .young: 4; case .full: 5; case .bearing: 6
        }
    }

    /// Rescaled when connections stopped contributing. The old thresholds were
    /// set against a formula whose heaviest term has been removed; leaving them
    /// would have made the last two stages practically unreachable.
    fileprivate var threshold: Int {
        switch self {
        case .sprout: 0; case .sapling: 3; case .young: 9; case .full: 20; case .bearing: 40
        }
    }
}

struct GrowthSummary {
    var saved: Int
    var foundAgain: Int
    /// Distinct books represented in the library. Shown on Home, but it is a
    /// description of the shelf rather than an activity, so it earns no growth.
    var books: Int

    static let savedWeight = 1
    static let foundAgainWeight = 3

    var points: Int {
        saved * Self.savedWeight + foundAgain * Self.foundAgainWeight
    }

    var stage: TreeStage {
        TreeStage.allCases.last { points >= $0.threshold } ?? .sprout
    }

    /// 0…1 through the current stage. Drives drawing, never shown as a bar.
    var stageProgress: Double {
        let current = stage
        guard let next = TreeStage(rawValue: current.rawValue + 1) else { return 1 }
        let span = Double(next.threshold - current.threshold)
        guard span > 0 else { return 1 }
        return min(1, max(0, Double(points - current.threshold) / span))
    }

    init(insights: [ReadingInsight]) {
        saved = insights.count
        foundAgain = insights.reduce(0) { $0 + $1.retrievalCount }
        books = Set(insights.map(\.bookTitle)).count
    }

    init(saved: Int, foundAgain: Int, books: Int = 0) {
        self.saved = saved; self.foundAgain = foundAgain; self.books = books
    }
}
