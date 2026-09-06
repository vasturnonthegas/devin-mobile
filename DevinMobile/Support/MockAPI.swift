#if DEBUG
import Foundation
import DevinKit

/// Debug-only stand-in for api.devin.ai so the app can be driven in the Simulator without a PAT.
/// Enabled by the `-MockAPI` launch argument: the app starts signed in (in-memory credentials, the
/// Keychain is untouched) and every request to `DevinClient.defaultBaseURL` is answered from an
/// in-memory catalogue of `sessionCount` sessions.
enum MockAPI {
    static let sessionCount = 130
    static let latency: TimeInterval = 0.4

    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-MockAPI") }

    static let credentialStore = InMemoryCredentialStore(DevinCredentials(token: "cog_mock", orgID: "org-mock", displayName: "Mock User"))

    static func installIfEnabled() {
        guard isEnabled else { return }
        URLProtocol.registerClass(MockAPIProtocol.self)
    }

    static let sessions: [Session] = {
        let now = Date(timeIntervalSince1970: 1_756_900_000)
        let shapes: [(SessionStatus, SessionStatusDetail?, DevinMode?)] = [
            (.running, .waitingForUser, .normal),
            (.running, .working, .fast),
            (.exit, .finished, .normal),
            (.suspended, .inactivity, .ultra),
            (.running, .working, .normal),
            (.error, .error, nil),
            (.running, .waitingForApproval, .lite),
            (.suspended, .finished, .normal),
        ]
        let titles = ["Fix flaky CI on main", "Add dark mode toggle", "Migrate to Swift Testing", "Bump dependencies",
                      "Investigate memory leak in inbox", "Write onboarding docs", "Refactor auth flow", "Paginate sessions list"]
        return (0..<sessionCount).map { i in
            let shape = shapes[i % shapes.count]
            let id = String(format: "devin-mock%03d", i)
            return Session(
                sessionID: id,
                orgID: "org-mock",
                status: shape.0,
                statusDetail: shape.1,
                title: "\(titles[i % titles.count]) #\(i)",
                url: URL(string: "https://app.devin.ai/sessions/\(id)")!,
                tags: i % 3 == 0 ? ["mobile", "sprint-1"] : [],
                pullRequests: i % 4 == 0 ? [PullRequest(url: URL(string: "https://github.com/acme/app/pull/\(100 + i)")!, state: "open")] : [],
                acusConsumed: Double(i % 7) * 0.75,
                createdAt: now.addingTimeInterval(-Double(i) * 3_600 - 600),
                updatedAt: now.addingTimeInterval(-Double(i) * 3_600),
                devinMode: shape.2,
                origin: .api,
                userID: members[i % members.count].userID
            )
        }
    }()

    static let members: [OrgMember] = [
        OrgMember(userID: "user-mock", email: "mock@example.com", name: "Mock User"),
        OrgMember(userID: "user-mock-2", email: "priya@example.com", name: "Priya Natarajan"),
        OrgMember(userID: "user-mock-3", email: "sam.rivera@example.com", name: nil),
    ]
}

final class MockAPIProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == DevinClient.defaultBaseURL.host
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, body) = Self.respond(to: request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        DispatchQueue.global().asyncAfter(deadline: .now() + MockAPI.latency) { [self] in
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    private static func respond(to request: URLRequest) -> (Int, Data) {
        guard let url = request.url else { return (400, Data()) }
        let method = request.httpMethod ?? "GET"
        let parts = url.pathComponents.filter { $0 != "/" }
        if method == "GET", parts == ["v3", "self"] {
            return (200, Data(#"{"principal_type":"user","user_id":"user-mock","user_name":"Mock User","org_id":"org-mock"}"#.utf8))
        }
        if method == "GET", parts.count == 5, parts[0] == "v3beta1", parts[3] == "members", parts[4] == "users" {
            return encode(Page(items: MockAPI.members))
        }
        if method == "GET", parts.count == 6, parts[0] == "v3", parts[3] == "attachments" {
            return MockAPI.attachmentBody(uuid: parts[4], name: parts[5]).map { (200, $0) } ?? notFound()
        }
        if method == "POST", parts.count == 4, parts[0] == "v3", parts[3] == "attachments" {
            let uuid = UUID().uuidString.lowercased()
            return encode(UploadedAttachment(attachmentID: "att-\(uuid.prefix(8))", name: "upload.png",
                                             url: URL(string: "https://api.devin.ai/v3/organizations/org-mock/attachments/\(uuid)/upload.png")!))
        }
        // Everything else is /v3/organizations/{org}/sessions[/{id}[/{sub}]]
        guard parts.count >= 4, parts[0] == "v3", parts[1] == "organizations", parts[3] == "sessions" else { return notFound() }
        let id = parts.count > 4 ? parts[4] : nil
        let sub = parts.count > 5 ? parts[5] : nil

        switch (method, id, sub) {
        case ("GET", nil, nil):
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let first = items.first { $0.name == "first" }?.value.flatMap(Int.init) ?? 100
            let offset = items.first { $0.name == "after" }?.value.flatMap(Int.init) ?? 0
            let slice = Array(MockAPI.sessions.dropFirst(offset).prefix(first))
            let end = offset + slice.count
            let page = Page(items: slice,
                            endCursor: end < MockAPI.sessions.count ? String(end) : nil,
                            hasNextPage: end < MockAPI.sessions.count,
                            total: MockAPI.sessions.count)
            return encode(page)

        case ("GET", let id?, nil), ("DELETE", let id?, nil), ("POST", let id?, "archive"), ("POST", let id?, "messages"):
            guard let session = MockAPI.sessions.first(where: { $0.sessionID == id }) else { return notFound() }
            return encode(session)

        case ("GET", let id?, "messages"):
            return encode(Page(items: MockAPI.messages(for: id)))

        case ("GET", let id?, "attachments"):
            return (200, MockAPI.attachmentsJSON(for: id))

        default:
            return notFound()
        }
    }

    private static func encode<T: Encodable>(_ value: T) -> (Int, Data) {
        (200, (try? encoder.encode(value)) ?? Data())
    }

    private static func notFound() -> (Int, Data) {
        (404, Data(#"{"status":404,"title":"Not Found","detail":"MockAPI has no handler for this route"}"#.utf8))
    }
}
#endif
