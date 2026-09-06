import SwiftUI
import DevinKit

@main
struct DevinMobileApp: App {
    @State private var app = AppModel(store: DevinMobileApp.credentialStore)
    // Owns the DeepLinkRouter so notification taps and URL opens land in the same place.
    @UIApplicationDelegateAdaptor(NotificationDelegate.self) private var notifications

    init() {
        #if DEBUG
        MockAPI.installIfEnabled()
        #endif
    }

    private static var credentialStore: any CredentialStore {
        #if DEBUG
        if MockAPI.isEnabled { return MockAPI.credentialStore }
        #endif
        // Shared with extensions via the App Group; a pre-existing app-private item is moved over once.
        return AppGroup.credentialStore.adoptingCredentials(from: KeychainCredentialStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(notifications.router)
                .task { app.restore() }
                .onOpenURL { url in notifications.router.open(url) }
                .schedulesBackgroundRefresh(for: app)
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.taskIdentifier)) {
            await BackgroundRefresh.run(credentials: await MainActor.run { DevinMobileApp.credentialStore })
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        switch app.authState {
        case .loading:
            ProgressView()
        case .signedOut:
            OnboardingView()
        case .signedIn(let account):
            InboxView(store: account.sessions)
                .id(account.credentials.orgID)
        }
    }
}
