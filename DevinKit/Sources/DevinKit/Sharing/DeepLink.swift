import Foundation

/// `devinmobile://` URLs the app accepts. Extensions build them with `url`; the app parses with `init(url:)`.
///
/// `devinmobile://session/<id>` — open a session (pushed onto the inbox stack once signed in).
public enum DeepLink: Hashable, Sendable {
    case session(id: String)

    public static let scheme = "devinmobile"

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        // `devinmobile://session/<id>` parses with host "session" and path "/<id>";
        // `devinmobile:///session/<id>` parses with an empty host. Accept both.
        var parts = components.path.split(separator: "/").map(String.init)
        if let host = components.host, !host.isEmpty {
            parts.insert(host, at: 0)
        }
        switch parts.first {
        case "session":
            guard parts.count == 2, !parts[1].isEmpty else { return nil }
            self = .session(id: parts[1])
        default:
            return nil
        }
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .session(let id):
            components.host = "session"
            components.path = "/" + id
        }
        return components.url!
    }
}
