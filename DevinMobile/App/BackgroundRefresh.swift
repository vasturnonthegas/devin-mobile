import BackgroundTasks
import Foundation
import DevinKit

/// The ~15-minute `BGAppRefreshTask` behind local notifications. iOS decides when (and whether)
/// it actually runs; the app re-arms it every time it goes to the background and at the start of
/// every run, and `DevinMobileApp` binds it to the scene with `.backgroundTask(.appRefresh(...))`.
///
/// One run is one poll of page 1 of the unfiltered inbox, diffed against the `SessionSnapshot`
/// the foreground app (or the previous run) left in the App Group. The snapshot is written only
/// after the diff, so a run that fails to fetch leaves the baseline alone and the next one
/// still sees the transition.
enum BackgroundRefresh {
    /// Must match `BGTaskSchedulerPermittedIdentifiers` in `project.yml`.
    static let taskIdentifier = "ai.devin.mobile.refresh"
    static let interval: TimeInterval = 15 * 60

    /// Replaces any pending request. Fails silently where BGTaskScheduler is unavailable (Simulator).
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = .now.addingTimeInterval(interval)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func run(credentials store: any CredentialStore) async {
        schedule()
        guard let credentials = try? store.load() else { return }
        let client = DevinClient(token: credentials.token)
        guard let page = try? await client.sessions(org: credentials.orgID, query: SessionQuery(first: 50)) else { return }
        let current = SessionSnapshot(sessions: page.items)
        if let previous = SessionSnapshot.load() {
            await SessionNotifier.post(current.notableChanges(since: previous))
        }
        try? current.save()
    }
}
