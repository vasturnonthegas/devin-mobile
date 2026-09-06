import SwiftUI
import DevinKit

/// One haptic per refresh in which a session already on screen moved bucket. The diff is
/// `SessionSnapshot.changes(since:)`, so sessions that only appear or disappear (first load,
/// archive, a new page) never fire. When several sessions move at once the strongest transition
/// wins — `.error` for `→ failed`, `.warning` for `→ needsYou`, `.success` for `→ finished`, a light
/// impact for everything else — so a 10 s poll is at most one tap.
struct BucketChangeHaptics: ViewModifier {
    let sessions: [Session]

    @State private var pulse: Pulse?

    /// The counter makes two consecutive changes into the same bucket distinct trigger values.
    private struct Pulse: Equatable {
        let bucket: Session.Bucket
        let count: Int
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: sessions) { old, new in
                let changes = SessionSnapshot(sessions: new).changes(since: SessionSnapshot(sessions: old))
                guard let bucket = Self.strongest(changes.map(\.to)) else { return }
                pulse = Pulse(bucket: bucket, count: (pulse?.count ?? 0) + 1)
            }
            .sensoryFeedback(trigger: pulse) { _, new in new.map { Self.feedback(for: $0.bucket) } }
    }

    static func strongest(_ buckets: [Session.Bucket]) -> Session.Bucket? {
        buckets.max { rank($0) < rank($1) }
    }

    private static func rank(_ bucket: Session.Bucket) -> Int {
        switch bucket {
        case .failed: 3
        case .needsYou: 2
        case .finished: 1
        case .working, .sleeping: 0
        }
    }

    static func feedback(for bucket: Session.Bucket) -> SensoryFeedback {
        switch bucket {
        case .failed: .error
        case .needsYou: .warning
        case .finished: .success
        case .working, .sleeping: .impact(weight: .light)
        }
    }
}

extension View {
    /// Plays a haptic when any of `sessions` changes bucket between two evaluations.
    /// Pass the list the user is looking at (scoped, unfiltered by search) so other people's
    /// sessions don't buzz the phone in the Mine scope.
    func bucketChangeHaptics(for sessions: [Session]) -> some View {
        modifier(BucketChangeHaptics(sessions: sessions))
    }
}
