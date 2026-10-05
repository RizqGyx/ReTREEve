//  LibraryView.swift
//  My Grimoire — a collection of passages, not a catalogue of books.
//
//  ── WHAT DECIDES THE LAYOUT ────────────────────────────────────────────────
//
//  The passage leads every row. A reader scanning their own shelf is looking for
//  a thought they recognise; the book is how they confirm it once they have. An
//  earlier version led with the book title and read as a bibliography.
//
//  ── THREE DIFFERENT KINDS OF NOTHING ───────────────────────────────────────
//
//  "You have saved nothing", "your filters exclude everything" and "that word
//  appears nowhere" are three different situations with three different fixes,
//  and showing the same screen for all of them tells the reader their library is
//  empty when it is not. Each gets its own state and its own way out.
//
//  ── WHY THERE IS A FILTER FIELD HERE AT ALL ────────────────────────────────
//
//  This screen shipped without one, on the reasoning that a second search box
//  one tap from Find Again would blur the product's central idea. That was wrong
//  about the smaller job: scrolling a shelf for something you CAN name stopped
//  being comfortable at ten insights, long before the semantic search has
//  anything to do. The two stay distinct — this matches literal text and only
//  narrows what is on screen, and when it finds nothing it points at Find Again.

import SwiftUI
import SwiftData

struct LibraryView: View {
    @Query(sort: \ReadingInsight.createdAt, order: .reverse)
    private var insights: [ReadingInsight]
    @Environment(\.modelContext) private var context

    @State private var options = LibraryOptions()
    @State private var draftOptions = LibraryOptions()
    @State private var showingFilters = false
    @State private var query = ""
    /// Only the empty state uses this — everywhere else capture starts from
    /// Home. Presented here so an empty shelf is not a dead end.
    @State private var startingCapture = false

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visible: [ReadingInsight] {
        options.apply(to: insights, matching: trimmedQuery)
    }

