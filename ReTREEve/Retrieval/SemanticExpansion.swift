//  SemanticExpansion.swift
//  The cure for vocabulary mismatch, on both sides of the search.
//
//  A half-remembered query rarely shares words with the passage it is looking
//  for. Widening the DOCUMENT at save time and the QUERY at search time is what
//  took the benchmark from 3/10 to 9–10/10. Neither half is sufficient alone.
//
//  Everything here is optional. If the model is unavailable, expansion is
//  skipped and retrieval degrades to lexical-only — measurably worse, still
//  working, never broken.

import Foundation
import FoundationModels
import OSLog

@Generable
private struct PhraseList {
    @Guide(description: "Between 10 and 18 short everyday phrases or single words. Plain casual vocabulary. No numbering, no explanations.")
    var phrases: [String]
}

enum SemanticExpansion {

    /// Retained purely to keep the model resident. The first generation on a
    /// cold model measured 4.5s against ~150ms once warm, and a reader waiting
    /// on their own search is the worst possible moment to pay that. Warming
    /// starts when the search screen opens, while they are still typing.
    ///
    /// Deliberately not reused for generation: sessions accumulate a transcript,
    /// and a long-lived one eventually trips the 4096-token context limit.
    private static var warmingSession: LanguageModelSession?

    /// A search must never wait on the model indefinitely. Past this the
    /// expansion is abandoned and retrieval proceeds on the reader's own words.
    private static let queryTimeout: Duration = .seconds(5)

    static func prewarm() {
        guard isModelAvailable, warmingSession == nil else { return }
        let session = LanguageModelSession(instructions: queryInstructions)
        session.prewarm()
        warmingSession = session
    }

