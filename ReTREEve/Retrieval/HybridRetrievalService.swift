//  HybridRetrievalService.swift
//  The engine proven in Benchmarks/ before any of this UI existed.
//
//    lexical BM25 over the expanded document surface   ← primary signal
//  + model-expanded query                              ← closes vocabulary gaps
//  + sentence-embedding cosine, weighted 0.15          ← tiebreak only
//
//  The embedding never overrides lexical evidence. On its own it scored 2/10
//  against BM25's 3/10, so it earns its place only by stopping equal-scoring
//  candidates from ordering arbitrarily.

import Foundation
import NaturalLanguage

struct HybridRetrievalService: InsightRetrieving {

    let insights: [ReadingInsight]
    /// Query expansion costs an on-device generation; the benchmark harness
    /// turns it off to measure the lexical core in isolation.
    var usesQueryExpansion: Bool = true

    private static let embedding = NLEmbedding.sentenceEmbedding(for: .english)

    /// A candidate must carry at least this share of the best lexical evidence
    /// to be shown at all. Without a floor, an unrelated one-word overlap would
    /// pad the list with results that only look like matches.
    private let evidenceFloor = 0.15
    private let maxResults = 5

    func search(_ query: String) async throws -> [InsightMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !insights.isEmpty else { return [] }

        // The reader's own words decide how confident a match may look; the
        // expansion is only allowed to widen what can be *found*.
        let originalTokens = Set(TextIndex.lemmas(trimmed))
        let expansion = usesQueryExpansion ? await SemanticExpansion.expandQuery(trimmed) : []
        let queryTokens = TextIndex.lemmas(([trimmed] + expansion).joined(separator: " "))
        guard !queryTokens.isEmpty else { return [] }

        let index = TextIndex.BM25(documents: insights.map { TextIndex.lemmas(searchSurface(for: $0)) })
        let scored = insights.indices.map { index.score(query: queryTokens, document: $0) }

        // No lexical evidence anywhere means no result. An all-zero array sorts
        // arbitrarily, and returning its head would be a confident-looking lie.
        guard let best = scored.map(\.score).max(), best > 0 else { return [] }

        let queryVector = Self.embedding?.vector(for: trimmed)

        let ranked = insights.indices.map { i -> (index: Int, combined: Double, lexical: Double, matched: [String]) in
            let lexical = scored[i].score / best
            var combined = lexical
            if let queryVector,
               let docVector = Self.embedding?.vector(for: insights[i].selectedText) {
                combined += 0.15 * cosine(queryVector, docVector)
            }
            return (i, combined, lexical, scored[i].matched)
        }
        .filter { $0.lexical >= evidenceFloor }
        .sorted { $0.combined > $1.combined }
        .prefix(maxResults)

        return ranked.map { entry in
            let insight = insights[entry.index]
            let hit = Set(entry.matched)
            let fields = fieldLemmas(for: insight)
            // Share of the reader's own content words this insight accounts for.
            // Scoring purely on rank-relative position made a single weak result
            // render as the strongest possible match, because it was being
            // normalised against itself.
            let coverage = originalTokens.isEmpty ? 0
                : Double(originalTokens.intersection(hit).count) / Double(originalTokens.count)

            let evidence = hit.sorted().map { term in
                MatchEvidence(term: term,
                              source: source(of: term, in: fields),
                              origin: originalTokens.contains(term) ? .yourWords : .widenedSearch)
            }
            let bridged = evidence.contains { !$0.source.isVisibleToReader }
                ? bridgingPhrases(for: insight, matching: hit)
                : []

            return InsightMatch(insight: insight,
                                confidence: coverage,
                                strength: strength(for: coverage),
                                evidence: evidence,
                                bridgingPhrases: bridged)
        }
    }

    // MARK: - Provenance
    //
    // Computed only for the handful of results actually shown, never for the
    // whole corpus, and it does not participate in scoring.

    private struct FieldLemmas {
        let passage: Set<String>
        let title: Set<String>
        let author: Set<String>
        let note: Set<String>
        let related: Set<String>
    }

    private func fieldLemmas(for insight: ReadingInsight) -> FieldLemmas {
        FieldLemmas(passage: Set(TextIndex.lemmas(insight.selectedText)),
                    title: Set(TextIndex.lemmas(insight.bookTitle)),
                    author: Set(TextIndex.lemmas(insight.author ?? "")),
                    note: Set(TextIndex.lemmas(insight.personalContext ?? "")),
                    related: Set(TextIndex.lemmas(insight.semanticDescription ?? "")))
    }

    /// Visible fields win over the generated index, so a word the reader can
    /// actually see is always reported as being where they can see it.
    private func source(of term: String, in fields: FieldLemmas) -> MatchEvidence.Source {
        if fields.passage.contains(term) { return .passage }
        if fields.title.contains(term) { return .bookTitle }
        if fields.note.contains(term) { return .note }
        if fields.author.contains(term) { return .author }
        return .relatedPhrases
    }

    /// The actual generated phrases that carried the match, so the explanation
    /// can show its working instead of asserting a connection.
    private func bridgingPhrases(for insight: ReadingInsight, matching hit: Set<String>) -> [String] {
        guard let description = insight.semanticDescription else { return [] }
        return description
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { phrase in
                !phrase.isEmpty && !Set(TextIndex.lemmas(phrase)).isDisjoint(with: hit)
            }
            .prefix(3)
            .map { $0 }
    }

    /// Everything a reader might half-remember about this insight: the words
    /// they read, the words they wrote, and the machine-written paraphrases.
    /// The title is weighted by repetition.
    private func searchSurface(for insight: ReadingInsight) -> String {
        [insight.bookTitle,
         insight.bookTitle,
         insight.author ?? "",
         insight.selectedText,
         insight.personalContext ?? "",
         insight.semanticDescription ?? ""]
            .joined(separator: " ")
    }

    /// Reads as "how much of what you typed did we actually find", which is a
    /// claim the engine can support — unlike a percentage.
    private func strength(for coverage: Double) -> InsightMatch.Strength {
        switch coverage {
        case 0.66...: .closest
        case 0.34...: .possible
        default:      .faint
        }
    }

    private func cosine(_ a: [Double], _ b: [Double]) -> Double {
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<min(a.count, b.count) {
            dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (sqrt(na) * sqrt(nb))
    }
}
