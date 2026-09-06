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

    /// Devin Reviews keyed by PR URL. Seeded reviews are long finished; a triggered one walks
    /// pending → running → completed over ~9 s so the detail header's poller has something to show.
    static let reviews = MockReviews(seeded: sessions.enumerated().compactMap { i, session in
        i % 8 == 0 ? session.pullRequests.first?.url : nil
    })

    static let members: [OrgMember] = [
        OrgMember(userID: "user-mock", email: "mock@example.com", name: "Mock User"),
        OrgMember(userID: "user-mock-2", email: "priya@example.com", name: "Priya Natarajan"),
        OrgMember(userID: "user-mock-3", email: "sam.rivera@example.com", name: nil),
    ]
}

final class MockReviews: @unchecked Sendable {
    private let lock = NSLock()
    private var acceptedAt: [URL: Date] = [:]

    init(seeded: [URL]) {
        for url in seeded { acceptedAt[url] = Date(timeIntervalSince1970: 1_756_890_000) }
    }

    func accept(_ url: URL) -> PRReview {
        lock.withLock { acceptedAt[url] = .now }
        return review(for: url)!
    }

    func review(for url: URL) -> PRReview? {
        guard let accepted = lock.withLock({ acceptedAt[url] }) else { return nil }
        let age = Date.now.timeIntervalSince(accepted)
        let status: PRReviewStatus = age < 3 ? .pending : age < 9 ? .running : .completed
        let parts = url.pathComponents.filter { $0 != "/" }
        return PRReview(
            status: status,
            repoPath: "\(url.host ?? "github.com")/\(parts.prefix(2).joined(separator: "/"))",
            prNumber: parts.last.flatMap(Int.init) ?? 0,
            commitSHA: String(String(repeating: String(format: "%016lx", UInt(bitPattern: url.absoluteString.hashValue)), count: 3).prefix(40)),
            createdAt: accepted
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
            let prURL: URL?
            if method == "POST" {
                let body = (try? JSONSerialization.jsonObject(with: bodyData(of: request))) as? [String: Any]
                prURL = (body?["pr_url"] as? String).flatMap { URL(string: $0) }
            } else {
                prURL = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "pr_url" }?.value.flatMap { URL(string: $0) }
            }
            guard let prURL else { return (422, Data(#"{"status":422,"title":"Unprocessable Content","detail":"pr_url is required"}"#.utf8)) }
            if method == "POST" { return encode(MockAPI.reviews.accept(prURL)) }
            guard let review = MockAPI.reviews.review(for: prURL) else { return notFound() }
            return encode(review)
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

        case ("GET", let id?, nil), ("DELETE", let id?, nil), ("POST", let id?, "archive"):
            guard let session = MockAPI.sessions.first(where: { $0.sessionID == id }) else { return notFound() }
            return encode(session)

        case ("GET", _?, "messages"):
            return encode(Page<SessionMessage>(items: []))

        case ("GET", _?, "attachments"):
            return encode(Page<SessionAttachment>(items: []))

        default:
            return notFound()
        }
    }

    /// URLSession hands protocols the body as a stream, not `httpBody`.
    private static func bodyData(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
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