    static var isModelAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static var unavailabilityReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This device does not support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence is turned off in Settings."
        case .unavailable(.modelNotReady):
            return "The on-device model is still downloading."
        case .unavailable:
            return "The on-device model is unavailable right now."
        @unknown default:
            return "The on-device model is unavailable right now."
        }
    }

    /// Three angles rather than one. A single generation is unreliable: one run
    /// returned only four phrases for an insight, which made it unfindable by
    /// any wording but its own. Unioning several passes costs save-time latency
    /// the reader never waits on, and buys a search surface that holds up.
    private static let documentAngles = [
        """
        You help build a search index for a personal reading app. Given one saved \
        reading insight, list alternative everyday phrasings a person might type months \
        later when they only half-remember it. Prefer common casual words over the \
        book's own vocabulary.
        """,
        """
        Given one saved reading insight, list the everyday SITUATIONS and feelings a \
        reader might be in when this idea becomes relevant to them, in plain words. \
        Short phrases only.
        """,
        """
        Given one saved reading insight, list single keywords and near-synonyms for its \
        core concepts, including informal and imprecise words someone might misremember \
        it by.
        """
    ]

    private static let queryInstructions = """
    A reader is searching their own saved book highlights but only half-remembers \
    the idea. Rewrite their vague query into alternative phrasings and related \
    concept words that might appear in the highlight they are looking for. \
    Plain everyday vocabulary. Phrases only.
    """

    /// Generated once at save time and persisted to `semanticDescription`.
    /// The model returns different phrasings on every call, so regenerating this
    /// per search would make ranking irreproducible.
    static func expandDocument(passage: String, bookTitle: String) async -> [String] {
        var seen = Set<String>()
        var merged: [String] = []
        // Angles are independent: a context-window overflow or a content refusal
        // on one still leaves the others' vocabulary in the index.
        for angle in documentAngles {
            for phrase in await generateWithFallback(instructions: angle,
                                                     passage: passage,
                                                     bookTitle: bookTitle) {
                let clean = phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !clean.isEmpty, seen.insert(clean).inserted else { continue }
                merged.append(clean)
            }
        }
        return merged
    }

    /// The titled prompt first, then the passage on its own if that produced
    /// nothing.
    ///
    /// ── WHY THIS RETRY EXISTS ──────────────────────────────────────────────
    ///
    /// A two-line `Book: …\nInsight: …` prompt is rejected outright with
    /// `unsupportedLanguageOrLocale` when the passage is not English — measured,
    /// 3 attempts out of 3, and it fails in about 30ms rather than trying. The
    /// same passage sent WITHOUT the `Book:` line succeeds every time and comes
    /// back with English keywords, which is exactly what makes an Indonesian
    /// passage findable by an English query.
    ///
    /// The title is not what breaks it: an English `Book: (untitled)` line fails
    /// just as reliably. It is the labelled two-line shape. Rather than guess at
    /// the guardrail's rule, the code simply tries the richer prompt and falls
    /// back to the passage alone — so English insights keep the exact prompt
    /// their expansions were measured with, and everything else stops coming
    /// back empty.
    private static func generateWithFallback(instructions: String,
                                             passage: String,
                                             bookTitle: String) async -> [String] {
        let title = bookTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            let titled = await generate(instructions: instructions,
                                        prompt: "Book: \(title)\nInsight: \(passage)")
            if !titled.isEmpty { return titled }
        }

        let bare = await generate(instructions: instructions, prompt: passage)
        if !bare.isEmpty { return bare }

        // Last resort: expand the passage a piece at a time. See `chunks(of:)`.
        var seen = Set<String>()
        var merged: [String] = []
        for chunk in chunks(of: passage) {
            for phrase in await generate(instructions: instructions, prompt: chunk) {
                let clean = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty, seen.insert(clean.lowercased()).inserted else { continue }
                merged.append(clean)
            }
        }
        return merged
    }

    /// Sentence-sized pieces, each short enough to get past the language check.
    ///
    /// ── WHY LENGTH DECIDES THIS ────────────────────────────────────────────
    ///
    /// The on-device model rejects a non-English passage with
    /// `unsupportedLanguageOrLocale`, and the rejection is deterministic —
    /// measured 12 times out of 12 on the same passage, in both prompt shapes.
    /// What decides it is how much of the language the classifier can see:
    ///
    ///      8 words /  47 chars → accepted
    ///     11 words /  62 chars → accepted
    ///     14 words /  88 chars → rejected
    ///     18 words / 121 chars → rejected
    ///
    /// A short passage stays ambiguous enough to pass; a long one is
    /// unmistakably Indonesian and is refused outright. Splitting a rejected
    /// passage restored it completely: 3 chunks out of 3 succeeded where the
    /// whole passage had failed every time, yielding 49 phrases.
    ///
    /// The pieces lose the sentence around them, so the phrasings come back a
    /// little blunter. That is a fair trade for an insight that would otherwise
    /// have no search vocabulary at all.
    ///
    /// `maxWords` sits below the measured boundary rather than on it, and the
    /// chunk count is capped: expansion already costs three generations per
    /// angle, and a long import should not turn into a minute of model time.
    static func chunks(of passage: String, maxWords: Int = 10, limit: Int = 4) -> [String] {
        let sentences = passage
            .split(whereSeparator: { ".!?\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var out: [String] = []
        for sentence in sentences {
            let words = sentence.split(separator: " ").map(String.init)
            var index = 0
            while index < words.count {
                let piece = words[index..<min(index + maxWords, words.count)]
                out.append(piece.joined(separator: " "))
                index += maxWords
                if out.count >= limit { return out }
            }
        }
        return out
    }

    /// Transient by nature — regenerated per search, and time-boxed.
    static func expandQuery(_ query: String) async -> [String] {
        await withTimeout(queryTimeout) {
            await generate(instructions: queryInstructions, prompt: query)
        }
    }

    /// Returns `[]` if the work outruns the budget. Losing the expansion costs
    /// recall; blocking the reader costs the search.
    private static func withTimeout(_ duration: Duration,
                                    _ work: @escaping @Sendable () async -> [String]) async -> [String] {
        await withTaskGroup(of: [String]?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(for: duration)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? []
        }
    }

    /// One generation, with a single retry for failures that are not the model's
    /// settled opinion.
    ///
    /// ── WHY THIS LOGS ──────────────────────────────────────────────────────
    ///
    /// This used to be `catch { return [] }` with no log line. Expansion is an
    /// enhancement and must never break a save, so swallowing the error was
    /// right — but swallowing it SILENTLY meant four very different failures all
    /// looked like "no phrases": a refused passage, an unsupported language, an
    /// ANE inference failure, and a model that simply had nothing to say. From
    /// outside the app they were indistinguishable from "search is broken", and
    /// identifying which one was happening took several rounds of guessing.
    ///
    /// ── WHY IT RETRIES ─────────────────────────────────────────────────────
    ///
    /// A guardrail violation, a refusal and an unsupported language are settled:
    /// the same prompt will fail the same way, so a retry only wastes time.
    /// Everything else — the neural engine failing a request, a cancellation, a
    /// transient resource error — can succeed on a second attempt, and this runs
    /// in the background where one extra second costs the reader nothing.
    private static func generate(instructions: String, prompt: String) async -> [String] {
        guard isModelAvailable else { return [] }

        for attempt in 1...2 {
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: prompt, generating: PhraseList.self)
                if attempt > 1 {
                    Logger.retrieval.info("Expansion succeeded on retry")
                }
                return response.content.phrases
            } catch let error as LanguageModelSession.GenerationError {
                let (label, settled) = classify(error)
                Logger.retrieval.error(
                    "Expansion failed (\(label, privacy: .public), attempt \(attempt, privacy: .public))")
                if settled { return [] }
            } catch {
                Logger.retrieval.error(
                    "Expansion failed (\(String(describing: type(of: error)), privacy: .public), attempt \(attempt, privacy: .public))")
            }

            // Long enough for a busy neural engine to finish what it was doing.
            try? await Task.sleep(for: .milliseconds(400))
        }
        return []
    }

    /// `settled` means the same prompt will fail the same way, so do not retry.
    private static func classify(_ error: LanguageModelSession.GenerationError) -> (String, Bool) {
        switch error {
        case .guardrailViolation:          ("guardrail — content refused", true)
        case .unsupportedLanguageOrLocale: ("unsupported language", true)
        case .refusal:                     ("model refused", true)
        case .exceededContextWindowSize:   ("passage too long", true)
        case .unsupportedGuide:            ("unsupported output shape", true)
        case .assetsUnavailable:           ("model assets unavailable", false)
        case .rateLimited:                 ("rate limited", false)
        case .concurrentRequests:          ("concurrent requests", false)
        case .decodingFailure:             ("decoding failure", false)
        @unknown default:                  ("unknown", false)
        }
    }
}
