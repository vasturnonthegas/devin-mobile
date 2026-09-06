import Foundation
import DevinKit

extension SessionStore {
    /// Mirrors the inbox into the App Group after each successful refresh so widgets and background
    /// refresh can show last-known buckets without calling the API. Only the unfiltered list is
    /// recorded: a filtered page would under-count "Needs you".
    func publishSnapshot() {
        guard filter.isEmpty else { return }
        try? SessionSnapshot(sessions: sessions).save()
    }
}
