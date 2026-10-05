import SwiftUI
import SwiftData

enum Route: Hashable {
    case library
    case search
    case matches(query: String)
    case book(title: String)
    case insight(ReadingInsight, searchSession: UUID?)
}

extension Route {
    static func saved(_ insight: ReadingInsight) -> Route {
        .insight(insight, searchSession: nil)
    }

    static func match(_ insight: ReadingInsight, session: UUID) -> Route {
        .insight(insight, searchSession: session)
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @State private var path = NavigationPath()
    @AppStorage(Onboarding.completedKey) private var hasCompletedOnboarding = false
    @State private var showingOnboarding = false
    @State private var ledger = RetrievalLedger()

    var body: some View {
        NavigationStack(path: $path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .library:
                        LibraryView()
                    case .search:
                        SearchView()
                    case .matches(let query):
                        PossibleMatchesView(query: query)
                    case .book(let title):
                        BookInsightsView(bookTitle: title)
                    case .insight(let insight, let session):
                        InsightDetailView(insight: insight, searchSession: session)
                    }
                }
        }
        .tint(Grimoire.primary)
        .environment(ledger)
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView { showingOnboarding = false }
        }
        .task {
            SampleLibrary.seedIfNeeded(context)
            // Once per install: absent on a fresh download, true forever after
            // the reader finishes it.
            showingOnboarding = !hasCompletedOnboarding

            // Detached so the model never delays the first screen. Insights
            // saved before the expansion prompt was fixed have no search
            // vocabulary at all; this gives it to them a few at a time.
            Task { await ExpansionBackfill.run(context: context) }
        }
    }

}
