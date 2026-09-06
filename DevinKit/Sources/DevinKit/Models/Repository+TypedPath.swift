import Foundation

public extension Repository {
    /// Turns a typed or spoken repository reference into the shape `NewSessionRequest.repos`
    /// accepts: scheme, `.git` and trailing slashes are dropped (`https://github.com/o/r.git/` →
    /// `github.com/o/r`), `owner/repo` passes through unchanged. Returns nil unless the result
    /// has at least an `owner/repo` pair with no whitespace.
    static func typedPath(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://"] where s.lowercased().hasPrefix(prefix) {
            s.removeFirst(prefix.count)
        }
        while s.hasSuffix("/") { s.removeLast() }
        if s.lowercased().hasSuffix(".git") { s.removeLast(4) }
        let parts = s.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty }), !s.contains(where: \.isWhitespace) else { return nil }
        return s
    }
}
