import Foundation
import XCTest
@testable import DevinKit

final class WidgetContentTests: XCTestCase {
    private let credentials = DevinCredentials(token: "cog_test", orgID: "org-xyz")
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "WidgetContentTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func session(_ id: String, _ status: SessionStatus, _ detail: SessionStatusDetail?, updated: TimeInterval) -> Session {
        Session(sessionID: id, orgID: "org-xyz", status: status, statusDetail: detail, title: id,
                url: URL(string: "https://app.devin.ai/sessions/\(id)")!,
                createdAt: Date(timeIntervalSince1970: updated - 60), updatedAt: Date(timeIntervalSince1970: updated))
    }

    func testNoCredentialsAndNoSnapshotIsSignedOut() {
        XCTAssertEqual(WidgetContent.resolve(credentials: InMemoryCredentialStore(), defaults: defaults), .signedOut)
    }

    func testCredentialsWithoutSnapshotAwaitsFirstLoad() {
        XCTAssertEqual(WidgetContent.resolve(credentials: InMemoryCredentialStore(credentials), defaults: defaults), .awaitingFirstLoad)
    }

    func testSnapshotWinsEvenWhenKeychainIsUnreadable() throws {
        let snapshot = SessionSnapshot(sessions: [session("s1", .running, .waitingForUser, updated: 100)],
                                       capturedAt: Date(timeIntervalSince1970: 1_000))
        try snapshot.save(to: defaults)

        XCTAssertEqual(WidgetContent.resolve(credentials: ThrowingCredentialStore(), defaults: defaults), .sessions(snapshot))
        XCTAssertEqual(WidgetContent.resolve(credentials: InMemoryCredentialStore(), defaults: defaults).snapshot, snapshot)
    }

    func testClearingSnapshotFallsBackToKeychain() throws {
        try SessionSnapshot(sessions: [], capturedAt: Date(timeIntervalSince1970: 1_000)).save(to: defaults)
        SessionSnapshot.clear(in: defaults)

        XCTAssertEqual(WidgetContent.resolve(credentials: ThrowingCredentialStore(), defaults: defaults), .signedOut)
        XCTAssertEqual(WidgetContent.resolve(credentials: InMemoryCredentialStore(credentials), defaults: defaults), .awaitingFirstLoad)
    }

    func testTopEntriesKeepInboxOrderAndCap() {
        let snapshot = SessionSnapshot(sessions: [
            session("working", .running, .working, updated: 500),
            session("needs-old", .running, .waitingForUser, updated: 100),
            session("finished", .exit, .finished, updated: 900),
            session("needs-new", .running, .waitingForApproval, updated: 200),
            session("failed", .error, nil, updated: 950),
        ], capturedAt: Date(timeIntervalSince1970: 1_000))

        XCTAssertEqual(snapshot.topEntries().map(\.id), ["needs-new", "needs-old", "working"])
        XCTAssertEqual(snapshot.topEntries(1).map(\.id), ["needs-new"])
        XCTAssertEqual(SessionSnapshot(sessions: []).topEntries(), [])
    }
}

/// Stands in for a Keychain that is locked or lacks the access-group entitlement.
private struct ThrowingCredentialStore: CredentialStore {
    struct Locked: Error {}
    func load() throws -> DevinCredentials? { throw Locked() }
    func save(_ credentials: DevinCredentials) throws { throw Locked() }
    func clear() throws { throw Locked() }
}
