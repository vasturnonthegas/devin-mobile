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
                pullRequests: pullRequests(forSessionIndex: i),
                acusConsumed: Double(i % 7) * 0.75,
                createdAt: now.addingTimeInterval(-Double(i) * 3_600 - 600),
                updatedAt: now.addingTimeInterval(-Double(i) * 3_600),
                devinMode: shape.2,
                origin: .api,
                userID: members[i % members.count].userID,
                structuredOutput: shape.1 == .finished ? structuredOutput(index: i) : nil
            )
        }
    }()

    /// Every fourth session has a PR, cycling through these states; the first session gets one PR
    /// per state so a single screen shows every badge plus the neutral fallback.
    static let pullRequestStates: [String?] = ["open", "draft", "merged", "closed", "locked_by_bot", nil]

    static func pullRequests(forSessionIndex i: Int) -> [PullRequest] {
        guard i % 4 == 0 else { return [] }
        let states = i == 0 ? pullRequestStates : [pullRequestStates[(i / 4) % pullRequestStates.count]]
        return states.enumerated().map { offset, state in
            PullRequest(url: URL(string: "https://github.com/acme/app/pull/\(100 + i + offset)")!, state: state)
        }
    }

    private static func structuredOutput(index: Int) -> JSONValue {
        .object([
            "summary": .string("Found \(index % 5) flaky tests in CI"),
            "confidence": .number(0.85),
            "tests_run": .number(Double(120 + index)),
            "has_blockers": .bool(index % 2 == 0),
            "owner": .null,
            "issues": .array([
                .object(["file": .string("Tests/LoginTests.swift"), "line": .number(42), "reasons": .array([.string("timing"), .string("shared state")])]),
                .object(["file": .string("Tests/InboxTests.swift"), "line": .number(7), "reasons": .array([])]),
            ]),
            "meta": .object([:]),
        ])
    }

    /// IDs woken by `POST …/messages`; mirrors the real API, which resumes a suspended session on message.
    private static let woken = LockedSet()

    static func wake(id: String) { woken.insert(id) }

    static func session(id: String) -> Session? {
        sessions.first(where: { $0.sessionID == id }).map(current)
    }

    /// The catalogue is immutable; `current` overlays the only state the mock tracks (suspended → resuming).
    static func current(_ session: Session) -> Session {
        guard session.status == .suspended, woken.contains(session.sessionID) else { return session }
        return Session(
            sessionID: session.sessionID, orgID: session.orgID, status: .resuming, statusDetail: nil,
            title: session.title, url: session.url, tags: session.tags, pullRequests: session.pullRequests,
            acusConsumed: session.acusConsumed, createdAt: session.createdAt, updatedAt: .now,
            devinMode: session.devinMode, origin: session.origin, userID: session.userID,
            structuredOutput: session.structuredOutput
        )
    }

    private final class LockedSet: @unchecked Sendable {
        private let lock = NSLock()
        private var ids: Set<String> = []
        func insert(_ id: String) { lock.withLock { _ = ids.insert(id) } }
        func contains(_ id: String) -> Bool { lock.withLock { ids.contains(id) } }
    }

    static let members: [OrgMember] = [
        OrgMember(userID: "user-mock", email: "mock@example.com", name: "Mock User"),
        OrgMember(userID: "user-mock-2", email: "priya@example.com", name: "Priya Natarajan"),
        OrgMember(userID: "user-mock-3", email: "sam.rivera@example.com", name: nil),
    ]

    /// Devin Reviews keyed by PR URL. Every other mock PR starts reviewed; triggering one walks
    /// pending → running → completed over `reviewDuration` seconds of wall-clock time.
    static let reviews = MockReviews()
}

final class MockReviews: @unchecked Sendable {
    static let reviewDuration: TimeInterval = 8

    private let lock = NSLock()
    private var queuedAt: [URL: Date] = [:]

