import SwiftUI
import SwiftData

struct PossibleMatchesView: View {
    let query: String

    @Query private var insights: [ReadingInsight]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var matches: [InsightMatch] = []
    @State private var stage: Stage = .searching
    @State private var attempt = 0
    @State private var session = UUID()

    private enum Stage: Equatable { case searching, widening, done, failed }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TitleFlourish()
                    .frame(maxWidth: .infinity)
                    .padding(.top, -6)

                recallEcho

                switch stage {
                case .searching, .widening:
                    if matches.isEmpty {
                        lookingState
                    } else {
                        results
                    }
                case .done:
                    if matches.isEmpty { nothingClose } else { results }
                case .failed:
                    failedState
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .magicalBackground(.normal)
        .grimoireNavigationTitle("Possible Matches")
        .task(id: attempt) { await runSearch() }
    }

    private func runSearch() async {
        stage = .searching

        let found: [InsightMatch]
        do {
            let lexical = HybridRetrievalService(insights: insights, usesQueryExpansion: false)
            found = try await lexical.search(query)
        } catch {
            matches = []
            stage = .failed
            return
        }
        show(found)

        guard found.isEmpty else {
            stage = .done
            return
        }

        stage = .widening
        let widened = HybridRetrievalService(insights: insights)
        if let results = try? await widened.search(query) {
            show(results)
        }
        stage = .done
    }

    private func show(_ results: [InsightMatch]) {
        if reduceMotion {
            matches = results
        } else {
            withAnimation(.easeOut(duration: 0.3)) { matches = results }
        }
    }

