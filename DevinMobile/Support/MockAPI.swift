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

        case ("POST", nil, nil):
            struct Body: Decodable { let prompt: String }
            let prompt = body(of: request).flatMap { try? JSONDecoder().decode(Body.self, from: $0) }?.prompt ?? "New session"
            let id = "devin-mock-\(UUID().uuidString.prefix(6).lowercased())"
            return encode(Session(sessionID: id, orgID: "org-mock", status: .running, statusDetail: .working,
                                  title: String(prompt.prefix(60)), url: URL(string: "https://app.devin.ai/sessions/\(id)")!,
                                  createdAt: Date(), updatedAt: Date(), origin: .api, userID: MockAPI.members[0].userID))

        case ("GET", let id?, nil), ("DELETE", let id?, nil), ("POST", let id?, "archive"):
            guard let session = MockAPI.sessions.first(where: { $0.sessionID == id }) else { return notFound() }
            return encode(session)

        case ("GET", let id?, "insights"):
            guard let index = MockAPI.sessions.firstIndex(where: { $0.sessionID == id }) else { return notFound() }
            return encode(MockAPI.insights(for: MockAPI.sessions[index], index: index))

        case ("POST", let id?, "insights") where parts.count > 6 && parts[6] == "generate":
            guard MockAPI.sessions.contains(where: { $0.sessionID == id }) else { return notFound() }
            return encode(MockAPI.startGeneration(for: id))

        case ("GET", _?, "messages"):
            return encode(Page<SessionMessage>(items: []))

        case ("GET", _?, "attachments"):
            return encode(Page<SessionAttachment>(items: []))

        default:
            return notFound()
        }
    }

    /// URLProtocol hands us the body as a stream, not `httpBody`.
    private static func body(of request: URLRequest) -> Data? {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return nil }
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
