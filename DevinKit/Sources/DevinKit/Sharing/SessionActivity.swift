import Foundation

/// The one session pinned to the lock screen as a Live Activity. `Attributes` are fixed for the
/// activity's lifetime (the session ID); `State` is what every refresh — the detail view's poll,
/// the inbox poll or a `BGAppRefreshTask` — pushes to it. Like `SessionSnapshot`, it carries only
/// what a glanceable surface needs and never the token or the transcript.
///
/// The ActivityKit conformance lives in `SessionActivity+ActivityKit.swift` (iOS only) so this
/// file — and its tests — build on macOS and Linux.
public struct SessionActivityAttributes: Codable, Hashable, Sendable {
    public struct State: Codable, Hashable, Sendable {
        public let title: String
        public let bucket: Session.Bucket
        public let statusSummary: String
        public let acusConsumed: Double
        /// When this state was fetched — shown as "Updated 3 min ago", so a stale activity is
        /// obviously stale rather than silently wrong.
        public let updatedAt: Date
        /// `finished`, or the VM is gone (`exit`, `error`). The activity ends with this as its final
        /// content; nothing later can change a session in these states.
        public let isFinal: Bool

        /// When the system should flag the activity as stale: one missed background refresh (~15 min)
        /// plus slack. A final state never goes stale.
        public var staleDate: Date? {
            isFinal ? nil : updatedAt.addingTimeInterval(SessionActivityAttributes.staleAfter)
        }

        /// True when the lock screen would render differently — everything but `updatedAt`, so a poll
        /// that found nothing new doesn't have to push an update.
        public func differsVisibly(from other: State) -> Bool {
            title != other.title || bucket != other.bucket || statusSummary != other.statusSummary
                || acusConsumed != other.acusConsumed || isFinal != other.isFinal
        }

        public init(_ session: Session, updatedAt: Date = .now) {
            title = session.displayTitle
            bucket = session.bucket
            statusSummary = session.statusSummary
            acusConsumed = session.acusConsumed
            self.updatedAt = updatedAt
            isFinal = session.isFinal
        }
    }

    public static let staleAfter: TimeInterval = 20 * 60

    public let sessionID: String

    public init(sessionID: String) {
        self.sessionID = sessionID
    }

    public var deepLink: DeepLink { .session(id: sessionID) }
}

public extension Session {
    /// True once the session can no longer make progress on its own: it finished, or its VM was
    /// destroyed (terminated or failed). A `suspended` session is *not* final — a message wakes it.
    var isFinal: Bool {
        switch status {
        case .exit, .error: true
        case .running, .resuming, .claimed, .new, .suspended: statusDetail == .finished
        }
    }
}
