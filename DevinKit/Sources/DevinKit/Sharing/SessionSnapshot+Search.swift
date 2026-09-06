import Foundation

public extension SessionSnapshot {
    /// Entries whose title (or id) contains every whitespace-separated word of `query`,
    /// case- and diacritic-insensitively; inbox order is kept. An empty query returns every entry.
    /// Used by Siri / Shortcuts to resolve a spoken session name without hitting the API.
    func entries(matching query: String) -> [Entry] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return entries }
        return entries.filter { entry in
            words.allSatisfy { word in
                entry.title.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                    || entry.id.range(of: word, options: .caseInsensitive) != nil
            }
        }
    }

    func entry(id: String) -> Entry? {
        entries.first { $0.id == id }
    }
}
