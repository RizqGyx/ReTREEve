//  InsightDetailView.swift
//  A reading surface, not a form. The passage gets primacy: largest type on the
//  screen, set off by a gilt quote mark and rule, with everything else deferring
//  to it.
//
//  ── ONE LAYOUT, TWO ARRIVALS ───────────────────────────────────────────────
//
//  From the Library and from Possible Matches the screen is the same page. Two
//  things differ, and only because the reader's question differs:
//    • the book card's last line — "3 insights saved" when browsing a shelf,
//      "Possible match from your grimoire" when checking a search result;
//    • Found It, which appears only after a search.
//
//  ── "FOUND IT" ─────────────────────────────────────────────────────────────
//
//  This screen is the only place a retrieval can be confirmed, and it only
//  offers the confirmation when the reader arrived from Possible Matches.
//
//  Opening a search result used to increment `retrievalCount` on the tap that
//  pushed this screen. That counted the wrong thing: a reader opens a candidate
//  precisely because they are not yet sure, and half the time the answer is "no,
//  not this one". Growth measured that as a successful recall. Now the reader
//  says so, or does not, and the tree only hears about the ones that worked.
//
//  Opened from the Library, no confirmation is offered at all — browsing your
//  own shelf is not retrieval from partial memory, and a button there would
//  collect taps that mean nothing.

import SwiftUI
import SwiftData

struct InsightDetailView: View {
    let insight: ReadingInsight
    /// Set only by `Route.match`, i.e. arriving from Possible Matches. Its
    /// presence is what offers "Found It"; its value scopes the confirmation to
    /// one search, so reopening this passage from the same results cannot count
    /// it twice.
    var searchSession: UUID? = nil

