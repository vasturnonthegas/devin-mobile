import SwiftUI
import UserNotifications
import DevinKit

/// App delegate whose only job is to own the `DeepLinkRouter` and be `UNUserNotificationCenter`'s
/// delegate from `willFinishLaunching` on — the delegate must be in place before launch completes
/// or a cold-start tap on a notification is lost. Banners are shown in the foreground too, so the
/// debugger-triggered refresh (see PR / HANDOFF) is visible without backgrounding the app.
@MainActor
final class NotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let router = DeepLinkRouter()

    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        DiagnosticsCollector.install()
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let raw = response.notification.request.content.userInfo[SessionNotifier.deepLinkUserInfoKey] as? String,
              let url = URL(string: raw)
        else { return }
        await MainActor.run { router.open(url) }
    }
}

extension View {
    /// Re-arms the background refresh whenever a signed-in app leaves the foreground.
    func schedulesBackgroundRefresh(for app: AppModel) -> some View {
        modifier(BackgroundRefreshScheduling(app: app))
    }
}

private struct BackgroundRefreshScheduling: ViewModifier {
    let app: AppModel
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, phase in
                guard phase == .background, app.account != nil else { return }
                BackgroundRefresh.schedule()
            }
            #if DEBUG
            .task { await MockAPI.simulateBackgroundRefreshIfRequested() }
            #endif
    }
}