    // MARK: - Pieces
    private var recallEcho: some View {
        HStack(spacing: 16) {
            Image("Leaf")
                .resizable()
                .scaledToFit()
                .padding(13)
                .frame(width: 56, height: 56)
                .background(Grimoire.surface, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("You remembered:")
                    .font(.grimoire(.subhead))
                    .foregroundStyle(Grimoire.textSecondary)
                Text("\u{201C}\(query)\u{201D}")
                    .font(.grimoire(.title2, .emphasized))
                    .foregroundStyle(Grimoire.textPrimary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.trailing, 36)

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Grimoire.primarySoft)
        .overlay(alignment: .bottomTrailing) {
            Image("Leaf")
                .resizable()
                .scaledToFit()
                .frame(width: 54)
                .rotationEffect(.degrees(-28))
                .opacity(0.22)
                .offset(x: 6, y: 10)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .topTrailing) {
            MagicSparkle(size: 13, delay: 0.2)
                .padding(.top, 18)
                .padding(.trailing, 58)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Grimoire.primary.opacity(0.15), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("You remembered: \(query)")
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Here are some passages that might match what you remember.")
                .font(.grimoire(.callout))
                .foregroundStyle(Grimoire.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)

            LazyVStack(spacing: 14) {
                ForEach(matches) { match in
                    NavigationLink(value: Route.match(match.insight, session: session)) {
                        MatchCard(match: match)
                    }
                    .buttonStyle(.plain)
                    .transition(reduceMotion ? .opacity
                                : .opacity.combined(with: .move(edge: .bottom)))
                }
            }

            TitleFlourish()
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
        }
    }

    private var lookingState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Grimoire.accentMagicSoft.opacity(0.7))
                    .frame(width: 150, height: 150)
                    .blur(radius: 24)
                Image("BookAcorn")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120)
                    .gentleFloat(amplitude: 4, duration: 2.6)
                MagicSparkle(size: 14, delay: 0.0).offset(x: 62, y: -48)
                MagicSparkle(size: 10, opacity: 0.8, delay: 0.5).offset(x: -64, y: -18)
                MagicSparkle(size: 8, opacity: 0.7, delay: 1.0).offset(x: 50, y: 46)
            }
            .accessibilityHidden(true)

            Text("Looking through your grimoire…")
                .font(.grimoire(.headline))
                .foregroundStyle(Grimoire.textPrimary)

            Text(stage == .widening
                 ? "Finding similar meanings…"
                 : "Searching your saved passages…")
                .font(.grimoire(.subhead))
                .foregroundStyle(Grimoire.textSecondary)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Looking through your grimoire")
    }

    private var nothingClose: some View {
        VStack(spacing: 14) {
            Image("Squirrel")
                .resizable()
                .scaledToFit()
                .frame(width: 110)
                .accessibilityHidden(true)

            Text("Nothing close yet.")
                .font(.grimoire(.title3, .emphasized))
                .foregroundStyle(Grimoire.textPrimary)

            Text("Try describing the idea in another way, or use a few different words.")
                .font(.grimoire(.subhead))
                .foregroundStyle(Grimoire.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)

            VStack(spacing: 10) {
                Button("Try Again") { dismiss() }
                    .buttonStyle(GrimoirePrimaryButton())
                    .accessibilityHint("Goes back so you can describe it differently")

                NavigationLink(value: Route.library) {
                    Text("View Library")
                }
                .buttonStyle(GrimoireSecondaryButton())
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var failedState: some View {
        VStack(spacing: 14) {
            Image("Squirrel")
                .resizable()
                .scaledToFit()
                .frame(width: 96)
                .accessibilityHidden(true)

            Text("Something went wrong.")
                .font(.grimoire(.title3, .emphasized))
                .foregroundStyle(Grimoire.textPrimary)

            Text("We couldn't search your grimoire right now.")
                .font(.grimoire(.subhead))
                .foregroundStyle(Grimoire.textSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                Button("Try Again") { attempt += 1 }
                    .buttonStyle(GrimoirePrimaryButton())
                Button("Back") { dismiss() }
                    .buttonStyle(GrimoireSecondaryButton())
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - Result card
private struct MatchCard: View {
    let match: InsightMatch

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            BookInitialsIcon(title: match.insight.bookTitle, size: 62)

            VStack(alignment: .leading, spacing: 6) {
                Text("\u{201C}\(match.insight.preview(limit: 160))\u{201D}")
                    .font(.grimoire(.body))
                    .foregroundStyle(Grimoire.textPrimary)
                    .lineSpacing(2)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(match.insight.bookTitle)
                            .font(.grimoire(.headline))
                            .foregroundStyle(Grimoire.primary)
                            .lineLimit(1)
                        if match.insight.isSample { SampleTag() }
                    }
                    Text(match.insight.displayAuthor)
                        .font(.grimoire(.subhead))
                        .foregroundStyle(Grimoire.textSecondary)
                        .lineLimit(1)
                }

                ProvenanceChips(chips: MatchProvenance.chips(for: match))
                    .padding(.top, 4)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Grimoire.primary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Grimoire.surface,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Grimoire.border, lineWidth: 1))
        .shadow(color: Grimoire.textPrimary.opacity(0.10), radius: 10, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Opens this insight")
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityDescription: String {
        [match.insight.bookTitle,
         match.insight.preview(limit: 160),
         match.insight.displayAuthor,
         MatchProvenance.strengthText(for: match.strength),
         MatchProvenance.sentence(for: match)]
            .joined(separator: ". ")
    }
}

// MARK: - Provenance
enum MatchProvenance {
    enum Kind { case closest, possible, faint, yourWords, relatedTopic, meaning }

    struct Chip: Identifiable {
        let kind: Kind
        let text: String
        var id: String { text }
    }

    static func strengthText(for strength: InsightMatch.Strength) -> String {
        switch strength {
        case .closest:  "Close to your memory"
        case .possible: "Possible match"
        case .faint:    "Loosely related"
        }
    }

    static func chips(for match: InsightMatch) -> [Chip] {
        let strengthKind: Kind = switch match.strength {
        case .closest:  .closest
        case .possible: .possible
        case .faint:    .faint
        }
        var chips = [Chip(kind: strengthKind, text: strengthText(for: match.strength))]

        let direct = match.yourWordsInText
        let indexed = match.yourWordsInIndex

        if !direct.isEmpty {
            chips.append(Chip(kind: .yourWords,
                              text: "Matched on: \(direct.prefix(2).joined(separator: ", "))"))
        } else if !indexed.isEmpty {
            chips.append(Chip(kind: .relatedTopic,
                              text: "Related topic: \(indexed.prefix(2).joined(separator: ", "))"))
        } else {
            chips.append(Chip(kind: .meaning, text: "Matched on meaning"))
        }
        return chips
    }

    static func sentence(for match: InsightMatch) -> String {
        let direct = match.yourWordsInText
        let indexed = match.yourWordsInIndex
        let widened = match.widenedTerms

        if !direct.isEmpty {
            let place = placeName(match.visibleSources)
            let words = quoted(direct)
            var sentence = direct.count == 1
                ? "\(words) appears in \(place)."
                : "\(words) appear in \(place)."
            if !indexed.isEmpty {
                sentence += " \(quoted(indexed)) matched how it's filed."
            }
            return sentence
        }

        if !indexed.isEmpty {
            let words = quoted(indexed)
            return indexed.count == 1
                ? "\(words) isn't in the passage — it's one of the related phrases this insight is filed under."
                : "\(words) aren't in the passage — they're related phrases this insight is filed under."
        }

        if !widened.isEmpty {
            return "None of your words appear here. It matched on meaning, through \(quoted(Array(widened.prefix(3))))."
        }

        return "Matched on meaning."
    }

    private static func placeName(_ sources: Set<MatchEvidence.Source>) -> String {
        if sources.contains(.passage) { return "this passage" }
        if sources.contains(.note) { return "your note" }
        if sources.contains(.bookTitle) { return "the book title" }
        if sources.contains(.author) { return "the author's name" }
        return "this insight"
    }

    private static func quoted(_ terms: [String]) -> String {
        terms.prefix(3)
            .map { "\u{201C}\($0)\u{201D}" }
            .formatted(.list(type: .and, width: .narrow))
    }
}

private struct ProvenanceChips: View {
    let chips: [MatchProvenance.Chip]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { chipViews }
            VStack(alignment: .leading, spacing: 6) { chipViews }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var chipViews: some View {
        ForEach(chips) { chip in
            HStack(spacing: 5) {
                icon(for: chip.kind)
                Text(chip.text)
                    .lineLimit(1)
            }
            .font(.grimoire(.caption1))
            .foregroundStyle(Grimoire.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(background(for: chip.kind), in: Capsule())
        }
    }

    @ViewBuilder
    private func icon(for kind: MatchProvenance.Kind) -> some View {
        switch kind {
        case .closest:
            Image(systemName: "star.fill")
                .font(.system(size: 11))
                .foregroundStyle(Grimoire.accentMagic)
        case .possible, .yourWords:
            Image("Leaf")
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)
        case .relatedTopic:
            Image(systemName: "book.closed.fill")
                .font(.system(size: 11))
                .foregroundStyle(Grimoire.primary)
        case .faint, .meaning:
            SparkleShape()
                .fill(Grimoire.accentMagic)
                .frame(width: 12, height: 12)
        }
    }

    private func background(for kind: MatchProvenance.Kind) -> Color {
        switch kind {
        case .closest, .possible:     Grimoire.primarySoft
        case .yourWords, .relatedTopic: Grimoire.secondarySoft
        case .faint, .meaning:        Grimoire.accentMagicSoft
        }
    }
}
