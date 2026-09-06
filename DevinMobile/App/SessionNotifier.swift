import Foundation
import UserNotifications
import DevinKit

/// Local notifications for inbox transitions found by `BackgroundRefresh` (see
/// `SessionSnapshot.Change.isNotable`). One request per session, keyed by its ID, so a later
/// transition of the same session replaces the earlier banner instead of stacking under it.
/// Each notification carries the session's `devinmobile://` URL in `userInfo`; tapping it goes
/// through `NotificationDelegate` → `DeepLinkRouter`, the same path as any other deep link.
enum SessionNotifier {
    static let deepLinkUserInfoKey = "deepLink"

    /// Above this many changes in one poll, a single summary notification stands in for the batch —
    /// an automation finishing 40 sessions at once should not produce 40 banners.
    static let summaryThreshold = 5

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Shows the system prompt the first time; later calls just report the stored answer.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func post(_ changes: [SessionSnapshot.Change]) async {
        guard !changes.isEmpty, await authorizationStatus() != .denied else { return }
        let center = UNUserNotificationCenter.current()
        if changes.count > summaryThreshold {
            try? await center.add(UNNotificationRequest(identifier: "summary", content: summaryContent(changes), trigger: nil))
            return
        }
        for change in changes {
            try? await center.add(UNNotificationRequest(identifier: "session-\(change.id)", content: content(for: change), trigger: nil))
        }
    }

    static func content(for change: SessionSnapshot.Change) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title(for: change.to)
        content.body = change.entry.title
        content.subtitle = change.entry.statusSummary
        content.sound = .default
        content.threadIdentifier = change.id
        content.userInfo = [deepLinkUserInfoKey: change.entry.deepLink.url.absoluteString]
        return content
    }

    static func summaryContent(_ changes: [SessionSnapshot.Change]) -> UNMutableNotificationContent {
        let needsYou = changes.filter { $0.to == .needsYou }.count
        let finished = changes.count - needsYou
        let content = UNMutableNotificationContent()
        content.title = "\(changes.count) Devin sessions changed"
        content.body = [
            needsYou > 0 ? "\(needsYou) need you" : nil,
            finished > 0 ? "\(finished) finished" : nil,
        ].compactMap { $0 }.joined(separator: " · ")
        content.sound = .default
        content.threadIdentifier = "summary"
        return content
    }

    static func title(for bucket: Session.Bucket) -> String {
        switch bucket {
        case .needsYou: "Devin needs you"
        case .finished: "Devin finished"
        default: bucket.title
        }
    }
}
