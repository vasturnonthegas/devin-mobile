import SwiftUI
import DevinKit

/// "Watch on Lock Screen" / "Stop watching" for the session detail `⋯` menu. Hidden for sessions
/// that are already final (nothing left to watch) and when Live Activities are off in Settings.
struct LiveActivityMenuItems: View {
    let session: Session
    let model: SessionDetailModel
    private let liveActivity = SessionLiveActivity.shared

    var body: some View {
        if liveActivity.isAvailable, !session.isFinal {
            if liveActivity.isWatching(session.sessionID) {
                Button("Stop watching on Lock Screen", systemImage: "eye.slash") {
                    Task { await liveActivity.stop(session.sessionID) }
                }
            } else {
                Button("Watch on Lock Screen", systemImage: "eye") {
                    Task {
                        do {
                            try await liveActivity.start(session)
                        } catch {
                            model.error = error.localizedDescription
                        }
                    }
                }
            }
            Divider()
        }
    }
}

/// Small "On Lock Screen" chip next to the status badge while this session is the pinned one.
struct LiveActivityBadge: View {
    let sessionID: String
    private let liveActivity = SessionLiveActivity.shared

    var body: some View {
        if liveActivity.isWatching(sessionID) {
            Label("On Lock Screen", systemImage: "eye")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .accessibilityLabel("Shown on the Lock Screen as a Live Activity")
        }
    }
}

extension View {
    /// Forwards every refreshed `Session` to its Live Activity, if one is pinned. The detail view
    /// polls every 5 s while the user is looking, so this is what keeps the lock screen current in
    /// the foreground; `BackgroundRefresh` covers the rest.
    func syncsLiveActivity(with session: Session?) -> some View {
        onChange(of: session, initial: true) { _, session in
            guard let session else { return }
            Task { await SessionLiveActivity.shared.update(session) }
        }
    }
}
