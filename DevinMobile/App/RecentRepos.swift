import Foundation

/// Cache of the repos most recently used to start a session (host-prefixed `github.com/owner/repo`).
/// Not a source of truth: `RepoPickerModel` lists repositories from the API and only pins these on
/// top; `SessionFilterSheet` offers them as suggestions. The API doesn't expose per-session repos,
/// so this is the only place recency lives. Safe to clear at any time.
enum RecentRepos {
    private static let key = "recentRepos"
    private static let limit = 12

    static func load(defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    static func remember(_ repos: [String], defaults: UserDefaults = .standard) {
        var merged = repos.map(normalize).filter { !$0.isEmpty }
        for existing in load(defaults: defaults) where !merged.contains(existing) {
            merged.append(existing)
        }
        defaults.set(Array(merged.prefix(limit)), forKey: key)
    }

    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://"] where s.hasPrefix(prefix) {
            s.removeFirst(prefix.count)
        }
        if s.hasSuffix(".git") { s.removeLast(4) }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
