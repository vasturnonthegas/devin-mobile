import Foundation

/// The API doesn't expose which repos a session used, so remember what the user typed.
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
