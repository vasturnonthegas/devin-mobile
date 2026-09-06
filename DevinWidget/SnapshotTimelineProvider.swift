import DevinKit
import WidgetKit

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let content: WidgetContent
}

/// Reads the shared Keychain + `SessionSnapshot` (see `WidgetContent.resolve`). One entry per
/// timeline: the data only changes when the app republishes, and the app reloads the widget then.
/// The periodic refresh only exists so a stale snapshot is eventually re-read (e.g. after the app was
/// killed mid-session) and `capturedAt` is re-evaluated.
struct SnapshotTimelineProvider: TimelineProvider {
    static let refreshInterval: TimeInterval = 15 * 60

    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, content: .sessions(.sample))
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, content: context.isPreview ? .sessions(.sample) : Self.currentContent()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, content: Self.currentContent())
        completion(Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(Self.refreshInterval))))
    }

    static func currentContent() -> WidgetContent {
        WidgetContent.resolve(credentials: AppGroup.credentialStore)
    }
}

extension SessionSnapshot {
    /// Shown in the widget gallery and as the redacted placeholder.
    static let sample: SessionSnapshot = {
        let now = Date.now
        func session(_ id: String, _ title: String, _ status: SessionStatus, _ detail: SessionStatusDetail?, minutesAgo: Double) -> Session {
            Session(sessionID: id, orgID: "org-sample", status: status, statusDetail: detail, title: title,
                    url: URL(string: "https://app.devin.ai/sessions/\(id)")!,
                    createdAt: now.addingTimeInterval(-3_600), updatedAt: now.addingTimeInterval(-minutesAgo * 60))
        }
        return SessionSnapshot(sessions: [
            session("sample-1", "Fix flaky CI on main", .running, .waitingForUser, minutesAgo: 4),
            session("sample-2", "Add dark mode toggle", .running, .waitingForApproval, minutesAgo: 12),
            session("sample-3", "Migrate to Swift Testing", .running, .working, minutesAgo: 1),
            session("sample-4", "Bump dependencies", .exit, .finished, minutesAgo: 40),
        ], capturedAt: now)
    }()
}
