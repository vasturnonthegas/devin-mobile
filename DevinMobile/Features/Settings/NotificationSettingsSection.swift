import SwiftUI
import UserNotifications

/// Settings row for the notification permission. iOS only shows the system prompt once; after a
/// denial the only way back is the Settings app, so the row turns into a link there.
struct NotificationSettingsSection: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var status: UNAuthorizationStatus?

    var body: some View {
        Section {
            switch status {
            case .authorized, .provisional, .ephemeral:
                Label("Notifications on", systemImage: "bell.badge.fill")
                    .foregroundStyle(.primary)
            case .denied:
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    Link(destination: url) {
                        Label("Turn on in Settings", systemImage: "bell.slash")
                    }
                }
            case .notDetermined:
                Button {
                    Task { await request() }
                } label: {
                    Label("Enable notifications", systemImage: "bell")
                }
            case nil:
                ProgressView()
            @unknown default:
                Label("Notifications", systemImage: "bell")
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Get a notification when a session needs you or finishes. Devin checks about every 15 minutes in the background.")
        }
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            // The user may have just come back from the Settings app.
            if phase == .active { Task { await refresh() } }
        }
    }

    private func refresh() async {
        status = await SessionNotifier.authorizationStatus()
    }

    private func request() async {
        await SessionNotifier.requestAuthorization()
        await refresh()
    }
}
