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
        allSessions.first(where: { $0.sessionID == id }).map(current)
    }

    /// The catalogue is immutable; `current` overlays the only state the mock tracks (suspended → resuming,
    /// plus the `-SimulateBackgroundRefresh` status flips).
    static func current(_ session: Session) -> Session {
        if let changed = simulatedStatusChange(for: session) { return changed }
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

    // MARK: Insights

    /// Finished sessions (every 3rd) ship with analysis; the rest have none until `generate` is
    /// called, after which the analysis "arrives" on the second poll (`generatedAt` + `generationDelay`).
    static let generationDelay: TimeInterval = 5
    private static let generationLock = NSLock()
    nonisolated(unsafe) private static var generatedAt: [String: Date] = [:]

    static func insights(for session: Session, index: Int) -> SessionInsights {
        let ready: Bool = {
            if index % 3 == 2 { return true }
            return generationLock.withLock {
                guard let started = generatedAt[session.sessionID] else { return false }
                return Date().timeIntervalSince(started) >= generationDelay
            }
        }()
        return SessionInsights(
            sessionID: session.sessionID,
            numUserMessages: 2 + index % 5,
            numDevinMessages: 7 + index % 9,
            size: SessionInsights.Size.allCases[index % SessionInsights.Size.allCases.count],
            analysis: ready ? analysis(for: session) : nil
        )
    }

    /// Sessions created through `POST …/sessions` this launch, newest first, so they survive the
    /// inbox's next poll and their detail page resolves.
    nonisolated(unsafe) private static var created: [Session] = []

    static var allSessions: [Session] { generationLock.withLock { created } + sessions }

    static func create(prompt: String) -> Session {
        let id = "devin-mock-\(UUID().uuidString.prefix(6).lowercased())"
        let session = Session(sessionID: id, orgID: "org-mock", status: .running, statusDetail: .working,
                              title: String(prompt.prefix(60)), url: URL(string: "https://app.devin.ai/sessions/\(id)")!,
                              createdAt: Date(), updatedAt: Date(), origin: .api, userID: members[0].userID)
        generationLock.withLock { created.insert(session, at: 0) }
        return session
    }

    static func startGeneration(for sessionID: String) -> SessionInsightsGeneration {
        generationLock.withLock {
            if generatedAt[sessionID] != nil { return SessionInsightsGeneration(sessionID: sessionID, status: "already_exists") }
            generatedAt[sessionID] = Date()
            return SessionInsightsGeneration(sessionID: sessionID, status: "started")
        }
    }

    private static func analysis(for session: Session) -> SessionInsightsAnalysis {
        let title = session.title ?? session.sessionID
        return SessionInsightsAnalysis(
            issues: [
                SessionInsightsIssue(issueID: "issue-1", title: "Flaky CI masked the fix", issue: "The test suite was already red on main, so Devin could not tell whether its change worked.",
                                     impact: "Two extra iterations (~1.2 ACU).", label: "environment"),
                SessionInsightsIssue(issue: "The prompt did not name the base branch.", impact: "The PR was opened against develop.", label: "prompt"),
            ],
            timeline: [
                SessionInsightsTimelineEvent(title: "Reproduced the problem", description: "Ran the failing flow locally and captured logs.", color: "green"),
                SessionInsightsTimelineEvent(title: "Blocked on unrelated failures", description: "Spent ~20 minutes on pre-existing red tests.", color: "red", issueID: "issue-1"),
                SessionInsightsTimelineEvent(title: "Opened PR", description: "Pushed the fix and requested review.", color: "blue"),
            ],
            actionItems: [
                SessionInsightsActionItem(kind: .repoConfig, actionItem: "Quarantine the flaky tests or mark them as known failures.", issueID: "issue-1"),
                SessionInsightsActionItem(kind: .promptImprovement, actionItem: "State the base branch and the definition of done in the prompt."),
                SessionInsightsActionItem(kind: nil, actionItem: "An action item type this build doesn't know about."),
            ],
            suggestedPrompt: SessionInsightsSuggestedPrompt(
                originalPrompt: title,
                suggestedPrompt: "\(title). Work in acme/app on a branch off main and open a PR against main. The tests under tests/legacy are known to be flaky — skip them. Done means: CI green and a short summary of the change in the PR body.",
                feedbackItems: [
                    SessionInsightsFeedbackItem(summary: "Name the base branch", excerpt: title, details: "Devin guessed develop."),
                    SessionInsightsFeedbackItem(summary: "Say what done looks like", excerpt: title, details: "No acceptance criteria were given."),
                ]
            )
        )
    }

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
        if method == "GET", parts.count == 4, parts[0] == "v3beta1", parts[3] == "repositories" {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            return encode(MockAPI.repositoriesPage(queryItems: items))
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
            return encode(MockAPI.storeUpload(body: body(of: request), contentType: request.value(forHTTPHeaderField: "Content-Type")))
        }
        if method == "GET", parts.count >= 4, parts[0] == "v3", parts[1] == "organizations", parts[3] == "playbooks" {
            if parts.count == 4 { return (200, MockAPI.playbooksJSON()) }
            return MockAPI.playbookJSON(id: parts[4]).map { (200, $0) } ?? notFound()
        }
        if let reply = MockAPI.knowledgeResponse(method: method, parts: parts, url: url) {
            return reply
        }
        // Everything else is /v3/organizations/{org}/sessions[/{id}[/{sub}]]
        guard parts.count >= 4, parts[0] == "v3", parts[1] == "organizations", parts[3] == "sessions" else { return notFound() }
        let id = parts.count > 4 ? parts[4] : nil
        let sub = parts.count > 5 ? parts[5] : nil

        let sessions = MockAPI.allSessions
        switch (method, id, sub) {
        case ("GET", nil, nil):
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let first = items.first { $0.name == "first" }?.value.flatMap(Int.init) ?? 100
            let offset = items.first { $0.name == "after" }?.value.flatMap(Int.init) ?? 0
            let slice = sessions.dropFirst(offset).prefix(first).map(MockAPI.current)
            let end = offset + slice.count
            let page = Page(items: slice,
                            endCursor: end < sessions.count ? String(end) : nil,
                            hasNextPage: end < sessions.count,
                            total: sessions.count)
            return encode(page)

        case ("POST", nil, nil):
            return encode(MockAPI.createSession(body: body(of: request)))

        case ("GET", let id?, nil), ("DELETE", let id?, nil), ("POST", let id?, "archive"):
            guard let session = MockAPI.session(id: id) else { return notFound() }
            return encode(session)

        case ("GET", let id?, "insights"):
            guard let session = sessions.first(where: { $0.sessionID == id }) else { return notFound() }
            // Created-this-launch sessions have no catalogue index; index 0 puts them on the "generate" path.
            let index = MockAPI.sessions.firstIndex(where: { $0.sessionID == id }) ?? 0
            return encode(MockAPI.insights(for: session, index: index))

        case ("POST", let id?, "insights") where parts.count > 6 && parts[6] == "generate":
            guard sessions.contains(where: { $0.sessionID == id }) else { return notFound() }
            return encode(MockAPI.startGeneration(for: id))

        case ("GET", let id?, "messages"):
            return encode(Page(items: MockAPI.createdMessages(for: id) ?? MockAPI.messages(for: id)))

        case ("POST", let id?, "messages"):
            guard let session = MockAPI.session(id: id) else { return notFound() }
            guard session.messaging.acceptsMessages else {
                return (409, Data(#"{"status":409,"title":"Conflict","detail":"Session has exited and cannot be resumed"}"#.utf8))
            }
            MockAPI.wake(id: id)
            return encode(MockAPI.current(session))

        case ("GET", let id?, "attachments"):
            return (200, MockAPI.createdAttachmentsJSON(for: id) ?? MockAPI.attachmentsJSON(for: id))

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
