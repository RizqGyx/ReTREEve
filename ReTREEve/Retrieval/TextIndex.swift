//  TextIndex.swift
//  Lemmatising, stop-wording and BM25. Deliberately plain and inspectable —
//  the benchmark showed this lexical core outperforming Apple's sentence
//  embeddings, so it is the primary signal rather than a fallback.

import Foundation
import NaturalLanguage

enum TextIndex {

    /// A generic English stoplist. It is deliberately NOT tuned to the test
    /// queries — tuning it to them would make the benchmark meaningless.
    /// The last group is query-frame language specific to this product
    /// ("I remember reading something about…") which carries no topic signal.
    static let stopwords: Set<String> = [
        "a","an","the","of","and","or","to","in","on","at","is","are","was","were",
        "be","been","being","can","could","would","should","i","you","it","its",
        "that","this","these","those","for","by","as","with","from","but","if",
        "then","than","so","do","does","did","have","has","had","will","my","me",
        "we","they","them","their","he","she","his","her","some","any","more",
        "most","much","very","just","also","up","down","out","over","when","what",
        "how","why","which","who","there","here","not","no","only","other","others",
        "get","got","about","something","anything",
        "remember","remembered","read","reading"
    ]

    /// Lowercased lemmas with stopwords and very short tokens removed.
    static func lemmas(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text
        var out: [String] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                             unit: .word, scheme: .lemma,
                             options: [.omitPunctuation, .omitWhitespace]) { tag, range in
            let raw = String(text[range]).lowercased()
            let lemma = (tag?.rawValue.lowercased()).flatMap { $0.isEmpty ? nil : $0 } ?? raw
            if lemma.count > 2 && !stopwords.contains(lemma) { out.append(lemma) }
            return true
        }
        return out
    }

    /// Okapi BM25 over a small in-memory corpus.
    struct BM25 {
        private let docs: [[String]]
        private let termFrequency: [[String: Int]]
        private let documentFrequency: [String: Int]
        private let averageLength: Double
        private let k1 = 1.2
        private let b = 0.75

        init(documents: [[String]]) {
            docs = documents
            termFrequency = documents.map { doc in
                doc.reduce(into: [:]) { $0[$1, default: 0] += 1 }
            }
            var df: [String: Int] = [:]
            for doc in documents {
                for term in Set(doc) { df[term, default: 0] += 1 }
            }
            documentFrequency = df
            let total = documents.reduce(0) { $0 + $1.count }
            averageLength = documents.isEmpty ? 0 : Double(total) / Double(documents.count)
        }

        /// Returns the score plus the query terms that actually contributed,
        /// so a match can be explained rather than just asserted.
        func score(query: [String], document index: Int) -> (score: Double, matched: [String]) {
            guard docs.indices.contains(index), averageLength > 0 else { return (0, []) }
            let length = Double(docs[index].count)
            var total = 0.0
            var matched: [String] = []
            let n = Double(docs.count)

            for term in Set(query) {
                let f = Double(termFrequency[index][term] ?? 0)
                guard f > 0 else { continue }
                let df = Double(documentFrequency[term] ?? 0)
                let idf = log(1 + (n - df + 0.5) / (df + 0.5))
                total += idf * (f * (k1 + 1)) / (f + k1 * (1 - b + b * length / averageLength))
                matched.append(term)
            }
            return (total, matched)
        }
    }
}
