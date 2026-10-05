//  InsightEditorView.swift
//  Book Details — the last step of capture — and the edit sheet.
//
//  ── THE PASSAGE CARD ───────────────────────────────────────────────────────
//
//  Arriving from a scan or a photo, the passage was already chosen on the page,
//  so it appears as a quote rather than a tall editor, and focus goes to the book
//  title. The card still carries an Edit button: this is the last place a word
//  the camera misread can be corrected before the passage becomes immutable.
//  That button replaced a whole review screen — see CaptureFlowView.
//
//  Typing manually, there is no earlier step and the passage field IS the job,
//  so it is simply a field.
//
//  ── RECENT BOOKS ───────────────────────────────────────────────────────────
//
//  Readers save several passages from the book they are in the middle of. While
//  the title field is focused, the books already in the grimoire are offered as
//  chips. One tap fills title and author, and it keeps "Atomic Habits" and
//  "atomic habits " from becoming two books in the library.
//
//  This view does NOT own its presentation: no NavigationStack, no dismiss()
//  of its own. It reports Save and Cancel upward and lets the caller decide
//  whether that means closing the capture flow or a sheet.

import SwiftUI
import SwiftData

struct InsightEditorView: View {
    enum Mode {
        case create
        case edit(ReadingInsight)
    }

    let mode: Mode
    /// Prefills the passage in `.create` mode. Capture passes the text the reader
    /// selected; the typed path passes nothing and the field starts empty.
    /// Ignored in `.edit` mode, where the passage is immutable.
    var initialPassage: String = ""
    /// Lines on the captured page that were read with low confidence. Only
    /// changes the wording of a hint; never blocks saving.
    var lowConfidenceCount: Int = 0
    /// Sheets need an explicit Cancel; a pushed screen already has a back button.
    var showsCancel: Bool = false
    var onDone: () -> Void = {}
    var onCancel: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Query(sort: \ReadingInsight.createdAt, order: .reverse)
    private var savedInsights: [ReadingInsight]

