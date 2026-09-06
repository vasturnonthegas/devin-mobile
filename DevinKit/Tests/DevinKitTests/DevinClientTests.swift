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

    func testListSessionsEncodesEveryFilterParam() async throws {
        transport.stub(json: Fixtures.sessionsPage)

        let query = SessionQuery(
            first: 100,
            after: "cursor-1",
            tags: ["bug", "auth"],
            isArchived: nil,
            updatedAfter: Date(timeIntervalSince1970: 1_756_800_000),
            updatedBefore: Date(timeIntervalSince1970: 1_756_803_600),
            createdAfter: Date(timeIntervalSince1970: 1_756_700_000),
            createdBefore: Date(timeIntervalSince1970: 1_756_700_500.9),
            repoNames: ["acme/api", "acme/web"],
            userIDs: ["user-1", "user-2"],
            origins: [.webapp, .codeScan],
            playbookID: "playbook-1"
        )
        _ = try await client.sessions(org: "org-xyz", query: query)

        let items = URLComponents(url: transport.lastRequest.url!, resolvingAgainstBaseURL: false)!.queryItems!
        func values(_ name: String) -> [String] { items.filter { $0.name == name }.compactMap(\.value) }

        XCTAssertEqual(values("first"), ["100"])
        XCTAssertEqual(values("after"), ["cursor-1"])
        XCTAssertEqual(values("tags"), ["bug", "auth"])
        XCTAssertEqual(values("repo_names"), ["acme/api", "acme/web"])
        XCTAssertEqual(values("user_ids"), ["user-1", "user-2"])
        XCTAssertEqual(values("origins"), ["webapp", "code_scan"])
        XCTAssertEqual(values("playbook_id"), ["playbook-1"])
        XCTAssertEqual(values("created_after"), ["1756700000"])
        XCTAssertEqual(values("created_before"), ["1756700500"], "dates are whole epoch seconds")
        XCTAssertEqual(values("updated_after"), ["1756800000"])
        XCTAssertEqual(values("updated_before"), ["1756803600"])
        XCTAssertEqual(values("is_archived"), [], "nil filters are omitted")
    }

    func testListSessionsOmitsUnsetFilters() async throws {
        transport.stub(json: Fixtures.sessionsPage)
        _ = try await client.sessions(org: "org-xyz", query: SessionQuery(first: 10))
        XCTAssertEqual(transport.lastRequest.url?.query, "first=10&is_archived=false")
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
        XCTAssertNil(odd.origin)
        XCTAssertNil(odd.category)
        XCTAssertEqual(odd.subcategory, "Whatever")
        XCTAssertEqual(odd.displayTitle, "devin-ghi789")
    }

    func testPullRequestStatesDecodeAndUnknownStaysNeutral() async throws {
        transport.stub(json: Fixtures.sessionWithPullRequests)
        let session = try await client.session(org: "org-xyz", id: "devin-prs001")

        XCTAssertEqual(transport.lastRequest.url?.path, "/v3/organizations/org-xyz/sessions/devin-prs001")
        XCTAssertEqual(transport.lastRequest.httpMethod, "GET")

        let prs = session.pullRequests
        XCTAssertEqual(prs.map(\.stateKind), [.open, .draft, .merged, .closed, .unknown("locked_by_bot"), .unknown(nil)])
        XCTAssertEqual(prs.map(\.stateKind.displayName), ["Open", "Draft", "Merged", "Closed", "Locked by bot", "Unknown"])
        XCTAssertEqual(prs.map(\.stateKind.isResolved), [false, false, true, true, false, false])
        XCTAssertEqual(prs.map(\.shortLabel), [
            "acme/api#42", "acme/api#43", "acme/api#44", "acme/api#45", "acme/web#9", "example.com/review/77",
        ])
        XCTAssertEqual(prs[2].state, "MERGED", "raw value is preserved for logging/debugging")
    }

    func testSecondaryMetadataDecodesNullable() async throws {
        transport.stub(json: Fixtures.sessionsPage)
        let page = try await client.sessions(org: "org-xyz")

        let first = page.items[0]
        XCTAssertEqual(first.category, .bugFixing)
        XCTAssertEqual(first.subcategory, "Authentication")
        XCTAssertEqual(first.automationID, "automation-77")
        XCTAssertEqual(first.origin, .api)
        XCTAssertEqual(first.categorySummary, "Bug fixing › Authentication")
        XCTAssertEqual(first.metadataSummary, ["Bug fixing › Authentication", "API", "Automation"])

        let second = page.items[1]
        XCTAssertEqual(second.category, .featureDevelopment)
        XCTAssertEqual(second.subcategory, "Other")
        XCTAssertNil(second.automationID)
        XCTAssertEqual(second.categorySummary, "Feature development")
        XCTAssertEqual(second.metadataSummary, ["Feature development", "Slack"])

        let odd = page.items[2]
        XCTAssertNil(odd.category)
        XCTAssertNil(odd.categorySummary)
        XCTAssertNil(odd.automationID)
        XCTAssertTrue(odd.metadataSummary.isEmpty)
    }

    func testBucketing() async throws {
        transport.stub(json: Fixtures.sessionsPage)
        let page = try await client.sessions(org: "org-xyz")
        XCTAssertEqual(page.items.map(\.bucket), [.needsYou, .working, .sleeping])
        XCTAssertTrue(page.items[0].needsAttention)
        XCTAssertEqual(page.items[0].statusSummary, "Waiting for you")
        XCTAssertEqual(page.items[2].statusSummary, "Asleep")
    }

    func testChildSessionsFiltersByParentAcrossArchiveState() async throws {
        transport.stub(json: Fixtures.sessionParent)
        let parent = try await client.session(org: "org-xyz", id: "devin-parent")
        XCTAssertEqual(parent.childCount, 2)
        XCTAssertTrue(parent.hasChildren)

        transport.stub(json: Fixtures.childSessionsPage)
        let page = try await client.childSessions(org: "org-xyz", of: parent.id)

        let url = transport.lastRequest.url!
        XCTAssertEqual(url.path, "/v3/organizations/org-xyz/sessions")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertTrue(items.contains(URLQueryItem(name: "parent_session_id", value: "devin-parent")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "first", value: "100")))
        XCTAssertFalse(items.contains { $0.name == "is_archived" }, "archived children must still be listed")

        XCTAssertEqual(page.items.map(\.sessionID), ["devin-child1", "devin-child2"])
        XCTAssertEqual(page.items.map(\.parentSessionID), ["devin-parent", "devin-parent"])
        XCTAssertTrue(page.items[0].isArchived)
        XCTAssertEqual(page.items[0].bucket, .finished)
        XCTAssertNil(page.items[1].origin, "unknown origin must decode as nil")
        XCTAssertFalse(page.items[1].hasChildren)
        XCTAssertFalse(page.hasNextPage)
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
        XCTAssertNil(transport.lastRequest.bodyJSON["attachment_urls"], "no attachments → key omitted, not null")

        transport.stub(json: "null")
        try await client.send(message: "empty list", attachmentURLs: [], org: "org-xyz", id: "devin-abc123")
        XCTAssertNil(transport.lastRequest.bodyJSON["attachment_urls"])
    }

    func testSendMessageWithAttachmentURLs() async throws {
        transport.stub(json: Fixtures.sessionRunningWaiting)
        let url = URL(string: "https://api.devin.ai/v3/organizations/org-xyz/attachments/7f3a9c1e/bug.png")!

        try await client.send(message: "Here's the crash", attachmentURLs: [url], org: "org-xyz", id: "devin-abc123")

        XCTAssertEqual(transport.lastRequest.httpMethod, "POST")
        XCTAssertEqual(transport.lastRequest.url?.path, "/v3/organizations/org-xyz/sessions/devin-abc123/messages")
        XCTAssertEqual(transport.lastRequest.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = transport.lastRequest.bodyJSON
        XCTAssertEqual(body["message"] as? String, "Here's the crash")
        XCTAssertEqual(body["attachment_urls"] as? [String], [url.absoluteString])
        XCTAssertEqual(body.count, 2)
    }

    func testUploadAttachmentBuildsMultipartAndDecodes() async throws {
        transport.stub(json: Fixtures.attachmentUploaded)
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0xFF])

        let uploaded = try await client.upload(data: bytes, filename: "bug.png", mime: "image/png", org: "org-xyz")

        let request = transport.lastRequest
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/v3/organizations/org-xyz/attachments")
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer cog_test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")

        let contentType = request.value(forHTTPHeaderField: "Content-Type") ?? ""
        let prefix = "multipart/form-data; boundary="
        XCTAssertTrue(contentType.hasPrefix(prefix), "got \(contentType)")
        let boundary = String(contentType.dropFirst(prefix.count))
        XCTAssertFalse(boundary.isEmpty)

        let body = request.httpBody!
        let head = Data("""
        --\(boundary)\r
        Content-Disposition: form-data; name="file"; filename="bug.png"\r
        Content-Type: image/png\r
        \r

        """.utf8)
        let tail = Data("\r\n--\(boundary)--\r\n".utf8)
        XCTAssertEqual(body, head + bytes + tail, "exactly one `file` part, raw bytes untouched, CRLF framing")

        XCTAssertEqual(uploaded.attachmentID, "att-7f3a9c")
        XCTAssertEqual(uploaded.name, "bug.png")
        XCTAssertEqual(uploaded.url.absoluteString, "https://api.devin.ai/v3/organizations/org-xyz/attachments/7f3a9c1e-2b4d-4f6a-9c8e-1d2e3f4a5b6c/bug.png")
    }

    func testUploadAttachmentSanitizesFilename() async throws {
        transport.stub(json: Fixtures.attachmentUploaded)
        _ = try await client.upload(data: Data("x".utf8), filename: "we\"ird\r\nname\\.txt", mime: "text/plain", org: "org-xyz")
        let body = String(decoding: transport.lastRequest.httpBody!, as: UTF8.self)
        XCTAssertTrue(body.contains("filename=\"we_ird__name_.txt\""), body)

        transport.stub(json: Fixtures.attachmentUploaded)
        _ = try await client.upload(data: Data("x".utf8), filename: "", mime: "application/octet-stream", org: "org-xyz")
        XCTAssertTrue(String(decoding: transport.lastRequest.httpBody!, as: UTF8.self).contains("filename=\"file\""))
    }

    func testUploadAttachmentTooLargeIsTypedError() async {
        transport.stub(413, json: Fixtures.problem413Attachment)
        do {
            _ = try await client.upload(data: Data(count: 16), filename: "huge.mov", mime: "video/quicktime", org: "org-xyz")
            XCTFail("expected error")
        } catch let error as DevinError {
            guard case .http(let status, let problem) = error else { return XCTFail("expected http error, got \(error)") }
            XCTAssertEqual(status, 413)
            XCTAssertEqual(error.errorDescription, "Attachments must be 25 MB or smaller")
            XCTAssertEqual(problem?.title, "Payload Too Large")
        } catch {
            XCTFail("wrong error type: \(error)")
        }
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

    func testListAttachmentsDecodesSpecArray() async throws {
        transport.stub(json: Fixtures.attachmentsArray)

        let attachments = try await client.attachments(org: "org-xyz", id: "devin-abc123")

        XCTAssertEqual(transport.lastRequest.httpMethod, "GET")
        XCTAssertEqual(transport.lastRequest.url?.path, "/v3/organizations/org-xyz/sessions/devin-abc123/attachments")
        XCTAssertEqual(transport.lastRequest.value(forHTTPHeaderField: "Authorization"), "Bearer cog_test")

        XCTAssertEqual(attachments.map(\.id), ["att-1", "att-2", "att-3", "att-4"])
        XCTAssertEqual(attachments[0].source, .user)
        XCTAssertEqual(attachments[0].contentType, "image/png")
        XCTAssertNil(attachments[1].contentType)
        XCTAssertEqual(attachments[1].source, .devin)
    }

    func testListAttachmentsToleratesPageEnvelope() async throws {
        transport.stub(json: Fixtures.attachmentsPage)
        let attachments = try await client.attachments(org: "org-xyz", id: "devin-abc123")
        XCTAssertEqual(attachments.count, 4)
    }

    func testAttachmentKindFromContentTypeOrExtension() async throws {
        transport.stub(json: Fixtures.attachmentsArray)
        let attachments = try await client.attachments(org: "org-xyz", id: "devin-abc123")

        XCTAssertTrue(attachments[0].isImage, "image/png")
        XCTAssertFalse(attachments[1].isImage, "no content type, .log extension")
        XCTAssertTrue(attachments[2].isImage, "octet-stream falls back to the .HEIC extension")
        XCTAssertEqual(attachments[2].fileExtension, "heic")
        XCTAssertFalse(attachments[3].isImage, "unknown non-image type")
        XCTAssertEqual(attachments[3].fileExtension, "bin", "extension falls back to the URL when the name has none")
    }

    func testAttachmentDataSendsBearerToAPIHostOnly() async throws {
        transport.stub(json: Fixtures.attachmentsArray)
        let attachments = try await client.attachments(org: "org-xyz", id: "devin-abc123")

        transport.stub(json: "PNGBYTES")
        let data = try await client.attachmentData(attachments[0])
        XCTAssertEqual(data, Data("PNGBYTES".utf8))
        XCTAssertEqual(transport.lastRequest.url?.absoluteString,
                       "https://api.devin.ai/v3/organizations/org-xyz/attachments/0f3c-uuid/screenshot.png")
        XCTAssertEqual(transport.lastRequest.value(forHTTPHeaderField: "Authorization"), "Bearer cog_test")
        XCTAssertEqual(transport.lastRequest.value(forHTTPHeaderField: "Accept"), "*/*")

        transport.stub(json: "HEIC")
        _ = try await client.attachmentData(attachments[2])
        XCTAssertEqual(transport.lastRequest.url?.absoluteString,
                       "https://api.devin.ai/v3/organizations/org-xyz/attachments/77e2-uuid/photo.HEIC",
                       "relative URLs resolve against the base URL")
        XCTAssertEqual(transport.lastRequest.value(forHTTPHeaderField: "Authorization"), "Bearer cog_test")

        transport.stub(json: "BIN")
        _ = try await client.attachmentData(attachments[3])
        XCTAssertEqual(transport.lastRequest.url?.absoluteString, "https://cdn.example.com/design.bin")
        XCTAssertNil(transport.lastRequest.value(forHTTPHeaderField: "Authorization"), "token never leaves the API host")
    }

    func testAttachmentDataMapsErrors() async throws {
        transport.stub(json: Fixtures.attachmentsArray)
        let attachments = try await client.attachments(org: "org-xyz", id: "devin-abc123")

        transport.stub(404, json: #"{"status": 404, "title": "Not Found", "detail": "gone"}"#)
        do {
            _ = try await client.attachmentData(attachments[1])
            XCTFail("expected notFound")
        } catch DevinError.notFound(let problem) {
            XCTAssertEqual(problem?.detail, "gone")
        }
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

    func testSessionTagsGet() async throws {
        transport.stub(json: Fixtures.sessionTags)
        let tags = try await client.sessionTags(org: "org-xyz", id: "devin-abc123")
        XCTAssertEqual(transport.lastRequest.httpMethod, "GET")
        XCTAssertEqual(transport.lastRequest.url?.path, "/v3/organizations/org-xyz/sessions/devin-abc123/tags")
        XCTAssertNil(transport.lastRequest.url?.query)
        XCTAssertNil(transport.lastRequest.httpBody)
        XCTAssertEqual(transport.lastRequest.value(forHTTPHeaderField: "Authorization"), "Bearer cog_test")
        XCTAssertEqual(tags, ["bug", "auth", "Mobile Sprint 1"])
    }

    func testReplaceTagsPutsFullSet() async throws {
        transport.stub(json: Fixtures.sessionTags)
        let tags = try await client.replaceTags(["bug", "auth", "Mobile Sprint 1"], org: "org-xyz", id: "devin-abc123")
        XCTAssertEqual(transport.lastRequest.httpMethod, "PUT")
        XCTAssertEqual(transport.lastRequest.url?.path, "/v3/organizations/org-xyz/sessions/devin-abc123/tags")
        XCTAssertEqual(transport.lastRequest.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(transport.lastRequest.bodyJSON["tags"] as? [String], ["bug", "auth", "Mobile Sprint 1"])
        XCTAssertEqual(transport.lastRequest.bodyJSON.count, 1)
        XCTAssertEqual(tags, ["bug", "auth", "Mobile Sprint 1"])
    }

    func testAppendTagsPostsOnlyNewTags() async throws {
        transport.stub(json: Fixtures.sessionTags)
        let tags = try await client.appendTags(["Mobile Sprint 1"], org: "org-xyz", id: "devin-abc123")
        XCTAssertEqual(transport.lastRequest.httpMethod, "POST")
        XCTAssertEqual(transport.lastRequest.url?.path, "/v3/organizations/org-xyz/sessions/devin-abc123/tags")
        XCTAssertEqual(transport.lastRequest.bodyJSON["tags"] as? [String], ["Mobile Sprint 1"])
        XCTAssertEqual(tags.count, 3, "server returns the merged set, not just the appended tags")
    }

    func testReplaceTagsRejectedIsTypedError() async {
        transport.stub(422, json: Fixtures.problem422Tags)
        do {
            _ = try await client.replaceTags(["nope"], org: "org-xyz", id: "devin-abc123")
            XCTFail("expected error")
        } catch let error as DevinError {
            guard case .http(let status, let problem) = error else { return XCTFail("expected http error, got \(error)") }
            XCTAssertEqual(status, 422)
            XCTAssertEqual(problem?.detail, "Tag 'nope' is not in the organization's allowed tags")
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func testSessionTagsNormalize() {
        XCTAssertEqual(SessionTags.normalize("  #mobile "), "mobile")
        XCTAssertEqual(SessionTags.normalize("##Sprint 1"), "Sprint 1")
        XCTAssertNil(SessionTags.normalize("  # "))
        XCTAssertNil(SessionTags.normalize(""))
        XCTAssertEqual(SessionTags.maxCount, 50)
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

    func testMembersBuildsQueryAndDecodes() async throws {
        transport.stub(json: Fixtures.membersPage1)
        let page = try await client.members(org: "org-xyz", after: "m0", first: 50)

        let url = transport.lastRequest.url!
        XCTAssertEqual(transport.lastRequest.httpMethod, "GET")
        XCTAssertEqual(url.path, "/v3beta1/organizations/org-xyz/members/users")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertTrue(items.contains(URLQueryItem(name: "first", value: "50")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "after", value: "m0")))
        XCTAssertEqual(transport.lastRequest.value(forHTTPHeaderField: "Authorization"), "Bearer cog_test")

        XCTAssertEqual(page.items.map(\.userID), ["user-1", "user-2"])
        XCTAssertTrue(page.hasNextPage)
        XCTAssertEqual(page.endCursor, "m1")
        XCTAssertEqual(page.items[0].displayName, "Taj Vasudeva")
        XCTAssertEqual(page.items[0].initials, "TV")
        XCTAssertEqual(page.items[1].displayName, "sam@example.com", "falls back to email when name is null")
        XCTAssertEqual(page.items[1].initials, "S")
    }

    func testAllMembersFollowsCursor() async throws {
        transport.stub(json: Fixtures.membersPage1)
        transport.stub(json: Fixtures.membersPage2)

        let members = try await client.allMembers(org: "org-xyz")

        XCTAssertEqual(members.map(\.userID), ["user-1", "user-2", "user-3"])
        XCTAssertEqual(members[2].displayName, "user-3", "blank name and null email fall back to the ID")
        XCTAssertEqual(transport.requests.count, 2)
        let second = URLComponents(url: transport.requests[1].url!, resolvingAgainstBaseURL: false)!
        XCTAssertTrue(second.queryItems!.contains(URLQueryItem(name: "after", value: "m1")))
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
