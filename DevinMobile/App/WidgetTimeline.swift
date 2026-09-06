import DevinKit
import WidgetKit

/// The app owns the widget's data. It republishes `SessionSnapshot` after every unfiltered refresh
/// and removes it at sign-out; the widget (`WidgetContent.resolve`) treats a present snapshot as
/// proof of a signed-in user. Timelines are reloaded when the visible rows change or the widget's
/// "Updated" time is older than `staleAfter`, not on every 10 s poll — WidgetKit budgets reloads.
enum WidgetTimeline {
    static let staleAfter: TimeInterval = 5 * 60

    static func publish(_ snapshot: SessionSnapshot) {
        let previous = SessionSnapshot.load()
        try? snapshot.save()
        let stale = previous.map { snapshot.capturedAt.timeIntervalSince($0.capturedAt) >= staleAfter } ?? true
        if stale || previous?.entries != snapshot.entries {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    static func clear() {
        SessionSnapshot.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