    @State private var passage = ""
    @State private var book = ""
    @State private var author = ""
    @State private var page = ""
    @State private var note = ""
    @State private var isCorrectingPassage = false
    @State private var confirmingDiscard = false
    /// `onAppear` can fire more than once for one presentation. Loading only on
    /// the first pass keeps a prefilled passage — or an in-progress edit — from
    /// being silently reset underneath the reader.
    @State private var didLoad = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case passage, book, author, page, note }

    private struct BookSuggestion: Hashable {
        let title: String
        let author: String?
    }

    private var isEditing: Bool { if case .edit = mode { true } else { false } }

    /// True when capture supplied the passage.
    private var arrivedFromCapture: Bool {
        !isEditing && !PassageAssembler.normalizeWhitespace(initialPassage).isEmpty
    }

    private var showsPassageField: Bool {
        !isEditing && (!arrivedFromCapture || isCorrectingPassage)
    }

    private var canSave: Bool {
        !passage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !book.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Drives the HIG requirement that a modal must not silently discard work.
    private var hasUnsavedChanges: Bool {
        switch mode {
        case .create:
            return !passage.isEmpty || !book.isEmpty || !author.isEmpty || !note.isEmpty
        case .edit(let insight):
            return book != insight.bookTitle
                || author != (insight.author ?? "")
                || page != (insight.pageReference ?? "")
                || note != (insight.personalContext ?? "")
        }
    }

    /// Books already in the grimoire, most recently used first, narrowed by
    /// whatever has been typed. An exact match is left out: it is already chosen.
    private var bookSuggestions: [BookSuggestion] {
        let typed = book.trimmingCharacters(in: .whitespaces).lowercased()
        var seen = Set<String>()
        var result: [BookSuggestion] = []
        for insight in savedInsights {
            let key = insight.bookTitle.trimmingCharacters(in: .whitespaces).lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            if !typed.isEmpty, !key.contains(typed) || key == typed { continue }
            result.append(BookSuggestion(title: insight.bookTitle, author: insight.author))
            if result.count == 6 { break }
        }
        return result
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    passageSection
                    sourceSection
                    noteSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                // Room for the Save Insight bar, which floats over the end of
                // the form, so the last field can always scroll clear of it.
                .padding(.bottom, isEditing ? 24 : Grimoire.buttonHeight + 44)
            }
            .scrollDismissesKeyboard(.interactively)

            // ── WHY THE KEYBOARD COVERS THE BUTTON ─────────────────────────
            //
            // As a bottom safe-area inset, Save Insight rode up on top of the
            // keyboard: a 54pt bar sitting over the fields the reader was
            // still filling in. It now stays pinned to the bottom of the
            // screen and the keyboard slides over it. The form itself still
            // avoids the keyboard, so the focused field stays visible; Done
            // or a downward swipe puts the keyboard away and the button is
            // there, where the design has it.
            if !isEditing {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    saveBar
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .magicalBackground(.subtle)
        .grimoireNavigationTitle(isEditing ? "Edit Details" : "Book Details")
        .interactiveDismissDisabled(hasUnsavedChanges)
        .toolbar {
            if showsCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasUnsavedChanges { confirmingDiscard = true } else { onCancel() }
                    }
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }
                    .fontWeight(.semibold)
                    .accessibilityHint("Hides the keyboard")
            }
            if isEditing {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
        .confirmationDialog("Discard your changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { onCancel() }
            Button("Keep Editing", role: .cancel) {}
        }
        .onAppear(perform: load)
    }

    /// Create mode ends in a commit, so the commit gets a real button rather
    /// than a word in the navigation bar. The edit sheet keeps the toolbar Save,
    /// which is what a short sheet is expected to have.
    private var saveBar: some View {
        Button("Save Insight", action: save)
            .buttonStyle(GrimoirePrimaryButton())
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.55)
            .accessibilityHint(canSave
                               ? "Saves this passage to your grimoire"
                               : "Add the passage and the book title first")
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 8)
            .background(
                // A fade rather than a material bar, so the illustration stays
                // visible behind the button while scrolled text still dissolves
                // before it reaches it.
                LinearGradient(colors: [Grimoire.background.opacity(0),
                                        Grimoire.background.opacity(0.92)],
                               startPoint: .top,
                               endPoint: UnitPoint(x: 0.5, y: 0.4))
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(false)
            )
    }

    // MARK: - Sections

    private var passageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                sectionLabel("Passage")
                Spacer()
                if arrivedFromCapture {
                    Button(isCorrectingPassage ? "Done" : "Edit", action: togglePassageCorrection)
                        .font(.grimoire(.subhead, .emphasized))
                        .foregroundStyle(Grimoire.primary)
                        .frame(minWidth: 44, minHeight: 32)
                        .accessibilityHint(isCorrectingPassage
                                           ? "Finishes correcting the passage"
                                           : "Correct any word the camera misread")
                }
            }

            HStack(alignment: .top, spacing: 10) {
                PassageQuoteMark(size: 20)
                    .padding(.top, 3)

                if showsPassageField {
                    TextField("Type or paste the passage", text: $passage, axis: .vertical)
                        .font(.grimoire(.body))
                        .foregroundStyle(Grimoire.textPrimary)
                        .lineLimit(3...12)
                        .focused($focus, equals: .passage)
                        .accessibilityLabel("Passage")
                } else {
                    Text(passage)
                        .font(.grimoire(.body))
                        .foregroundStyle(Grimoire.textPrimary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Passage. \(passage)")
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Grimoire.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(focus == .passage ? Grimoire.primary.opacity(0.55) : Grimoire.border,
                              lineWidth: 1))
            .shadow(color: Grimoire.textPrimary.opacity(0.08), radius: 8, y: 4)

            passageFooter
        }
    }

    @ViewBuilder
    private var passageFooter: some View {
        if isEditing {
            footnote("The passage stays exactly as you captured it.")
        } else if arrivedFromCapture {
            if isCorrectingPassage {
                footnote("Fix misread words only — the passage can't be changed after saving.")
            } else if lowConfidenceCount > 0 {
                Label {
                    Text("Some words were hard to read. Tap Edit to check them.")
                } icon: {
                    Image(systemName: "eye.trianglebadge.exclamationmark")
                        .foregroundStyle(Grimoire.accentMagic)
                }
                .font(.grimoire(.footnote))
                .foregroundStyle(Grimoire.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                footnote("Misread a word? Tap Edit to fix it.")
            }
        } else {
            footnote("Keep the part that actually mattered.")
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Source")

            VStack(spacing: 0) {
                field("Book title", text: $book, field: .book, next: .author)
                    .accessibilityHint("Required")
                divider
                field("Author (optional)", text: $author, field: .author, next: .page)
                divider
                field("Page (optional)", text: $page, field: .page, next: .note)
                    .keyboardType(.numbersAndPunctuation)
            }
            .background(Grimoire.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Grimoire.border, lineWidth: 1))

            if !isEditing, focus == .book, !bookSuggestions.isEmpty {
                recentBooks
            }
        }
    }

    private var recentBooks: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your books")
                .font(.grimoire(.caption1))
                .foregroundStyle(Grimoire.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(bookSuggestions, id: \.self) { suggestion in
                        Button {
                            book = suggestion.title
                            if author.trimmingCharacters(in: .whitespaces).isEmpty {
                                author = suggestion.author ?? ""
                            }
                            focus = .page
                        } label: {
                            Label(suggestion.title, systemImage: "book.closed")
                                .font(.grimoire(.subhead))
                                .foregroundStyle(Grimoire.primary)
                                .lineLimit(1)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 44)
                                .background(Grimoire.primarySoft, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Fills in this book")
                    }
                }
            }
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(isEditing ? "Why is it important?" : "Why did you save this?")

            TextField("Optional", text: $note, axis: .vertical)
                .font(.grimoire(.body))
                .foregroundStyle(Grimoire.textPrimary)
                .lineLimit(4...8)
                .focused($focus, equals: .note)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Grimoire.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(focus == .note ? Grimoire.primary.opacity(0.55) : Grimoire.border,
                                  lineWidth: 1))

            footnote("A sentence here often becomes the thing you remember months later.")
        }
    }

    // MARK: - Pieces

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.grimoire(.caption1, .emphasized))
            .foregroundStyle(Grimoire.textSecondary)
            .textCase(.uppercase)
            .tracking(0.6)
            .accessibilityAddTraits(.isHeader)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.grimoire(.footnote))
            .foregroundStyle(Grimoire.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var divider: some View {
        Rectangle()
            .fill(Grimoire.border)
            .frame(height: 1)
            .padding(.leading, 14)
    }

    private func field(_ placeholder: String,
                       text: Binding<String>,
                       field: Field,
                       next: Field) -> some View {
        TextField(placeholder, text: text)
            .font(.grimoire(.body))
            .foregroundStyle(Grimoire.textPrimary)
            .focused($focus, equals: field)
            .submitLabel(.next)
            .onSubmit { focus = next }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
    }

    // MARK: - Actions

    private func togglePassageCorrection() {
        if isCorrectingPassage {
            passage = PassageAssembler.normalizeWhitespace(passage)
            isCorrectingPassage = false
            focus = nil
        } else {
            isCorrectingPassage = true
            focus = .passage
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true

        switch mode {
        case .edit(let insight):
            passage = insight.selectedText
            book = insight.bookTitle
            author = insight.author ?? ""
            page = insight.pageReference ?? ""
            note = insight.personalContext ?? ""
        case .create:
            let prefill = PassageAssembler.normalizeWhitespace(initialPassage)
            if prefill.isEmpty {
                focus = .passage
            } else {
                // Arrived from capture: the passage is settled, so send the
                // reader straight to the field that still needs them.
                passage = prefill
                focus = .book
            }
        }
    }

    private func save() {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPage = page.trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case .create:
            let insight = ReadingInsight(
                selectedText: PassageAssembler.normalizeWhitespace(passage),
                bookTitle: book.trimmingCharacters(in: .whitespacesAndNewlines),
                author: trimmedAuthor.isEmpty ? nil : trimmedAuthor,
                pageReference: trimmedPage.isEmpty ? nil : trimmedPage,
                personalContext: trimmedNote.isEmpty ? nil : trimmedNote)
            context.insert(insight)
            // The save commits now; widening the search surface is slow enough
            // to notice, so it backfills afterwards. Until it lands the insight
            // is still findable by its own words.
            expandInBackground(insight)
        case .edit(let insight):
            // selectedText is deliberately untouched.
            insight.bookTitle = book.trimmingCharacters(in: .whitespacesAndNewlines)
            insight.author = trimmedAuthor.isEmpty ? nil : trimmedAuthor
            insight.pageReference = trimmedPage.isEmpty ? nil : trimmedPage
            insight.personalContext = trimmedNote.isEmpty ? nil : trimmedNote
            insight.updatedAt = .now
        }

        try? context.save()
        onDone()
    }

    private func expandInBackground(_ insight: ReadingInsight) {
        let passage = insight.selectedText
        let title = insight.bookTitle
        Task {
            let phrases = await SemanticExpansion.expandDocument(passage: passage, bookTitle: title)
            guard !phrases.isEmpty else { return }
            insight.semanticDescription = phrases.joined(separator: ", ")
            try? context.save()
        }
    }
}
