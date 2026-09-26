//  SampleLibrary.swift
//  Seeded paraphrases used to exercise retrieval. These are NOT quotations —
//  they are short paraphrases written for testing and are labelled as such
//  everywhere they appear in the UI.
//
//  Each seed ships with a pre-generated search expansion, baked in so the sample
//  library stays searchable where Apple Intelligence is unavailable.
//
//  The seeds carry NO activity. They used to ship fabricated `retrievalCount`
//  and `connectionCount` values, which meant a fresh install opened on a tree
//  reporting four retrievals and two connections the reader had never made. The
//  library is sample content; the growth on the tree has to be the reader's own.
//
//  These expansions are the VERBATIM output of the on-device model in
//  Benchmarks/, generated from the passage alone. They are deliberately NOT
//  hand-tuned: an earlier version was written while looking at the test queries
//  and scored 9/9, which was the seed data flattering itself rather than a
//  measurement of retrieval.

import Foundation
import SwiftData

enum SampleLibrary {
    struct Seed {
        let text: String
        let book: String
        let author: String
        let note: String?
        let daysAgo: Int
        let expansion: [String]
    }

    static let seeds: [Seed] = [
        Seed(text: "Small improvements repeated consistently can create meaningful change over time.",
             book: "Atomic Habits", author: "James Clear",
             note: "Read this the week I gave up on the big plan.",
             daysAgo: 212,
             expansion: ["keep doing little things", "consistency is key",
                         "little steps", "gradual progress", "small wins",
                         "build habits", "repetition", "stay the course",
                         "make it a habit", "keep going", "persistence",
                         "gradual change", "consistent effort", "small actions",
                         "consistency pays off", "keep moving forward",
                         "build good habits", "keep it up", "small changes",
                         "habits matter.", "change takes time.",
                         "small steps count.", "consistency is key.",
                         "everyday habits.", "daily routines.", "mindful habits.",
                         "healthy habits.", "healthy lifestyle.",
                         "personal growth.", "self-improvement.", "motivation.",
                         "discipline.", "goal setting.", "resilience.",
                         "patience.", "progress.", "success.", "habit", "small",
                         "change", "time", "repeat", "consistently", "meaningful",
                         "improvement", "process", "work", "progress", "steps",
                         "habituation", "consistency", "habitual", "routine",
                         "effort"]),
        Seed(text: "Success can be influenced by effort, timing, opportunity, and environment.",
             book: "Outliers", author: "Malcolm Gladwell",
             note: nil,
             daysAgo: 168,
             expansion: ["effort matters.", "timing is key.",
                         "opportunities matter.", "environment impacts success.",
                         "hard work pays off.", "luck plays a role.",
                         "balance is important.", "persistence is crucial.",
                         "surround yourself with good people.",
                         "stay focused on your goals.",
                         "be open to new opportunities.", "work hard, play hard.",
                         "stay motivated.", "learn from failures.",
                         "stay positive.", "keep pushing forward.",
                         "stay organized.", "stay committed.", "timing matters.",
                         "opportunities arise.", "environment affects success.",
                         "persistence is key.", "balancing effort and chance.",
                         "building a solid foundation.",
                         "adaptability is crucial.", "overcoming obstacles.",
                         "continuous learning is important.",
                         "motivation drives achievement.", "setting goals.",
                         "resilience is vital.",
                         "taking risks can yield rewards.",
                         "collaborating with others.", "embracing challenges.",
                         "celebrating milestones.", "hard work", "luck", "chance",
                         "good timing", "support", "environment"]),
        Seed(text: "Focused work without distraction can produce unusually valuable results.",
             book: "Deep Work", author: "Cal Newport",
             note: "Worth remembering on days that feel busy but empty.",
             daysAgo: 96,
             expansion: ["focus", "concentrate", "deep", "dedicated",
                         "mindfulness", "immersion", "single-tasking",
                         "without-distraction", "quality", "productivity",
                         "value", "efficiency", "isolated", "quiet",
                         "time-blocking", "mental-space", "concentration"]),
        Seed(text: "Abilities can develop through effort, strategy, and learning.",
             book: "Mindset", author: "Carol S. Dweck",
             note: nil,
             daysAgo: 54,
             expansion: ["effort builds skills.", "strategy matters.",
                         "learning is key.", "trying hard to learn.",
                         "working on a challenge.", "feeling determined.",
                         "using strategies to succeed.", "practicing regularly.",
                         "feeling motivated.", "improving skills.",
                         "learning from mistakes.",
                         "persisting through difficulties.",
                         "feeling proud of progress.",
                         "seeing results over time.",
                         "feeling confident in abilities.", "trying new things.",
                         "embracing effort.", "feeling empowered by mindset.",
                         "taking action.", "feeling excited about growth.",
                         "feeling hopeful about future opportunities.", "work",
                         "learn", "strategy", "effort", "improve", "skill",
                         "practice", "knowledge", "growth", "development",
                         "brainpower", "potential", "mindset", "perspective",
                         "success", "achievement", "motivation", "focus", "goal"]),
        Seed(text: "Financial decisions can be shaped by personal experience as much as logic.",
             book: "The Psychology of Money", author: "Morgan Housel",
             note: "Explains more arguments than I expected it to.",
             daysAgo: 11,
             expansion: ["money choices depend on past stuff too.",
                         "what we've learned about money matters a lot.",
                         "our past experiences affect how we think about money.",
                         "money decisions are influenced by our past.",
                         "money choices are shaped by past experiences.",
                         "our past experiences impact our money decisions.",
                         "money choices are influenced by our past.",
                         "money choices are shaped by our past.", "money",
                         "finance", "spending", "saving", "investing", "income",
                         "expenses", "budgeting", "financial literacy",
                         "personal finance", "money management",
                         "economic factors", "financial habits",
                         "financial goals", "financial security",
                         "financial planning", "financial freedom",
                         "financial responsibility", "financial stress",
                         "financial mistakes"])
    ]

