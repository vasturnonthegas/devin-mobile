import Foundation
import XCTest
@testable import DevinKit

final class DevinClientTests: XCTestCase {
    private var transport: MockTransport!
    private var client: DevinClient!

    override func setUp() {
        transport = MockTransport()
        client = DevinClient(token: "cog_test", transport: transport)
    }

    func testListSessionsBuildsQueryAndDecodesPage() async throws {
        transport.stub(json: Fixtures.sessionsPage)

        let page = try await client.sessions(org: "org-xyz", query: SessionQuery(first: 25, tags: ["bug"], isArchived: false))

        let url = transport.lastRequest.url!
        XCTAssertEqual(url.path, "/v3/organizations/org-xyz/sessions")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertTrue(items.contains(URLQueryItem(name: "first", value: "25")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "tags", value: "bug")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "is_archived", value: "false")))
        XCTAssertEqual(transport.lastRequest.value(forHTTPHeaderField: "Authorization"), "Bearer cog_test")

        XCTAssertEqual(page.items.count, 3)
        XCTAssertEqual(page.endCursor, "cursor-2")
        XCTAssertTrue(page.hasNextPage)

        let first = page.items[0]
        XCTAssertEqual(first.sessionID, "devin-abc123")
        XCTAssertEqual(first.status, .running)
        XCTAssertEqual(first.statusDetail, .waitingForUser)
        XCTAssertEqual(first.pullRequests.first?.url.absoluteString, "https://github.com/acme/api/pull/42")
        XCTAssertEqual(first.acusConsumed, 3.25)
        XCTAssertEqual(first.createdAt, Date(timeIntervalSince1970: 1_756_800_000))
        XCTAssertEqual(first.devinMode, .fast)
    }

    func testListSessionsPassesCursorAsAfter() async throws {
        transport.stub(json: Fixtures.sessionsPage)
        transport.stub(json: Fixtures.sessionsPage2)

        let first = try await client.sessions(org: "org-xyz", query: SessionQuery(first: 50, isArchived: false))
        let second = try await client.sessions(org: "org-xyz", query: SessionQuery(first: 50, after: first.endCursor, isArchived: false))

        let firstItems = URLComponents(url: transport.requests[0].url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertFalse(firstItems.contains { $0.name == "after" })
        let secondItems = URLComponents(url: transport.requests[1].url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertTrue(secondItems.contains(URLQueryItem(name: "after", value: "cursor-2")))
        XCTAssertTrue(secondItems.contains(URLQueryItem(name: "first", value: "50")))
        XCTAssertTrue(secondItems.contains(URLQueryItem(name: "is_archived", value: "false")))

        XCTAssertEqual(second.items.map(\.sessionID), ["devin-jkl012", "devin-mno345"])
        XCTAssertFalse(second.hasNextPage)
        XCTAssertNil(second.endCursor)
        XCTAssertNil(second.items[0].origin, "unknown origin must decode as nil")
        XCTAssertEqual(second.items[0].bucket, .finished)
        XCTAssertEqual(second.items[1].bucket, .failed)
    }

    func testUnknownEnumValuesDoNotBreakDecoding() async throws {
        transport.stub(json: Fixtures.sessionsPage)
        let page = try await client.sessions(org: "org-xyz")
        let odd = page.items[2]
        XCTAssertEqual(odd.status, .suspended)
        XCTAssertNil(odd.statusDetail)
        XCTAssertNil(odd.devinMode)
        XCTAssertEqual(odd.displayTitle, "devin-ghi789")
    }

    func testBucketing() async throws {
        transport.stub(json: Fixtures.sessionsPage)
        let page = try await client.sessions(org: "org-xyz")
        XCTAssertEqual(page.items.map(\.bucket), [.needsYou, .working, .sleeping])
        XCTAssertTrue(page.items[0].needsAttention)
        XCTAssertEqual(page.items[0].statusSummary, "Waiting for you")
        XCTAssertEqual(page.items[2].statusSummary, "Asleep")
    }

    func testCreateSessionEncodesSnakeCaseBody() async throws {
        transport.stub(json: Fixtures.sessionRunningWaiting)

        let request = NewSessionRequest(
            prompt: "Fix it",
            repos: ["github.com/acme/api"],
            playbookID: "playbook-1",
            devinMode: .ultra,
            maxACULimit: 10,
            tags: ["mobile"]
        )
        let session = try await client.createSession(org: "org-xyz", request)

        XCTAssertEqual(transport.lastRequest.httpMethod, "POST")
        XCTAssertEqual(transport.lastRequest.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = transport.lastRequest.bodyJSON
        XCTAssertEqual(body["prompt"] as? String, "Fix it")
        XCTAssertEqual(body["repos"] as? [String], ["github.com/acme/api"])
        XCTAssertEqual(body["playbook_id"] as? String, "playbook-1")
        XCTAssertEqual(body["devin_mode"] as? String, "ultra")
        XCTAssertEqual(body["max_acu_limit"] as? Int, 10)
        XCTAssertNil(body["title"], "nil optionals must be omitted, not sent as null")
        XCTAssertEqual(session.sessionID, "devin-abc123")
    }

    func testSendMessage() async throws {
        transport.stub(json: "null")
        try await client.send(message: "LGTM, merge it", org: "org-xyz", id: "devin-abc123")
        XCTAssertEqual(transport.lastRequest.url?.path, "/v3/organizations/org-xyz/sessions/devin-abc123/messages")
        XCTAssertEqual(transport.lastRequest.bodyJSON["message"] as? String, "LGTM, merge it")
    }

    func testAllMessagesFollowsCursor() async throws {
        transport.stub(json: Fixtures.messagesPage1)
        transport.stub(json: Fixtures.messagesPage2)

        let messages = try await client.allMessages(org: "org-xyz", id: "devin-abc123")

        XCTAssertEqual(messages.map(\.eventID), ["e1", "e2", "e3"])
        XCTAssertEqual(messages[0].source, .user)
        XCTAssertEqual(transport.requests.count, 2)
        let second = URLComponents(url: transport.requests[1].url!, resolvingAgainstBaseURL: false)!
        XCTAssertTrue(second.queryItems!.contains(URLQueryItem(name: "after", value: "c1")))
    }

    func testListArchivedSessions() async throws {
        transport.stub(json: Fixtures.archivedSessionsPage)

        let page = try await client.sessions(org: "org-xyz", query: SessionQuery(first: 100, isArchived: true))

        let items = URLComponents(url: transport.lastRequest.url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertTrue(items.contains(URLQueryItem(name: "is_archived", value: "true")))
        XCTAssertEqual(page.items.count, 2)
        XCTAssertTrue(page.items.allSatisfy(\.isArchived))
        XCTAssertNil(page.items[0].origin, "unknown origin must decode as nil")
        XCTAssertEqual(page.items[0].pullRequests.first?.state, "merged")
        XCTAssertFalse(page.hasNextPage)
    }

    func testUnarchive() async throws {
        transport.stub(json: Fixtures.sessionUnarchived)

        let session = try await client.unarchive(org: "org-xyz", id: "devin-arch001")

        XCTAssertEqual(transport.lastRequest.httpMethod, "POST")
        XCTAssertEqual(transport.lastRequest.url?.path, "/v3/organizations/org-xyz/sessions/devin-arch001/unarchive")
        XCTAssertNil(transport.lastRequest.url?.query)
        XCTAssertNil(transport.lastRequest.httpBody)
        XCTAssertEqual(transport.lastRequest.value(forHTTPHeaderField: "Authorization"), "Bearer cog_test")
        XCTAssertEqual(session.sessionID, "devin-arch001")
        XCTAssertFalse(session.isArchived)
    }

    func testTerminateWithArchiveFlag() async throws {
        transport.stub(json: Fixtures.sessionRunningWaiting)
        _ = try await client.terminate(org: "org-xyz", id: "devin-abc123", archive: true)
        XCTAssertEqual(transport.lastRequest.httpMethod, "DELETE")
        XCTAssertEqual(transport.lastRequest.url?.query, "archive=true")
    }

    func testMeDecodesOrg() async throws {
        transport.stub(json: Fixtures.selfPAT)
        let me = try await client.me()
        XCTAssertEqual(me.orgID, "org-xyz")
        XCTAssertEqual(me.displayName, "Taj")

        transport.stub(json: Fixtures.selfEnterprisePAT)
        let enterprise = try await client.me()
        XCTAssertNil(enterprise.orgID)
    }

    func testPlaybooks() async throws {
        transport.stub(json: Fixtures.playbooksPage)
        let page = try await client.playbooks(org: "org-xyz")
        XCTAssertEqual(page.items.first?.title, "Fix CI")
        XCTAssertEqual(page.items.first?.macro, "!fixci")
    }

    func testUnauthorizedMapsToTypedError() async {
        transport.stub(401, json: Fixtures.problem401)
        do {
            _ = try await client.me()
            XCTFail("expected error")
        } catch let error as DevinError {
            XCTAssertEqual(error, .unauthorized(ProblemDetail(status: 401, title: "Unauthorized", detail: "Invalid API key")))
            XCTAssertTrue(error.isAuthFailure)
            XCTAssertEqual(error.errorDescription, "Invalid API key")
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func testRateLimitedReadsRetryAfter() async {
        transport.stub(429, json: "{}", headers: ["Retry-After": "7"])
        do {
            _ = try await client.sessions(org: "org-xyz")
            XCTFail("expected error")
        } catch let error as DevinError {
            XCTAssertEqual(error, .rateLimited(retryAfter: 7))
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func testMalformedJSONIsDecodingError() async {
        transport.stub(json: "{\"items\": \"nope\"}")
        do {
            _ = try await client.sessions(org: "org-xyz")
            XCTFail("expected error")
        } catch let error as DevinError {
            guard case .decoding = error else { return XCTFail("expected decoding error, got \(error)") }
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }
}

final class SessionListMergeTests: XCTestCase {
    private func session(_ id: String, updatedAt: TimeInterval = 0) -> Session {
        Session(sessionID: id, orgID: "org-xyz", status: .running, url: URL(string: "https://app.devin.ai/sessions/\(id)")!,
                createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: updatedAt))
    }

    func testAppendingPageKeepsExistingAndDeduplicates() {
        let loaded = [session("a"), session("b")]
        let merged = loaded.merging([session("b", updatedAt: 5), session("c")])
        XCTAssertEqual(merged.map(\.sessionID), ["a", "b", "c"])
        XCTAssertEqual(merged[1].updatedAt, Date(timeIntervalSince1970: 5), "row moved into the incoming page replaces the stale copy")
    }

    func testRefreshingFirstPageWithDeeperPagesLoadedRetainsOlderRows() {
        let loaded = [session("a"), session("b"), session("c")]
        let merged = loaded.merging([session("new"), session("a", updatedAt: 9)], pruneMissing: false)
        XCTAssertEqual(merged.map(\.sessionID), ["a", "b", "c", "new"])
        XCTAssertEqual(merged[0].updatedAt, Date(timeIntervalSince1970: 9))
    }

    func testRefreshingSoleFirstPagePrunesRowsThatFellOff() {
        let loaded = [session("a"), session("archived")]
        let merged = loaded.merging([session("a"), session("new")], pruneMissing: true)
        XCTAssertEqual(merged.map(\.sessionID), ["a", "new"])
    }
}

final class CredentialStoreTests: XCTestCase {
    func testInMemoryRoundTrip() throws {
        let store = InMemoryCredentialStore()
        XCTAssertNil(try store.load())
        try store.save(DevinCredentials(token: "cog_x", orgID: "org-1", displayName: "Taj"))
        XCTAssertEqual(try store.load()?.orgID, "org-1")
        try store.clear()
        XCTAssertNil(try store.load())
    }
}
