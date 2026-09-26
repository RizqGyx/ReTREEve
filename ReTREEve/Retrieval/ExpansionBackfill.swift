//  ExpansionBackfill.swift
//  Gives an insight its search vocabulary when it was saved without one.
//
//  ── WHY THIS IS NEEDED ─────────────────────────────────────────────────────
//
//  `semanticDescription` is written once, in the background, just after an
//  insight is saved. When that generation fails the insight is committed anyway
//  — losing the passage would be far worse than losing its expansion — and it
//  stays findable only by its own literal words.
//
//  Failures are not rare. A non-English passage was rejected outright by the
//  titled prompt until `generateWithFallback` was added, so every insight saved
//  in that period has no expansion at all. Without a backfill, fixing the prompt
//  would only help insights saved from now on, and the reader would search for
//  the passage that prompted the fix and still find nothing.
//
//  ── DELIBERATELY SLOW ──────────────────────────────────────────────────────
//
//  A handful per launch, not the whole library. Each insight costs three
//  generations, and a reader who imported fifty passages should not have the
//  model running for minutes behind their first screen. The remainder is picked
//  up next launch, and nothing waits on any of it.

import Foundation
import SwiftData
import OSLog

enum ExpansionBackfill {

    /// How many insights to repair per launch. Three generations each, so this
    /// is already several seconds of model time.
    static let perLaunchLimit = 3

    /// Fills in missing expansions, oldest first, without blocking anything.
    ///
    /// Samples are excluded: `SampleLibrary` owns their expansions and rewrites
    /// them from compile-time constants, so generating one here would be undone
    /// on the next launch.
    @MainActor
    static func run(context: ModelContext) async {
        guard SemanticExpansion.isModelAvailable else { return }

        var descriptor = FetchDescriptor<ReadingInsight>(
            predicate: #Predicate { $0.semanticDescription == nil && !$0.isSample },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        descriptor.fetchLimit = perLaunchLimit

        guard let pending = try? context.fetch(descriptor), !pending.isEmpty else { return }

        Logger.retrieval.info("Backfilling expansions for \(pending.count, privacy: .public) insight(s)")

        for insight in pending {
            // Read the values out before awaiting: the insight can be deleted
            // while the model is working, and touching a deleted model traps.
            let passage = insight.selectedText
            let title = insight.bookTitle
            guard !passage.isEmpty else { continue }

            let phrases = await SemanticExpansion.expandDocument(passage: passage,
                                                                bookTitle: title)
            guard !phrases.isEmpty else { continue }

            // Re-fetch rather than trusting the reference across the await.
            let id = insight.persistentModelID
            guard let live = context.model(for: id) as? ReadingInsight else { continue }
            live.semanticDescription = phrases.joined(separator: ", ")
            try? context.save()
        }
    }
}

extension Logger {
    nonisolated static let retrieval = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ReTREEve",
        category: "retrieval")
}
