import ActivityKit
import Foundation
import Observation
import DevinKit

/// The one session pinned to the lock screen (see `SessionActivityAttributes`). ActivityKit is the
/// source of truth for *which* session: activities outlive the process, so nothing is stored in
/// defaults and `watchedSessionID` merely mirrors `Activity.activities` for SwiftUI.
///
/// Content flows in from wherever a fresh `Session` shows up — the detail view's poll while the user
/// is looking at it, `BackgroundRefresh` (one `GET …/sessions/{id}` per run) otherwise. A session
/// that `isFinal` ends the activity with that state left on the lock screen; a user-initiated stop
/// (or terminate / archive from the app) removes it immediately.
///
/// `Activity` is not `Sendable`, so every ActivityKit call happens in a `nonisolated` helper keyed by
/// session ID; the main-actor class only holds the mirror for SwiftUI.
@Observable
@MainActor
final class SessionLiveActivity {
    static let shared = SessionLiveActivity()

    /// Foreground polls arrive every 5 s; an activity whose visible fields didn't change is re-stamped
    /// no more often than this so "Updated N min ago" stays honest without burning update budget.
    nonisolated static let heartbeat: TimeInterval = 60

    private(set) var watchedSessionID: String?

    private init() {
        watchedSessionID = Self.liveSessionIDs.first
    }

    /// False when the user disabled Live Activities for the app in Settings, or the device can't show them.
    var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func isWatching(_ sessionID: String) -> Bool { watchedSessionID == sessionID }

    /// Pins `session`, replacing whatever was pinned before — one activity at a time.
    func start(_ session: Session) async throws {
        try await Self.request(session)
        sync()
    }

    /// User-initiated: the activity disappears right away. No-op when `sessionID` isn't pinned.
    func stop(_ sessionID: String) async {
        await Self.end(sessionID: sessionID, content: nil, dismissalPolicy: .immediate)
        sync()
    }

    /// Pushes `session` to its activity, if any. A final state ends the activity with that content
    /// (system default dismissal) so the lock screen shows how the session ended.
    func update(_ session: Session) async {
        guard Self.liveSessionIDs.contains(session.sessionID) else { return }
        await Self.push(session)
        sync()
    }

    /// One `GET …/sessions/{id}` per pinned session (at most one). A failed fetch leaves the activity
    /// alone; ActivityKit flags it stale once `staleDate` passes.
    func refresh(client: DevinClient, orgID: String) async {
        for id in Self.liveSessionIDs {
            guard let session = try? await client.session(org: orgID, id: id) else { continue }
            await update(session)
        }
    }

    private func sync() {
        watchedSessionID = Self.liveSessionIDs.first
    }

    // MARK: ActivityKit (nonisolated: `Activity` must not cross an actor boundary)

    /// Sessions with an activity still on the lock screen — `.stale` included, a refresh is what fixes it.
    nonisolated private static var liveSessionIDs: [String] {
        live.map(\.attributes.sessionID)
    }

    nonisolated private static var live: [Activity<SessionActivityAttributes>] {
        Activity<SessionActivityAttributes>.activities.filter { [.active, .stale].contains($0.activityState) }
    }

    nonisolated private static func request(_ session: Session) async throws {
        for activity in live where activity.attributes.sessionID != session.sessionID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        let content = content(for: session)
        if let existing = live.first(where: { $0.attributes.sessionID == session.sessionID }) {
            await existing.update(content)
        } else {
            _ = try Activity.request(attributes: SessionActivityAttributes(sessionID: session.sessionID), content: content)
        }
    }

    nonisolated private static func push(_ session: Session) async {
        let content = content(for: session)
        for activity in live where activity.attributes.sessionID == session.sessionID {
            if content.state.isFinal {
                await activity.end(content, dismissalPolicy: .default)
            } else if content.state.differsVisibly(from: activity.content.state)
                        || content.state.updatedAt.timeIntervalSince(activity.content.state.updatedAt) >= heartbeat {
                await activity.update(content)
            }
        }
    }

    nonisolated private static func end(sessionID: String, content: ActivityContent<SessionActivityAttributes.State>?, dismissalPolicy: ActivityUIDismissalPolicy) async {
        for activity in live where activity.attributes.sessionID == sessionID {
            await activity.end(content, dismissalPolicy: dismissalPolicy)
        }
    }

    nonisolated static func content(for session: Session) -> ActivityContent<SessionActivityAttributes.State> {
        let state = SessionActivityAttributes.State(session)
        return ActivityContent(state: state, staleDate: state.staleDate, relevanceScore: session.needsAttention ? 100 : 0)
    }
}
