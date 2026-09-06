import AppIntents
import DevinKit
import Foundation

/// The API as seen from an intent: credentials from the shared Keychain, one `DevinClient`, and
/// the org they belong to. Built per intent run; nothing is cached across runs.
struct SignedInDevin: Sendable {
    let client: DevinClient
    let orgID: String

    static func current() throws -> SignedInDevin {
        let credentials: DevinCredentials?
        do {
            credentials = try AppGroup.credentialStore.load()
        } catch {
            throw DevinIntentError.keychainUnavailable
        }
        guard let credentials else { throw DevinIntentError.signedOut }
        return SignedInDevin(client: DevinClient(token: credentials.token), orgID: credentials.orgID)
    }

    /// Page 1 of the unfiltered inbox as a snapshot, saved to the App Group on the way out so the
    /// widget and background refresh see what Siri just reported.
    func refreshSnapshot() async throws -> SessionSnapshot {
        let page = try await call { try await client.sessions(org: orgID, query: SessionQuery(first: 50)) }
        let snapshot = SessionSnapshot(sessions: page.items)
        try? snapshot.save()
        return snapshot
    }

    func session(id: String) async throws -> Session {
        try await call { try await client.session(org: orgID, id: id) }
    }

    func createSession(_ request: NewSessionRequest) async throws -> Session {
        try await call { try await client.createSession(org: orgID, request) }
    }

    func send(_ message: String, to sessionID: String) async throws {
        try await call { try await client.send(message: message, org: orgID, id: sessionID) }
    }

    /// Every API failure becomes a `DevinIntentError`, which App Intents renders as a dialog.
    private func call<T: Sendable>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as DevinError {
            throw DevinIntentError(error)
        } catch let error as DevinIntentError {
            throw error
        } catch {
            throw DevinIntentError.request(error.localizedDescription)
        }
    }
}

/// User-facing failures. Siri speaks `localizedStringResource`; Shortcuts shows it in an alert.
enum DevinIntentError: Error, CustomLocalizedStringResourceConvertible {
    case signedOut
    case keychainUnavailable
    case tokenRejected(String)
    case emptyPrompt
    case invalidRepository(String)
    case emptyMessage
    case sessionNotFound
    case cannotMessage(title: String, reason: String)
    case request(String)

    init(_ error: DevinError) {
        switch error {
        case .unauthorized:
            self = .tokenRejected(error.localizedDescription)
        case .notFound:
            self = .sessionNotFound
        default:
            self = .request(error.localizedDescription)
        }
    }

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .signedOut:
            "You're not signed in to Devin. Open the app and paste your API token first."
        case .keychainUnavailable:
            "Devin can't read your credentials right now. Unlock your iPhone and try again."
        case .tokenRejected(let detail):
            "Devin rejected your token: \(detail) Open the app and sign in again."
        case .emptyPrompt:
            "Tell Devin what to do — the prompt can't be empty."
        case .invalidRepository(let raw):
            "“\(raw)” isn't a repository. Use owner/repo, like acme/mobile."
        case .emptyMessage:
            "The message can't be empty."
        case .sessionNotFound:
            "Devin couldn't find that session. It may have been archived or deleted."
        case .cannotMessage(let title, let reason):
            "“\(title)” can't take a message. \(reason)"
        case .request(let detail):
            "Devin couldn't do that. \(detail)"
        }
    }
}
