import Foundation

public extension SessionSnapshot {
    /// One or two sentences answering "what is Devin waiting on?", written to be read aloud by Siri
    /// and shown as an intent dialog. Names at most `spokenTitleLimit` sessions; the rest are counted.
    static let spokenTitleLimit = 3

    var spokenSummary: String {
        let waiting = entries(in: .needsYou)
        guard !waiting.isEmpty else {
            return "Nothing is waiting on you right now. " + workingSentence
        }
        let named = waiting.prefix(Self.spokenTitleLimit).map { "“\($0.title)” (\($0.statusSummary.lowercased()))" }
        let list = Self.spokenList(named)
        switch waiting.count {
        case 1:
            return "One session needs you: \(list)."
        case ...Self.spokenTitleLimit:
            return "\(waiting.count) sessions need you: \(list)."
        default:
            return "\(waiting.count) sessions need you, including \(list)."
        }
    }

    private var workingSentence: String {
        switch count(.working) {
        case 0: "Devin isn't working on anything."
        case 1: "Devin is working on one session."
        case let n: "Devin is working on \(n) sessions."
        }
    }

    /// "a", "a and b", "a, b and c".
    static func spokenList(_ items: [String]) -> String {
        guard items.count > 1, let last = items.last else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + last
    }
}
