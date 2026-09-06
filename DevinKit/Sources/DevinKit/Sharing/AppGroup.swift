import Foundation

/// Identifiers shared by the app and its extensions (widget, intents, share sheet).
///
/// One string serves as both the App Group and the Keychain access group: iOS lets an app use its
/// app groups as keychain access groups without the team-ID prefix, so credentials and the
/// last-known session snapshot are reachable from every target that carries the same
/// `com.apple.security.application-groups` entitlement (see `project.yml`).
public enum AppGroup {
    public static let identifier = "group.ai.devin.mobile"

    /// Preferences shared across the group; `.standard` only when the suite can't be opened.
    public static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    #if canImport(Security)
    /// Credentials visible to every target in the group. Fails with `errSecMissingEntitlement`
    /// (-34018) in a build without the App Group entitlement; callers fall back to the private store.
    public static var credentialStore: KeychainCredentialStore {
        KeychainCredentialStore(accessGroup: identifier)
    }
    #endif
}

public extension CredentialStore {
    /// Picks the store to use at launch: `self` (the shared one) once `legacy`'s credentials are moved
    /// into it, or `legacy` when `self` can't be used at all (missing entitlement, locked keychain).
    /// Idempotent: a second call finds `legacy` empty and `self` populated.
    func adoptingCredentials(from legacy: some CredentialStore) -> any CredentialStore {
        do {
            guard try load() == nil, let credentials = try? legacy.load() else { return self }
            try save(credentials)
        } catch {
            return legacy
        }
        try? legacy.clear()
        return self
    }
}
