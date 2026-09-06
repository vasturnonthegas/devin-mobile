import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Async client for the Devin v3 organization API.
///
/// Authenticates with a Personal Access Token or service-user key (`cog_...`).
/// All session operations are scoped to an organization ID (`org-...`).
public struct DevinClient: Sendable {
    public static let defaultBaseURL = URL(string: "https://api.devin.ai")!

    public let baseURL: URL
    private let token: String
    private let transport: any HTTPTransport
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(token: String, baseURL: URL = DevinClient.defaultBaseURL, transport: any HTTPTransport = URLSessionTransport()) {
        self.token = token
        self.baseURL = baseURL
        self.transport = transport

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                // The API documents integer epoch seconds; tolerate milliseconds too.
                return Date(timeIntervalSince1970: seconds > 1e12 ? seconds / 1000 : seconds)
            }
            let string = try container.decode(String.self)
            if let date = ISO8601DateFormatter.withFractional.date(from: string) ?? ISO8601DateFormatter.plain.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised date: \(string)")
        }
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
    }

    // MARK: Identity

    public func me() async throws -> Principal {
        try await request(.get, "/v3/self")
    }

    // MARK: Sessions

    public func sessions(org: String, query: SessionQuery = SessionQuery()) async throws -> Page<Session> {
        try await request(.get, "/v3/organizations/\(org)/sessions", query: query.queryItems)
    }

    public func session(org: String, id: String) async throws -> Session {
        try await request(.get, "/v3/organizations/\(org)/sessions/\(id)")
    }

    public func createSession(org: String, _ body: NewSessionRequest) async throws -> Session {
        try await request(.post, "/v3/organizations/\(org)/sessions", body: body)
    }

    public func archive(org: String, id: String) async throws -> Session {
        try await request(.post, "/v3/organizations/\(org)/sessions/\(id)/archive")
    }

    public func unarchive(org: String, id: String) async throws -> Session {
        try await request(.post, "/v3/organizations/\(org)/sessions/\(id)/unarchive")
    }

    public func terminate(org: String, id: String, archive: Bool = false) async throws -> Session {
        try await request(.delete, "/v3/organizations/\(org)/sessions/\(id)",
                          query: [URLQueryItem(name: "archive", value: archive ? "true" : "false")])
    }

    // MARK: Messages

    public func messages(org: String, id: String, after: String? = nil, first: Int = 200) async throws -> Page<SessionMessage> {
        var items = [URLQueryItem(name: "first", value: String(first))]
        if let after { items.append(URLQueryItem(name: "after", value: after)) }
        return try await request(.get, "/v3/organizations/\(org)/sessions/\(id)/messages", query: items)
    }

    /// Follows the cursor until the transcript is exhausted.
    public func allMessages(org: String, id: String) async throws -> [SessionMessage] {
        var all: [SessionMessage] = []
        var cursor: String? = nil
        repeat {
            let page = try await messages(org: org, id: id, after: cursor)
            all += page.items
            cursor = page.hasNextPage ? page.endCursor : nil
        } while cursor != nil
        return all
    }

    public func send(message: String, org: String, id: String) async throws {
        struct Body: Encodable { let message: String }
        try await requestIgnoringBody(.post, "/v3/organizations/\(org)/sessions/\(id)/messages", body: Body(message: message))
    }

    public func attachments(org: String, id: String) async throws -> [SessionAttachment] {
        let list: SessionAttachmentList = try await request(.get, "/v3/organizations/\(org)/sessions/\(id)/attachments")
        return list.items
    }

    // MARK: Playbooks

    public func playbooks(org: String, after: String? = nil) async throws -> Page<Playbook> {
        var items = [URLQueryItem(name: "first", value: "100")]
        if let after { items.append(URLQueryItem(name: "after", value: after)) }
        return try await request(.get, "/v3/organizations/\(org)/playbooks", query: items)
    }

    // MARK: Members

    public func members(org: String, after: String? = nil, first: Int = 200) async throws -> Page<OrgMember> {
        var items = [URLQueryItem(name: "first", value: String(first))]
        if let after { items.append(URLQueryItem(name: "after", value: after)) }
        return try await request(.get, "/v3beta1/organizations/\(org)/members/users", query: items)
    }

    /// Follows the cursor until every direct member has been fetched.
    public func allMembers(org: String) async throws -> [OrgMember] {
        var all: [OrgMember] = []
        var cursor: String? = nil
        repeat {
            let page = try await members(org: org, after: cursor)
            all += page.items
            cursor = page.hasNextPage ? page.endCursor : nil
        } while cursor != nil
        return all
    }

    // MARK: - Plumbing

    enum Method: String { case get = "GET", post = "POST", put = "PUT", delete = "DELETE" }

    func makeRequest(_ method: Method, _ path: String, query: [URLQueryItem] = [], bodyData: Data? = nil) -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = path
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!)
        request.httpMethod = method.rawValue
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("DevinMobile/\(DevinKitVersion.string)", forHTTPHeaderField: "User-Agent")
        if let bodyData {
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    func request<Response: Decodable>(_ method: Method, _ path: String, query: [URLQueryItem] = []) async throws -> Response {
        let data = try await perform(makeRequest(method, path, query: query))
        return try decode(data)
    }

    func request<Body: Encodable, Response: Decodable>(_ method: Method, _ path: String, body: Body) async throws -> Response {
        let data = try await perform(makeRequest(method, path, bodyData: try encoder.encode(body)))
        return try decode(data)
    }

    private func requestIgnoringBody<Body: Encodable>(_ method: Method, _ path: String, body: Body) async throws {
        _ = try await perform(makeRequest(method, path, bodyData: try encoder.encode(body)))
    }

    func perform(_ request: URLRequest) async throws -> Data {
        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await transport.send(request)
        } catch let error as DevinError {
            throw error
        } catch {
            throw DevinError.transport(error.localizedDescription)
        }

        guard (200..<300).contains(response.statusCode) else {
            let problem = try? decoder.decode(ProblemDetail.self, from: data)
            switch response.statusCode {
            case 401: throw DevinError.unauthorized(problem)
            case 403: throw DevinError.forbidden(problem)
            case 404: throw DevinError.notFound(problem)
            case 429:
                let retry = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                throw DevinError.rateLimited(retryAfter: retry)
            default: throw DevinError.http(status: response.statusCode, problem: problem)
            }
        }
        return data
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw DevinError.decoding(String(describing: error))
        }
    }
}

public enum DevinKitVersion {
    public static let string = "0.1.0"
}

extension ISO8601DateFormatter {
    static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let plain = ISO8601DateFormatter()
}
