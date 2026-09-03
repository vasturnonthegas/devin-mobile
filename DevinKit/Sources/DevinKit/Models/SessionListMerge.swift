import Foundation

public extension Array where Element == Session {
    /// Upserts `incoming` by `sessionID`: rows already present are replaced in place, unseen
    /// rows are appended. With `pruneMissing`, rows absent from `incoming` are dropped — only
    /// valid when `incoming` is the complete known set (a first page with nothing loaded past it).
    func merging(_ incoming: [Session], pruneMissing: Bool = false) -> [Session] {
        let incomingIDs = Set(incoming.map(\.sessionID))
        var merged = pruneMissing ? filter { incomingIDs.contains($0.sessionID) } : self
        var indexByID = Dictionary(merged.enumerated().map { ($1.sessionID, $0) }, uniquingKeysWith: { first, _ in first })
        for session in incoming {
            if let index = indexByID[session.sessionID] {
                merged[index] = session
            } else {
                indexByID[session.sessionID] = merged.count
                merged.append(session)
            }
        }
        return merged
    }
}
