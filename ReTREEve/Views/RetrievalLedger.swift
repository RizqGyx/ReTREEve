import Foundation
import Observation
import SwiftData

@Observable
final class RetrievalLedger {
    private struct Key: Hashable {
        let session: UUID
        let insight: PersistentIdentifier
    }

    private var confirmed: Set<Key> = []

    func isConfirmed(_ insight: PersistentIdentifier, in session: UUID) -> Bool {
        confirmed.contains(Key(session: session, insight: insight))
    }

    func confirm(_ insight: PersistentIdentifier, in session: UUID) {
        confirmed.insert(Key(session: session, insight: insight))
    }
}