    init() {
        let longAgo = Date(timeIntervalSince1970: 1_756_890_000)
        for session in MockAPI.sessions {
            for pr in session.pullRequests where pr.url.lastPathComponent.hasSuffix("0") || pr.url.lastPathComponent.hasSuffix("8") {
                queuedAt[pr.url] = longAgo
            }
        }
    }

    func trigger(_ url: URL) -> PRReview {
        lock.withLock {
            let now = Date.now
            queuedAt[url] = now
            return review(for: url, queuedAt: now)
        }
    }

    func latest(_ url: URL) -> PRReview? {
        lock.withLock { queuedAt[url].map { review(for: url, queuedAt: $0) } }
    }

    private func review(for url: URL, queuedAt: Date) -> PRReview {
        let elapsed = Date.now.timeIntervalSince(queuedAt)
        let status: PRReviewStatus = elapsed < Self.reviewDuration / 4 ? .pending
            : elapsed < Self.reviewDuration ? .running
            : url.lastPathComponent.hasSuffix("8") ? .errored : .completed
        let parts = url.pathComponents.filter { $0 != "/" }
        let hex = String(Int(queuedAt.timeIntervalSince1970), radix: 16)
        return PRReview(
            status: status,
            repoPath: "\(url.host ?? "github.com")/\(parts[0])/\(parts[1])",
            prNumber: Int(url.lastPathComponent) ?? 0,
            commitSHA: String(String(repeating: hex, count: 5).prefix(40)),
            createdAt: queuedAt
        )
    }
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
        if parts.count == 4, parts[0] == "v3", parts[1] == "organizations", parts[3] == "pr-reviews" {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let prURL: URL?
            if method == "POST" {
                prURL = body(of: request).flatMap { try? JSONDecoder().decode([String: URL].self, from: $0) }?["pr_url"]
            } else {
                prURL = items.first { $0.name == "pr_url" }?.value.flatMap(URL.init)
            }
            guard let prURL else { return (422, Data(#"{"status":422,"title":"Unprocessable Content","detail":"pr_url is required"}"#.utf8)) }
            if method == "POST" { return encode(MockAPI.reviews.trigger(prURL)) }
            guard let review = MockAPI.reviews.latest(prURL) else { return notFound() }
            return encode(review)
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
            let slice = MockAPI.sessions.dropFirst(offset).prefix(first).map(MockAPI.current)
            let end = offset + slice.count
            let page = Page(items: slice,
                            endCursor: end < MockAPI.sessions.count ? String(end) : nil,
                            hasNextPage: end < MockAPI.sessions.count,
                            total: MockAPI.sessions.count)
            return encode(page)

        case ("GET", let id?, nil), ("DELETE", let id?, nil), ("POST", let id?, "archive"):
            guard let session = MockAPI.session(id: id) else { return notFound() }
            return encode(session)

        case ("GET", let id?, "messages"):
            return encode(Page(items: MockAPI.messages(for: id)))

        case ("POST", let id?, "messages"):
            guard let session = MockAPI.session(id: id) else { return notFound() }
            guard session.messaging.acceptsMessages else {
                return (409, Data(#"{"status":409,"title":"Conflict","detail":"Session has exited and cannot be resumed"}"#.utf8))
            }
            MockAPI.wake(id: id)
            return encode(MockAPI.current(session))

        case ("GET", let id?, "attachments"):
            return (200, MockAPI.attachmentsJSON(for: id))

        default:
            return notFound()
        }
    }

    /// URLSession hands protocols the body as a stream, not `httpBody`.
    private static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: 4096)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }

    private static func encode<T: Encodable>(_ value: T) -> (Int, Data) {
        (200, (try? encoder.encode(value)) ?? Data())
    }

    private static func notFound() -> (Int, Data) {
        (404, Data(#"{"status":404,"title":"Not Found","detail":"MockAPI has no handler for this route"}"#.utf8))
    }
}
#endif
