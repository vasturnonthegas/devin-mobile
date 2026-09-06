import Foundation

/// What a glanceable extension (home-screen widget) should show, derived from the shared Keychain
/// and the last `SessionSnapshot`.
///
/// The app owns the snapshot's lifecycle — it is republished after every unfiltered refresh and
/// removed at sign-out — so a present snapshot is proof of a signed-in user even when the Keychain
/// can't be read (device locked before first unlock, entitlement missing, in-memory credentials
/// under `-MockAPI`). Credentials alone, without a snapshot, mean the inbox hasn't loaded yet.
public enum WidgetContent: Hashable, Sendable {
    case signedOut
    case awaitingFirstLoad
    case sessions(SessionSnapshot)

    public static func resolve(credentials: any CredentialStore, defaults: UserDefaults = AppGroup.defaults) -> WidgetContent {
        if let snapshot = SessionSnapshot.load(from: defaults) {
            return .sessions(snapshot)
        }
        let hasCredentials = (try? credentials.load()) != nil
        return hasCredentials ? .awaitingFirstLoad : .signedOut
    }

    public var snapshot: SessionSnapshot? {
        if case .sessions(let snapshot) = self { return snapshot }
        return nil
    }
}

public extension SessionSnapshot {
    /// The rows a widget lists: `needsYou` first, then the rest of the inbox order, capped at `limit`.
    func topEntries(_ limit: Int = 3) -> [Entry] {
        Array(entries.prefix(limit))
    }
}
