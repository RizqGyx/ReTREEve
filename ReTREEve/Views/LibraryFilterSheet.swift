//  LibraryFilterSheet.swift
//  Filter & Sort, as a bottom sheet.
//
//  ── ONLY WHAT THE DATA CAN ANSWER ──────────────────────────────────────────
//
//  Every control here maps to a field that exists on `ReadingInsight`: the date
//  it was saved, the book title, and whether a page reference was written down.
//  There is no tag, favourite, topic or category filter because there is no tag,
//  favourite, topic or category — a filter for a field that does not exist is a
//  control that can only ever return everything.
//
//  ── WHY THE SHEET EDITS A DRAFT ────────────────────────────────────────────
//
//  The sheet works on a copy and the library only adopts it on Apply. Editing
//  the live options would re-sort the list behind the sheet on every tap, and
//  Reset would have no meaning — there would be nothing to discard by swiping
//  the sheet away.

import SwiftUI

/// How the library is currently showing itself. A value type so the sheet can
/// be handed a draft to edit and the screen can adopt or discard it whole.
struct LibraryOptions: Equatable {
    enum Sort: String, CaseIterable, Identifiable {
        case newest = "Newest First"
        case oldest = "Oldest First"
        case bookAscending = "Book Title A–Z"
        case bookDescending = "Book Title Z–A"
        var id: String { rawValue }
    }

    enum PageFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case withPage = "With Page"
        case withoutPage = "Without Page"
        var id: String { rawValue }
    }

    enum Display: String, CaseIterable, Identifiable {
        case allInsights = "All Insights"
        case byBook = "Group by Book"
        var id: String { rawValue }
    }

    var sort: Sort = .newest
    var pageFilter: PageFilter = .all
    var display: Display = .allInsights

    var groupsByBook: Bool { display == .byBook }
    var isDefault: Bool { self == LibraryOptions() }

    /// Spoken by VoiceOver on the toolbar button, so the reader knows what is
    /// applied without opening the sheet.
    var summary: String {
        var parts = [sort.rawValue]
        if pageFilter != .all { parts.append(pageFilter.rawValue) }
        if display != .allInsights { parts.append(display.rawValue) }
        return parts.joined(separator: ", ")
    }

    /// Search, then filter, then sort — in that order, because sorting a set
    /// that is about to shrink is wasted work.
    func apply(to insights: [ReadingInsight], matching query: String) -> [ReadingInsight] {
        var result = insights

        if !query.isEmpty {
            let needle = query.lowercased()
            // Passage, book and author: the three things visible on a card. The
            // generated search vocabulary is deliberately excluded — a hit on a
            // word that appears nowhere on screen reads as a bug.
            result = result.filter { insight in
                [insight.selectedText, insight.bookTitle, insight.author ?? ""]
                    .contains { $0.lowercased().contains(needle) }
            }
        }

        switch pageFilter {
        case .all: break
        case .withPage: result = result.filter { $0.hasPageReference }
        case .withoutPage: result = result.filter { !$0.hasPageReference }
        }

        switch sort {
        case .newest:
            result.sort { $0.createdAt > $1.createdAt }
        case .oldest:
            result.sort { $0.createdAt < $1.createdAt }
        case .bookAscending:
            result.sort { $0.bookTitle.localizedCaseInsensitiveCompare($1.bookTitle) == .orderedAscending }
        case .bookDescending:
            result.sort { $0.bookTitle.localizedCaseInsensitiveCompare($1.bookTitle) == .orderedDescending }
        }
        return result
    }
}

struct LibraryFilterSheet: View {
    @Binding var options: LibraryOptions
    var onApply: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Display") {
                        segmented(LibraryOptions.Display.allCases,
                                  selection: $options.display) { $0.rawValue }
                    }

                    section("Sort by") {
                        VStack(spacing: 0) {
                            ForEach(Array(LibraryOptions.Sort.allCases.enumerated()), id: \.element.id) { index, sort in
                                sortRow(sort)
                                if index < LibraryOptions.Sort.allCases.count - 1 {
                                    Divider().overlay(Grimoire.border).padding(.leading, 34)
                                }
                            }
                        }
                        .grimoireCard(padding: 0, radius: 14)
                    }

                    section("Has Page Number") {
                        segmented(LibraryOptions.PageFilter.allCases,
                                  selection: $options.pageFilter) { $0.rawValue }
                    }
                }
                .padding(20)
            }
            .background(Grimoire.surface.ignoresSafeArea())
            .navigationTitle("Filter & Sort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button("Reset") { options = LibraryOptions() }
                        .font(.grimoire(.headline))
                        .foregroundStyle(Grimoire.textSecondary)
                        .frame(minWidth: 88, minHeight: Grimoire.buttonHeight)
                        .accessibilityHint("Returns every option to its default")

                    Button("Apply Filter") {
                        onApply()
                        dismiss()
                    }
                    .buttonStyle(GrimoirePrimaryButton())
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .background(Grimoire.surface)
            }
        }
        // Medium first so the list stays visible behind it on a small phone;
        // large is there for accessibility text sizes, where the rows grow.
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.grimoire(.subhead, .emphasized))
                .foregroundStyle(Grimoire.textPrimary)
            content()
        }
    }

    private func sortRow(_ sort: LibraryOptions.Sort) -> some View {
        Button {
            options.sort = sort
        } label: {
            HStack(spacing: 10) {
                Image(systemName: options.sort == sort ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(options.sort == sort ? Grimoire.primary : Grimoire.textDisabled)
                Text(sort.rawValue)
                    .font(.grimoire(.subhead))
                    .foregroundStyle(Grimoire.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(options.sort == sort ? [.isButton, .isSelected] : .isButton)
    }

    /// A hand-built segmented control rather than `Picker(.segmented)`, which
    /// cannot be tinted and reads as system grey against parchment.
    private func segmented<T: Hashable & Identifiable>(_ cases: [T],
                                                       selection: Binding<T>,
                                                       label: @escaping (T) -> String) -> some View {
        HStack(spacing: 6) {
            ForEach(cases) { option in
                let isSelected = selection.wrappedValue == option
                Button {
                    selection.wrappedValue = option
                } label: {
                    Text(label(option))
                        .font(.grimoire(.subhead))
                        .foregroundStyle(isSelected ? Grimoire.surface : Grimoire.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(isSelected ? Grimoire.primary : Grimoire.secondarySoft,
                                    in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}
