import SwiftUI
import DevinKit

@main
struct DevinMobileApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .task { app.restore() }
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
