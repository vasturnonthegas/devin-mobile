import Foundation
import XCTest
@testable import DevinKit

final class DeepLinkTests: XCTestCase {
    func testParsesSessionLinkInBothHostAndPathForms() {
        XCTAssertEqual(DeepLink(url: URL(string: "devinmobile://session/devin-abc123")!), .session(id: "devin-abc123"))
        XCTAssertEqual(DeepLink(url: URL(string: "devinmobile:///session/devin-abc123")!), .session(id: "devin-abc123"))
        XCTAssertEqual(DeepLink(url: URL(string: "DevinMobile://session/devin-abc123")!), .session(id: "devin-abc123"))
    }

    func testRejectsForeignAndMalformedURLs() {
        for raw in [
            "https://app.devin.ai/sessions/devin-abc123",
            "devinmobile://session",
            "devinmobile://session/",
            "devinmobile://session/a/b",
            "devinmobile://playbook/pb-1",
            "devinmobile://",
        ] {
            XCTAssertNil(DeepLink(url: URL(string: raw)!), raw)
        }
    }

    func testURLRoundTrips() {
        let link = DeepLink.session(id: "devin-abc123")
        XCTAssertEqual(link.url.absoluteString, "devinmobile://session/devin-abc123")
        XCTAssertEqual(DeepLink(url: link.url), link)
    }
}

final class SessionSnapshotTests: XCTestCase {
    private func session(_ id: String, _ status: SessionStatus, _ detail: SessionStatusDetail?, updated: TimeInterval, title: String? = nil) -> Session {
        Session(sessionID: id, orgID: "org-xyz", status: status, statusDetail: detail, title: title,
                url: URL(string: "https://app.devin.ai/sessions/\(id)")!,
                createdAt: Date(timeIntervalSince1970: updated - 60), updatedAt: Date(timeIntervalSince1970: updated))
    }

    func testOrdersByBucketThenRecency() {
        let snapshot = SessionSnapshot(sessions: [
            session("working-old", .running, .working, updated: 100),
            session("needs-old", .running, .waitingForUser, updated: 200, title: "Fix CI"),
            session("finished", .exit, .finished, updated: 900),
            session("needs-new", .running, .waitingForApproval, updated: 300),
            session("failed", .error, nil, updated: 950),
        ], capturedAt: Date(timeIntervalSince1970: 1_000))

        XCTAssertEqual(snapshot.entries.map(\.id), ["needs-new", "needs-old", "working-old", "finished", "failed"])
        XCTAssertEqual(snapshot.needsYouCount, 2)
        XCTAssertEqual(snapshot.count(.sleeping), 0)
        XCTAssertEqual(snapshot.entries(in: .needsYou).map(\.title), ["needs-new", "Fix CI"])
        XCTAssertEqual(snapshot.entries[1].statusSummary, "Waiting for you")
        XCTAssertEqual(snapshot.entries[0].deepLink.url.absoluteString, "devinmobile://session/needs-new")
    }

    func testRoundTripsThroughDefaults() throws {
        let suite = "SessionSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertNil(SessionSnapshot.load(from: defaults))

        let snapshot = SessionSnapshot(sessions: [session("s1", .suspended, .inactivity, updated: 100)],
                                       capturedAt: Date(timeIntervalSince1970: 1_000))
        try snapshot.save(to: defaults)
        XCTAssertEqual(SessionSnapshot.load(from: defaults), snapshot)

        SessionSnapshot.clear(in: defaults)
        XCTAssertNil(SessionSnapshot.load(from: defaults))
    }
}

final class CredentialStoreAdoptionTests: XCTestCase {
    private let credentials = DevinCredentials(token: "cog_test", orgID: "org-xyz", displayName: "Test")

    func testMovesLegacyCredentialsIntoSharedStore() throws {
        let shared = InMemoryCredentialStore()
        let legacy = InMemoryCredentialStore(credentials)

        let chosen = shared.adoptingCredentials(from: legacy)

        XCTAssertTrue(chosen is InMemoryCredentialStore && (chosen as? InMemoryCredentialStore) === shared)
        XCTAssertEqual(try shared.load(), credentials)
        XCTAssertNil(try legacy.load(), "moved, not copied")
    }

    func testSharedCredentialsWinOverLegacy() throws {
        let shared = InMemoryCredentialStore(credentials)
        let stale = DevinCredentials(token: "cog_old", orgID: "org-old")
        let legacy = InMemoryCredentialStore(stale)

        _ = shared.adoptingCredentials(from: legacy)

        XCTAssertEqual(try shared.load(), credentials)
        XCTAssertEqual(try legacy.load(), stale, "nothing is touched once the shared store is populated")
    }

    func testFallsBackToLegacyWhenSharedStoreIsUnusable() throws {
        let legacy = InMemoryCredentialStore(credentials)

        let chosen = FailingCredentialStore().adoptingCredentials(from: legacy)

        XCTAssertTrue((chosen as? InMemoryCredentialStore) === legacy)
        XCTAssertEqual(try legacy.load(), credentials)
    }

    /// Stands in for a Keychain without the access-group entitlement (errSecMissingEntitlement on every call).
    private struct FailingCredentialStore: CredentialStore {
        struct Unusable: Error {}
        func load() throws -> DevinCredentials? { throw Unusable() }
        func save(_ credentials: DevinCredentials) throws { throw Unusable() }
        func clear() throws { throw Unusable() }
    }
}
