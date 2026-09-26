//  ReadingInsight.swift
//  The single stored artefact: one meaningful thing a reader kept.

import Foundation
import SwiftData

@Model
final class ReadingInsight {
    var id: UUID = UUID()

    /// The passage exactly as it was captured. Written once, never rewritten.
    var selectedText: String = ""

    var bookTitle: String = ""
    var author: String?

    /// "Why did this stand out?" — always optional, never demanded.
    var personalContext: String?

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// Times the reader confirmed, from Possible Matches, that this was the
    /// passage they were looking for. Feeds tree growth. Incremented only by an
    /// explicit "Found It" — never by opening a search result.
    var retrievalCount: Int = 0

    /// Where in the book it was, as the reader wrote it — "123", "p. 12–13",
    /// "ch. 4". A string rather than an Int because a page reference is a note
    /// to a human, not an index, and a book with unnumbered pages or two-page
    /// spreads would otherwise have nowhere to put the truth.
    ///
    /// Optional with a nil default, which is what keeps SwiftData's lightweight
    /// migration able to open an existing store — the schema still has no
    /// versioned plan, so every property added here has to be of this shape.
    var pageReference: String?

    /// DORMANT. Written only to zero, read only by nothing.
    ///
    /// It backed a Reconnect feature that was never built: no code ever
    /// incremented it, and it is no longer part of growth or of any screen. The
    /// property stays because the schema has no migration plan and a dormant
    /// column is cheaper than a risky removal.
    var connectionCount: Int = 0

    /// Machine-written alternative phrasings that widen the search surface.
    /// Generated once at save time in Phase 2; nil here in Phase 1.
    var semanticDescription: String?

    /// Marks the seeded paraphrases so the UI can label them honestly.
    var isSample: Bool = false

    init(selectedText: String,
         bookTitle: String,
         author: String? = nil,
         pageReference: String? = nil,
         personalContext: String? = nil,
         createdAt: Date = .now,
         isSample: Bool = false) {
        self.id = UUID()
        self.selectedText = selectedText
        self.bookTitle = bookTitle
        self.author = author
        self.pageReference = pageReference
        self.personalContext = personalContext
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.retrievalCount = 0
        self.connectionCount = 0
        self.isSample = isSample
    }
}

extension ReadingInsight {
    var displayAuthor: String {
        guard let author, !author.trimmingCharacters(in: .whitespaces).isEmpty else { return "Unknown Author" }
        return author
    }

    /// "Page 121", or the reader's own label if they typed one ("pp. 12–14").
    /// `nil` when no page was written down, so callers show nothing at all
    /// rather than a placeholder.
    var pageLabel: String? {
        guard let page = pageReference?.trimmingCharacters(in: .whitespacesAndNewlines),
              !page.isEmpty else { return nil }
        return page.allSatisfy(\.isNumber) ? "Page \(page)" : page
    }

    /// "Today", "Yesterday", otherwise "13 September 2026".
    ///
    /// Relative for the two days a reader thinks of that way; a full date after
    /// that, because "5 days ago" stops meaning anything once the list is long.
    var savedDateLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(createdAt) { return "Today" }
        if calendar.isDateInYesterday(createdAt) { return "Yesterday" }
        return createdAt.formatted(.dateTime.day().month(.wide).year()
            .locale(Locale(identifier: "en_GB")))
    }

    /// "James Clear · p. 123", with each half optional. Built here so the
    /// library row, the detail screen and the share text cannot disagree.
    var attributionLine: String {
        var parts: [String] = []
        if let author, !author.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append(author)
        }
        if let page = pageReference?.trimmingCharacters(in: .whitespacesAndNewlines),
           !page.isEmpty {
            // A bare number reads as a page; anything else the reader typed is
            // already the label they wanted.
            parts.append(page.allSatisfy(\.isNumber) ? "p. \(page)" : page)
        }
        return parts.joined(separator: " · ")
    }

    var hasPageReference: Bool {
        guard let pageReference else { return false }
        return !pageReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasNote: Bool {
        guard let personalContext else { return false }
        return !personalContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The single-word keywords the machine filed this insight under.
    ///
    /// `semanticDescription` holds both phrases and bare keywords; only the
    /// bare ones are worth showing — "they seem to have gone through a growth
    /// spurt" tells a reader nothing about findability, while "aging, wrinkles,
    /// youth" tells them exactly what will reach it.
    var searchKeywords: [String] {
        guard let semanticDescription else { return [] }
        var seen = Set<String>()
        return semanticDescription
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.contains(" ") && $0.count > 2 && seen.insert($0).inserted }
    }

    /// True when the search vocabulary was never generated — the insight is then
    /// reachable only by its own literal words, which is the difference between
    /// "I half-remember this" working and not working.
    var isMissingSearchVocabulary: Bool {
        (semanticDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A short preview for list rows, cut on a word boundary.
    func preview(limit: Int = 120) -> String {
        let flat = selectedText.replacingOccurrences(of: "\n", with: " ")
        guard flat.count > limit else { return flat }
        let cut = flat.prefix(limit)
        let end = cut.lastIndex(of: " ") ?? cut.endIndex
        return String(cut[..<end]) + "…"
    }
}
