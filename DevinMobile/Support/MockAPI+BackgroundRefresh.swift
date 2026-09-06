#if DEBUG
import Foundation
import DevinKit

/// `-MockAPI -SimulateBackgroundRefresh` demonstrates the notification path end to end without a
/// PAT or the BGTaskScheduler debugger incantation: a few seconds after launch — once the inbox has
/// published its snapshot — the mock flips three sessions' statuses and runs one
/// `BackgroundRefresh` pass, which should post exactly two banners (`devin-mock001`, `devin-mock004`).
/// The inbox's own 10 s poll then catches up and shows the same changes.
extension MockAPI {
    static var simulatesBackgroundRefresh: Bool { ProcessInfo.processInfo.arguments.contains("-SimulateBackgroundRefresh") }

    /// Applied on top of the catalogue once `simulateBackgroundRefreshIfRequested` arms them.
    static let simulatedStatusChanges: [String: (status: SessionStatus, detail: SessionStatusDetail?)] = [
        "devin-mock001": (.running, .waitingForUser), // working → needsYou: notified
        "devin-mock004": (.exit, .finished),          // working → finished: notified
        "devin-mock006": (.running, .working),        // needsYou → working: inbox only
    ]

    private static let statusChangesArmed = LockedFlag()

    static func simulatedStatusChange(for session: Session) -> Session? {
        guard statusChangesArmed.isSet, let change = simulatedStatusChanges[session.sessionID] else { return nil }
        return Session(
            sessionID: session.sessionID, orgID: session.orgID, status: change.status, statusDetail: change.detail,
            title: session.title, url: session.url, tags: session.tags, pullRequests: session.pullRequests,
            acusConsumed: session.acusConsumed, createdAt: session.createdAt, updatedAt: .now,
            devinMode: session.devinMode, origin: session.origin, userID: session.userID,
            structuredOutput: session.structuredOutput
        )
    }

    static func simulateBackgroundRefreshIfRequested() async {
        guard isEnabled, simulatesBackgroundRefresh else { return }
        try? await Task.sleep(for: .seconds(4))
        statusChangesArmed.set()
        await BackgroundRefresh.run(credentials: credentialStore)
    }

    private final class LockedFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var isSet: Bool { lock.withLock { value } }
        func set() { lock.withLock { value = true } }
    }
}
#endif
