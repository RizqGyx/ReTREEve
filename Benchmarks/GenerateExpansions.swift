// Regenerates docexp.json — the document expansions baked into the sample library.
//
// One generation is not enough. The model returns a different, sometimes very
// thin, list each time (one run gave Outliers only four phrases, which made
// "luck and being in the right place" unfindable). Unioning several passes
// trades a little save-time latency for a search surface that is actually
// stable. Run:  swift GenerateExpansions.swift

import Foundation
import FoundationModels

let seeds: [(book: String, text: String)] = [
 ("Atomic Habits", "Small improvements repeated consistently can create meaningful change over time."),
 ("Outliers", "Success can be influenced by effort, timing, opportunity, and environment."),
 ("Deep Work", "Focused work without distraction can produce unusually valuable results."),
 ("Mindset", "Abilities can develop through effort, strategy, and learning."),
 ("The Psychology of Money", "Financial decisions can be shaped by personal experience as much as logic."),
]

@Generable
struct PhraseList {
    @Guide(description: "Between 12 and 20 short phrases or single words. Plain casual vocabulary. No numbering, no explanations.")
    var phrases: [String]
}

// Three angles, so the union covers vocabulary one prompt alone would miss.
let angles = [
    """
    You help build a search index for a personal reading app. Given one saved reading \
    insight, list alternative everyday phrasings a person might type months later when \
    they only half-remember it. Prefer common casual words over the book's own vocabulary.
    """,
    """
    Given one saved reading insight, list the everyday SITUATIONS and feelings a reader \
    might be in when this idea becomes relevant to them, in plain words. Short phrases only.
    """,
    """
    Given one saved reading insight, list single keywords and near-synonyms for its core \
    concepts, including informal and imprecise words someone might misremember it by.
    """
]

func generate(_ seed: (book: String, text: String), instructions: String) async -> [String] {
    do {
        let session = LanguageModelSession(instructions: instructions)
        let r = try await session.respond(to: "Book: \(seed.book)\nInsight: \(seed.text)",
                                          generating: PhraseList.self)
        return r.content.phrases
    } catch {
        print("  error (\(seed.book)): \(error)")
        return []
    }
}

var all: [[String]] = []
for seed in seeds {
    var seen = Set<String>()
    var merged: [String] = []
    for angle in angles {
        for phrase in await generate(seed, instructions: angle) {
            let clean = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { continue }
            let key = clean.lowercased()
            if seen.insert(key).inserted { merged.append(clean.lowercased()) }
        }
    }
    print("\(seed.book): \(merged.count) phrases")
    print("  \(merged.joined(separator: " / "))\n")
    all.append(merged)
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted]
try encoder.encode(all).write(to: URL(fileURLWithPath: "docexp.json"))
print("wrote docexp.json")
