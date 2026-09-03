import Foundation

/// RFC 9457 problem body returned by the v3 API on errors.
public struct ProblemDetail: Codable, Hashable, Sendable {
    public let status: Int?
    public let title: String?
    public let detail: String?

    public init(status: Int?, title: String?, detail: String?) {
        self.status = status
        self.title = title
        self.detail = detail
    }
}

public enum DevinError: Error, Sendable, Equatable {
    case unauthorized(ProblemDetail?)
    case forbidden(ProblemDetail?)
    case notFound(ProblemDetail?)
    case rateLimited(retryAfter: TimeInterval?)
    case http(status: Int, problem: ProblemDetail?)
    case decoding(String)
    case transport(String)
    case missingOrganization

    public var isAuthFailure: Bool {
        switch self {
        case .unauthorized, .forbidden: true
        default: false
        }
    }
}

extension DevinError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unauthorized(let p): p?.detail ?? "Invalid or expired token."
        case .forbidden(let p): p?.detail ?? "This token doesn't have permission for that."
        case .notFound(let p): p?.detail ?? "Not found."
        case .rateLimited: "Rate limited — try again in a moment."
        case .http(let status, let p): p?.detail ?? p?.title ?? "Request failed (HTTP \(status))."
        case .decoding(let msg): "Unexpected response: \(msg)"
        case .transport(let msg): msg
        case .missingOrganization: "This token isn't tied to an organization. Enter your org ID (Settings → Devin API)."
        }
    }
}
