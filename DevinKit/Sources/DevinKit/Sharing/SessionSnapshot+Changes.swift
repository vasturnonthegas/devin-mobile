import Foundation

public extension SessionSnapshot {
    /// A session whose bucket differs between two snapshots. `entry` is the newer state.
    struct Change: Hashable, Sendable, Identifiable {
        public let entry: Entry
        public let from: Session.Bucket

        public var id: String { entry.id }
        public var to: Session.Bucket { entry.bucket }

        /// The two transitions worth interrupting the user for: Devin stopped working because it
        /// needs input (`working → needsYou`), or a session reached `finished` from any other bucket.
        /// Everything else (sleeping, failing, resuming) is visible in the inbox but not pushed.
        public var isNotable: Bool {
            switch (from, to) {
            case (.working, .needsYou): true
            case (_, .finished): true
            default: false
            }
        }
    }

    /// Sessions present in both snapshots whose bucket moved, in this snapshot's order.
    /// Sessions that appear only here (created since `previous`) or only there (archived, deleted,
    /// fell off the first page) have no "from" state and are never reported, so a first launch —
    /// or a page of 50 new sessions — cannot fan out into a storm of notifications.
    func changes(since previous: SessionSnapshot) -> [Change] {
        let before = Dictionary(previous.entries.map { ($0.id, $0.bucket) }, uniquingKeysWith: { first, _ in first })
        return entries.compactMap { entry in
            guard let from = before[entry.id], from != entry.bucket else { return nil }
            return Change(entry: entry, from: from)
        }
    }

    func notableChanges(since previous: SessionSnapshot) -> [Change] {
        changes(since: previous).filter(\.isNotable)
    }
}