    @Environment(RetrievalLedger.self) private var ledger

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ReadingInsight.createdAt, order: .reverse)
    private var allInsights: [ReadingInsight]

    @State private var editing = false
    @State private var confirmingDelete = false
    /// Deleting a SwiftData model that a visible view still reads from can trap.
    /// The pop is started first and the delete runs once this view is gone.
    @State private var deleteOnDisappear = false

    /// One confirmation per visit. The button is replaced by an acknowledgement
    /// rather than staying tappable, so re-rendering, rotating, returning from
    /// the edit sheet or backgrounding the app cannot add a second count.
    /// A later search that lands here again is a genuinely new retrieval, and
    /// that push builds a new view with this reset — which is correct.
    @State private var didConfirmRetrieval = false

    private var arrivedFromSearch: Bool { searchSession != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TitleFlourish()
                    .frame(maxWidth: .infinity)
                    .padding(.top, -6)

                bookCard

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Passage")
                    passageCard
                }

                if insight.hasNote {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Why it matters to me")
                        noteCard
                    }
                }

                details

                findability

                if arrivedFromSearch { foundItSection }

                closingIllustration
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .magicalBackground(.normal)
        .grimoireNavigationTitle(insight.bookTitle)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { editing = true } label: { Label("Edit Details", systemImage: "pencil") }
                    ShareLink(item: shareText) { Label("Share", systemImage: "square.and.arrow.up") }
                    Divider()
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Actions")
            }
        }
        .sheet(isPresented: $editing) {
            NavigationStack {
                InsightEditorView(mode: .edit(insight),
                                  showsCancel: true,
                                  onDone: { editing = false },
                                  onCancel: { editing = false })
            }
            .tint(Grimoire.primary)
        }
        .confirmationDialog("Delete Insight?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                deleteOnDisappear = true
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This insight will be permanently removed from your grimoire.")
        }
        .onDisappear {
            guard deleteOnDisappear else { return }
            context.delete(insight)
            try? context.save()
        }
    }

    // MARK: - Book

    /// Book, then author only if there is one. Here the book is the subject of
    /// the card, and "Unknown Author" under its title would state the absence of
    /// something the reader chose not to record.
    private var bookCard: some View {
        HStack(spacing: 16) {
            BookInitialsIcon(title: insight.bookTitle)
                .padding(12)
                .background(Grimoire.primarySoft,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(insight.bookTitle)
                    .font(.grimoire(.title3, .emphasized))
                    .foregroundStyle(Grimoire.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let author = insight.author,
                   !author.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(author)
                        .font(.grimoire(.subhead))
                        .foregroundStyle(Grimoire.textSecondary)
                }

                Label(bookCardFootnote, systemImage: "book")
                    .font(.grimoire(.footnote))
                    .foregroundStyle(Grimoire.textSecondary)
                    .padding(.top, 2)

                if insight.isSample { SampleTag().padding(.top, 2) }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .detailCard(sprig: true)
        .accessibilityElement(children: .combine)
    }

    private var bookCardFootnote: String {
        if arrivedFromSearch { return "Possible match from your grimoire" }
        let count = allInsights.filter { $0.bookTitle == insight.bookTitle }.count
        return "\(count) \(count == 1 ? "insight" : "insights") saved"
    }

    // MARK: - Passage & note

    private var passageCard: some View {
        HStack(alignment: .top, spacing: 12) {
            PassageQuoteMark(size: 26)
                .padding(.top, 2)

            Text(insight.selectedText)
                .font(.grimoire(.title3))
                .foregroundStyle(Grimoire.textPrimary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 14)
        }
        .padding(.vertical, 20)
        .padding(.leading, 20)
        .padding(.trailing, 16)
        // A gilt rule down the leading edge, like a marked margin.
        .background(alignment: .leading) {
            Rectangle()
                .fill(Grimoire.accentMagic)
                .frame(width: 4)
        }
        .detailCard(sprig: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Passage. \(insight.selectedText)")
    }

    private var noteCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image("Leaf")
                .resizable()
                .scaledToFit()
                .padding(7)
                .frame(width: 34, height: 34)
                .background(Grimoire.primarySoft,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)

            Text(insight.personalContext ?? "")
                .font(.grimoire(.callout))
                .foregroundStyle(Grimoire.textPrimary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 5)
        }
        .padding(16)
        .detailCard(sprig: false)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Details

    /// When it was kept, where in the book, and how often it has come back.
    /// Page and the found-again count appear only when there is something to say.
    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            detailLine(savedText, systemImage: "calendar")
            if let page = insight.pageLabel {
                detailLine(page, systemImage: "bookmark")
            }
            if insight.retrievalCount > 0 {
                Label {
                    Text("Found again \(insight.retrievalCount)×")
                } icon: {
                    Image(systemName: "sparkles")
                }
                .font(.grimoire(.footnote))
                .foregroundStyle(Grimoire.accentMystic)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private func detailLine(_ text: String, systemImage: String) -> some View {
        Label {
            Text(text).foregroundStyle(Grimoire.textSecondary)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(Grimoire.primary)
        }
        .font(.grimoire(.subhead))
    }

    /// "Saved today", "Saved yesterday", "Saved 14 February 2026".
    private var savedText: String {
        let label = insight.savedDateLabel
        let relative = Calendar.current.isDateInToday(insight.createdAt)
            || Calendar.current.isDateInYesterday(insight.createdAt)
        return "Saved \(relative ? label.lowercased() : label)"
    }

    /// What this insight can be found by, and — more importantly — when it
    /// cannot be found by anything but its own words.
    ///
    /// The expansion runs in the background after a save and can fail silently:
    /// the on-device model refuses some passages outright, and a reader then has
    /// an insight that only answers to the exact wording they captured. That
    /// looked identical to "search is broken" from the outside, and cost three
    /// rounds of guessing to identify. It is one line on screen to make obvious.
    @ViewBuilder
    private var findability: some View {
        if insight.isMissingSearchVocabulary {
            Label {
                Text("Only findable by its own words. Related-word indexing hasn't run for this one yet.")
                    .foregroundStyle(Grimoire.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(Grimoire.accentMagic)
            }
            .font(.grimoire(.footnote))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        } else if !insight.searchKeywords.isEmpty {
            let keywords = Array(insight.searchKeywords.prefix(10))
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Also findable by", systemImage: "sparkle.magnifyingglass")

                ChipFlowLayout(spacing: 8) {
                    ForEach(keywords, id: \.self) { keyword in
                        Text(keyword)
                            .font(.grimoire(.subhead))
                            .foregroundStyle(Grimoire.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Grimoire.secondarySoft, in: Capsule())
                            .overlay(Capsule().strokeBorder(Grimoire.border, lineWidth: 1))
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Also findable by \(keywords.joined(separator: ", "))")
            }
        }
    }

    // MARK: - Found It

    /// Confirmed on this screen, or earlier in the same search.
    private var isConfirmed: Bool {
        if didConfirmRetrieval { return true }
        guard let searchSession else { return false }
        return ledger.isConfirmed(insight.persistentModelID, in: searchSession)
    }

    @ViewBuilder
    private var foundItSection: some View {
        if isConfirmed {
            FoundAgainBadge(animate: didConfirmRetrieval)
                .transition(.opacity)
        } else {
            VStack(spacing: 10) {
                Button(action: confirmRetrieval) {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Grimoire.accentMagic)
                        Label("Found It", systemImage: "checkmark.circle")
                        Image(systemName: "sparkle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Grimoire.accentMagic)
                    }
                }
                .buttonStyle(GrimoirePrimaryButton())
                .accessibilityLabel("Found It")
                .accessibilityHint("Confirm this is the insight you were looking for")

                Text("Is this the one you were looking for?")
                    .font(.grimoire(.footnote))
                    .foregroundStyle(Grimoire.textSecondary)
            }
            .padding(.top, 4)
        }
    }

    /// The only place `retrievalCount` rises. Guarded twice: the ledger stops a
    /// second count for the same passage within one search, and the local flag
    /// stops a double tap before the ledger has been written.
    private func confirmRetrieval() {
        guard let searchSession, !isConfirmed else { return }
        ledger.confirm(insight.persistentModelID, in: searchSession)
        withAnimation(.easeOut(duration: 0.25)) { didConfirmRetrieval = true }

        insight.retrievalCount += 1
        insight.updatedAt = .now
        try? context.save()

        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
    }

    // MARK: - Closing

    /// The acorn on its open book, closing the page the way the design does.
    private var closingIllustration: some View {
        ZStack {
            Circle()
                .fill(Grimoire.accentMagicSoft)
                .frame(width: 150, height: 150)
                .blur(radius: 30)
            Image("BookAcorn")
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 140)
                .gentleFloat(amplitude: 3, duration: 3.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .accessibilityHidden(true)
    }

    /// Exactly what a reader would paste into a message: the passage, then its
    /// source. No page reference — that is a note to themselves about a physical
    /// book, and it means nothing to whoever receives this.
    private var shareText: String {
        var out = "\u{201C}\(insight.selectedText)\u{201D}\n\n— \(insight.bookTitle)"
        if let author = insight.author,
           !author.trimmingCharacters(in: .whitespaces).isEmpty {
            out += ", \(author)"
        }
        if insight.isSample { out += "\n(Sample paraphrase, not a quotation.)" }
        return out
    }
}

// MARK: - Pieces

/// A leaf, an uppercase label and a hairline running to the edge.
private struct SectionHeader: View {
    let title: String
    /// A symbol in place of the leaf, for sections that are not about the reading.
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Grimoire.primary)
                } else {
                    Image("Leaf")
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(width: 18, height: 18)

            Text(title)
                .font(.grimoire(.caption1, .emphasized))
                .foregroundStyle(Grimoire.textSecondary)
                .textCase(.uppercase)
                .tracking(0.8)
                .lineLimit(1)
                .layoutPriority(1)

            Rectangle()
                .fill(Grimoire.border)
                .frame(height: 1)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
    }
}

private extension View {
    /// The detail screen's card: warm surface, hairline border, a lifting shadow,
    /// and optionally a faint leaf sprig tucked into the bottom corner.
    func detailCard(sprig: Bool) -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Grimoire.surface)
            .overlay(alignment: .bottomTrailing) {
                if sprig {
                    Image("Leaf")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 46)
                        .rotationEffect(.degrees(-24))
                        .opacity(0.16)
                        .offset(x: 6, y: 8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Grimoire.border, lineWidth: 1))
            .shadow(color: Grimoire.textPrimary.opacity(0.10), radius: 10, y: 5)
    }
}

