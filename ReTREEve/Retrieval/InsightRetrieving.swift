//  InsightRetrieving.swift
//  One protocol so the search screen, the future App Intent, and the
//  benchmark harness all go through the same engine.

import Foundation
import SwiftData

/// Why one insight surfaced: which word landed, where it was found, and whether
/// the reader actually typed it.
///
/// Ranking matches against a search surface that includes machine-generated
/// related phrases the reader never sees. Reporting only the bare word was
/// misleading — "matched on improve" reads as false when `improve` appears
/// nowhere in the visible passage. Naming the source makes the claim true.
struct MatchEvidence: Hashable {
    enum Source: Hashable {
        case passage
        case bookTitle
        case author
        case note
        /// The machine-written phrases in `semanticDescription`. Invisible to
        /// the reader until we explain that this is what bridged the match.
        case relatedPhrases

        var isVisibleToReader: Bool { self != .relatedPhrases }
    }

    enum Origin: Hashable {
        /// A lemma of a word the reader actually typed.
        case yourWords
        /// A lemma only the on-device query expansion produced.
        case widenedSearch
    }

    let term: String
    let source: Source
    let origin: Origin
}

/// A candidate, never a certainty. The reader is the one who decides.
struct InsightMatch: Identifiable {
    enum Strength {
        case closest, possible, faint

        var label: String {
            switch self {
            case .closest:  "Closest"
            case .possible: "Possible"
            case .faint:    "Faint"
            }
        }
    }

    let insight: ReadingInsight
    /// Share of the best lexical evidence in this result set, 0…1.
    let confidence: Double
    let strength: Strength
    /// Everything that contributed, with provenance.
    let evidence: [MatchEvidence]
    /// Up to a few of the actual generated phrases that bridged the match, so
    /// the explanation can show its working rather than assert it.
    let bridgingPhrases: [String]

    var id: PersistentIdentifier { insight.persistentModelID }

    /// Words the reader typed that appear in text they can actually see.
    var yourWordsInText: [String] {
        evidence.filter { $0.origin == .yourWords && $0.source.isVisibleToReader }
            .map(\.term)
    }

    /// Words the reader typed that appear only in the generated index.
    var yourWordsInIndex: [String] {
        evidence.filter { $0.origin == .yourWords && !$0.source.isVisibleToReader }
            .map(\.term)
    }

    /// Terms neither typed nor visible — the search was widened to reach these.
    var widenedTerms: [String] {
        evidence.filter { $0.origin == .widenedSearch }.map(\.term)
    }

    /// Where the reader can see their own words, for naming the place.
    var visibleSources: Set<MatchEvidence.Source> {
        Set(evidence.filter { $0.origin == .yourWords && $0.source.isVisibleToReader }
            .map(\.source))
    }
}

protocol InsightRetrieving {
    func search(_ query: String) async throws -> [InsightMatch]
}