    /// Books in the order the current sort implies, each with its passages.
    private var books: [(title: String, items: [ReadingInsight])] {
        let grouped = Dictionary(grouping: visible, by: \.bookTitle)
        let ordered = grouped.map { (title: $0.key, items: $0.value) }
        switch options.sort {
        case .bookDescending:
            return ordered.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        case .newest, .oldest, .bookAscending:
            return ordered.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    var body: some View {
        Group {
            if insights.isEmpty {
                emptyGrimoire
            } else if visible.isEmpty {
                // Which nothing this is depends on what the reader last did.
                if !trimmedQuery.isEmpty { noSearchResults } else { noFilterResults }
            } else if options.groupsByBook {
                bookList
            } else {
                passageList
            }
        }
        .magicalBackground(.subtle)
        // A centred inline title between Back and Filter, as the design has it.
        // The large "My Grimoire" title spent the top of the screen repeating
        // what the reader had just tapped on Home.
        .grimoireNavigationTitle("Grimoire")
        .searchable(text: $query, prompt: "Search your grimoire")
        .toolbar {
            if !insights.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        draftOptions = options
                        showingFilters = true
                    } label: {
                        // Filled only while something other than the default
                        // is applied, so a changed view never goes unnoticed.
                        Image(systemName: options.isDefault
                              ? "line.3.horizontal.decrease"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel("Filter and sort")
                    .accessibilityValue(options.summary)
                }
            }
        }
        .sheet(isPresented: $showingFilters) {
            LibraryFilterSheet(options: $draftOptions) { options = draftOptions }
        }
        .fullScreenCover(isPresented: $startingCapture) { CaptureFlowView() }
    }

    // MARK: - Lists

    private var passageList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                sectionHeader(countLabel)

                ForEach(visible) { insight in
                    NavigationLink(value: Route.saved(insight)) {
                        LibraryPassageCard(insight: insight)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private var bookList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                sectionHeader("Books  |  Total \(books.count)")

                ForEach(books, id: \.title) { book in
                    NavigationLink(value: Route.book(title: book.title)) {
                        BookGroupCard(title: book.title,
                                      author: book.items.first?.author,
                                      count: book.items.count)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private var countLabel: String {
        visible.count == insights.count
            ? "Library of Passages  |  Total \(insights.count)"
            : "Library of Passages  |  \(visible.count) of \(insights.count)"
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.grimoire(.caption1, .emphasized))
            .foregroundStyle(Grimoire.textSecondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 4)
    }

    // MARK: - States

    private var emptyGrimoire: some View {
        LibraryEmptyState(
            title: "Your grimoire is waiting.",
            message: "Save your first meaningful passage to begin growing your collection.",
            actionTitle: "New Insight",
            action: { startingCapture = true })
    }

    private var noFilterResults: some View {
        LibraryEmptyState(
            title: "No insights found.",
            message: "Try changing your filters.",
            actionTitle: "Reset Filters",
            action: { options = LibraryOptions() })
    }

    private var noSearchResults: some View {
        LibraryEmptyState(
            // The query stays on screen: a reader who mistyped needs to see what
            // was actually searched before they can fix it.
            title: "No matching insights.",
            message: "Nothing contains “\(trimmedQuery)”. Try another word or phrase.",
            actionTitle: "Clear Search",
            action: { query = "" })
    }
}

// MARK: - Cards

/// One saved passage. The passage leads, set off by the gilt quote mark; the book
/// names it; the last line says whose words and when they were kept.
///
/// The author line always has something in it — "Unknown Author" when none was
/// written — so every card has the same shape. The page is different: a page
/// that was never noted is simply left out, because "Page —" is noise.
struct LibraryPassageCard: View {
    let insight: ReadingInsight

    private var sourceLine: String {
        [insight.displayAuthor, insight.pageLabel]
            .compactMap { $0 }
            .joined(separator: "  |  ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            PassageQuoteMark(size: 18)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 8) {
                Text(insight.preview(limit: 150))
                    .font(.grimoire(.body))
                    .foregroundStyle(Grimoire.textPrimary)
                    .lineSpacing(2)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    // Clears the chevron in the top-right corner.
                    .padding(.trailing, 22)

                HStack(spacing: 6) {
                    Text(insight.bookTitle)
                        .font(.grimoire(.subhead, .emphasized))
                        .foregroundStyle(Grimoire.primary)
                        .lineLimit(1)
                    if insight.isSample { SampleTag() }
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(sourceLine)
                        .font(.grimoire(.footnote))
                        .foregroundStyle(Grimoire.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(insight.savedDateLabel)
                        .font(.grimoire(.footnote))
                        .foregroundStyle(Grimoire.textSecondary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: "chevron.right")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Grimoire.primary)
                .padding(.top, 3)
        }
        .padding(16)
        .libraryCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Opens this insight")
        .accessibilityAddTraits(.isButton)
    }

    /// Book, then passage, then source and date — the order a reader would say
    /// it aloud.
    private var accessibilityDescription: String {
        [insight.bookTitle, insight.preview(limit: 150), sourceLine, "Saved \(insight.savedDateLabel)"]
            .joined(separator: ". ")
    }
}

private extension View {
    /// The card both library rows share: warm surface, hairline border and a
    /// shadow deep enough to lift it off the illustration, as in the design.
    func libraryCard() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Grimoire.surface,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Grimoire.border, lineWidth: 1))
            .shadow(color: Grimoire.textPrimary.opacity(0.12), radius: 10, y: 5)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// One book, in the grouped display mode.
struct BookGroupCard: View {
    let title: String
    let author: String?
    let count: Int

    var body: some View {
        HStack(spacing: 14) {
            BookInitialsIcon(title: title)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.grimoire(.headline))
                    .foregroundStyle(Grimoire.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let author, !author.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(author)
                        .font(.grimoire(.subhead))
                        .foregroundStyle(Grimoire.textSecondary)
                        .lineLimit(1)
                }
                Text("\(count) \(count == 1 ? "insight" : "insights")")
                    .font(.grimoire(.footnote))
                    .foregroundStyle(Grimoire.textSecondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Grimoire.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .libraryCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(count) \(count == 1 ? "insight" : "insights")")
        .accessibilityHint("Opens this book's passages")
        .accessibilityAddTraits(.isButton)
    }
}

/// A closed book with the title's initials on its cover — "AH" for Atomic
/// Habits, "I" for Ikigai — so books are told apart at a glance before their
/// titles are read.
struct BookInitialsIcon: View {
    let title: String

    @ScaledMetric private var size: CGFloat

    init(title: String, size: CGFloat = 46) {
        self.title = title
        _size = ScaledMetric(wrappedValue: size, relativeTo: .headline)
    }

    private var initials: String { BookInitials.from(title) }

    var body: some View {
        Image(systemName: "book.closed.fill")
            .font(.system(size: size))
            .foregroundStyle(Grimoire.primary)
            .overlay {
                if !initials.isEmpty {
                    Text(initials)
                        .font(.system(size: size * (initials.count > 1 ? 0.28 : 0.34),
                                      weight: .bold, design: .rounded))
                        .foregroundStyle(Grimoire.surface)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        // The symbol's cover sits right of its spine and above its
                        // page edge, so the letters are nudged onto the cover.
                        .offset(x: size * 0.06, y: -size * 0.06)
                }
            }
            .frame(minWidth: size, minHeight: size)
            .accessibilityHidden(true)
    }
}

/// Up to two letters taken from a book title.
///
/// Small joining words are skipped — in English and Indonesian — so "The
/// Psychology of Money" becomes "PM" rather than "TP". A title with no letters
/// or digits at all gets no initials, and the icon shows a plain book.
enum BookInitials {
    private static let minorWords: Set<String> = [
        "the", "a", "an", "of", "and", "to", "in", "on", "for", "at", "by", "with",
        "dan", "di", "ke", "dari", "yang", "untuk", "dengan", "sang", "si", "para"
    ]

    static func from(_ title: String) -> String {
        let words = title
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        let significant = words.filter { !minorWords.contains($0.lowercased()) }
        let source = significant.isEmpty ? words : significant
        return source
            .prefix(2)
            .compactMap(\.first)
            .map { String($0).uppercased() }
            .joined()
    }
}

/// The shared shape of every "nothing here" screen.
struct LibraryEmptyState: View {
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Grimoire.accentMagicSoft.opacity(0.6))
                        .frame(width: 180, height: 180)
                        .blur(radius: 28)
                    Image("Grimoire")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 160)
                        .gentleFloat(amplitude: 4, duration: 3.8)
                    MagicSparkle(size: 14, delay: 0.2).offset(x: 80, y: -58)
                    MagicSparkle(size: 10, opacity: 0.75, delay: 0.7).offset(x: -82, y: -16)
                }
                .accessibilityHidden(true)

                Text(title)
                    .font(.grimoire(.title3, .emphasized))
                    .foregroundStyle(Grimoire.textPrimary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.grimoire(.subhead))
                    .foregroundStyle(Grimoire.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 36)

                Button(actionTitle, action: action)
                    .buttonStyle(GrimoirePrimaryButton())
                    .padding(.horizontal, 46)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// One book's passages. Reached from the grouped display mode.
struct BookInsightsView: View {
    let bookTitle: String

    @Query(sort: \ReadingInsight.createdAt, order: .reverse)
    private var insights: [ReadingInsight]

    private var items: [ReadingInsight] {
        insights.filter { $0.bookTitle == bookTitle }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(items) { insight in
                    NavigationLink(value: Route.saved(insight)) {
                        LibraryPassageCard(insight: insight)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .magicalBackground(.subtle)
        .navigationTitle(bookTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}
