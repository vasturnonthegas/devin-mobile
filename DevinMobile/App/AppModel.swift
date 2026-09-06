import Foundation
import Observation
import DevinKit

/// Signed-in state: the credentials plus the objects built from them.
@MainActor
final class Account {
    let credentials: DevinCredentials
    let client: DevinClient
    let sessions: SessionStore

    init(credentials: DevinCredentials, client: DevinClient) {
        self.credentials = credentials
        self.client = client
        self.sessions = SessionStore(client: client, orgID: credentials.orgID)
    }
}

@Observable
@MainActor
final class AppModel {
    enum AuthState {
        case loading
        case signedOut
        case signedIn(Account)
    }

    private(set) var authState: AuthState = .loading
    private let store: any CredentialStore

    init(store: any CredentialStore = KeychainCredentialStore()) {
        self.store = store
    }

    var account: Account? {
        if case .signedIn(let account) = authState { return account }
        return nil
    }

    func restore() {
        guard case .loading = authState else { return }
        if let credentials = try? store.load() {
            authState = .signedIn(Account(credentials: credentials, client: DevinClient(token: credentials.token)))
        } else {
            authState = .signedOut
        }
    }

    /// Validates the token against `GET /v3/self`, resolves the organization, and persists.
    /// `orgOverride` is required for enterprise PATs, which aren't bound to a single org.
    func signIn(token rawToken: String, orgOverride: String?) async throws {
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let client = DevinClient(token: token)
        let me = try await client.me()

        let override = orgOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let orgID = override.isEmpty ? me.orgID : override, !orgID.isEmpty else {
            throw DevinError.missingOrganization
        }

        // Make sure the org is actually reachable before persisting.
        _ = try await client.sessions(org: orgID, query: SessionQuery(first: 1))

        let credentials = DevinCredentials(token: token, orgID: orgID, displayName: me.displayName)
        try store.save(credentials)
        authState = .signedIn(Account(credentials: credentials, client: client))
    }

    func signOut() {
        account?.sessions.stopPolling()
        try? store.clear()
        WidgetTimeline.clear()
        authState = .signedOut
    }
}