    /// Inserts the sample set once, on an empty store.
    static func seedIfNeeded(_ context: ModelContext) {
        let existing = try? context.fetchCount(FetchDescriptor<ReadingInsight>())
        guard (existing ?? 0) == 0 else {
            backfillSampleExpansions(context)
            return
        }

        for seed in seeds {
            let date = Calendar.current.date(byAdding: .day, value: -seed.daysAgo, to: .now) ?? .now
            let insight = ReadingInsight(selectedText: seed.text,
                                         bookTitle: seed.book,
                                         author: seed.author,
                                         personalContext: seed.note,
                                         createdAt: date,
                                         isSample: true)
            insight.semanticDescription = seed.expansion.joined(separator: ", ")
            context.insert(insight)
        }
        try? context.save()
    }

    /// Keeps seeded stores in step when the expansion text itself changes.
    private static func backfillSampleExpansions(_ context: ModelContext) {
        let descriptor = FetchDescriptor<ReadingInsight>(predicate: #Predicate { $0.isSample })
        guard let samples = try? context.fetch(descriptor) else { return }
        for insight in samples {
            guard let seed = seeds.first(where: { $0.book == insight.bookTitle }) else { continue }
            let expected = seed.expansion.joined(separator: ", ")
            if insight.semanticDescription != expected { insight.semanticDescription = expected }
        }
        clearSeededActivityOnce(samples, context)
        try? context.save()
    }

    /// Stores seeded before the counts were removed still hold them, and they
    /// would keep inflating the tree forever.
    ///
    /// Deliberately ONCE, behind a flag, rather than every launch: a sample
    /// passage is a real passage as far as retrieval is concerned, and a reader
    /// who genuinely found one again has earned that count. Clearing on every
    /// launch would quietly delete their activity instead of the fabricated kind.
    private static let seededActivityClearedKey = "SampleLibrary.seededActivityCleared"

    private static func clearSeededActivityOnce(_ samples: [ReadingInsight], _ context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: seededActivityClearedKey) else { return }
        for insight in samples {
            insight.retrievalCount = 0
            insight.connectionCount = 0
        }
        defaults.set(true, forKey: seededActivityClearedKey)
    }
}