/// Lays chips out left to right, wrapping onto a new line when the next one
/// would not fit. A grid would force every keyword into the same width.
private struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            widest = max(widest, x + size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// "Found again." — the small moment after a confirmation.
///
/// Inline rather than a success screen: the reader has just found what they
/// came for, and the kindest thing is to let them keep reading it.
private struct FoundAgainBadge: View {
    /// False when the badge is shown because this passage was already confirmed
    /// earlier in the same search: that is a fact to state, not a moment to
    /// celebrate a second time.
    let animate: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popped = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Image("Acorn")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                    .scaleEffect(popped ? 1 : 0.4)
                MagicSparkle(size: 10, delay: 0.1)
                    .offset(x: 18, y: -14)
                    .opacity(popped ? 1 : 0)
            }
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Found Again ✓")
                    .font(.grimoire(.subhead, .emphasized))
                    .foregroundStyle(Grimoire.primary)
                Text("Back where it belongs.")
                    .font(.grimoire(.caption1))
                    .foregroundStyle(Grimoire.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Grimoire.accentMagicSoft,
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
            .strokeBorder(Grimoire.accentMagic.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Found again. Back where it belongs.")
        .onAppear {
            guard animate, !reduceMotion else { popped = true; return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { popped = true }
        }
    }
}
