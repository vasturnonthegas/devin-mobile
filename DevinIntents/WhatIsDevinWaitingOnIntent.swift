import AppIntents
import DevinKit
import Foundation

/// "What is Devin waiting on?" — one poll of page 1, spoken as `SessionSnapshot.spokenSummary`.
/// When the API can't be reached but a snapshot exists, that snapshot is read out with its age
/// instead of failing: a stale answer beats none for a glance from the lock screen.
struct WhatIsDevinWaitingOnIntent: AppIntent {
    static let title: LocalizedStringResource = "What Is Devin Waiting On"
    static let description = IntentDescription(
        "Tells you which sessions need your reply or approval, and how many Devin is working on.",
        categoryName: "Sessions",
        resultValueName: "Sessions Needing You"
    )

    func perform() async throws -> some IntentResult & ReturnsValue<[SessionEntity]> & ProvidesDialog {
        let devin = try SignedInDevin.current()
        let snapshot: SessionSnapshot
        let dialog: IntentDialog
        do {
            snapshot = try await devin.refreshSnapshot()
            dialog = "\(snapshot.spokenSummary)"
        } catch let error as DevinIntentError {
            // Only transport/server failures fall back; a rejected token must be heard.
            guard case .request = error, let saved = SessionSnapshot.load() else { throw error }
            snapshot = saved
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let age = formatter.localizedString(for: saved.capturedAt, relativeTo: .now)
            dialog = "I couldn't reach Devin, so this is from \(age). \(saved.spokenSummary)"
        }
        return .result(value: snapshot.entries(in: .needsYou).map(SessionEntity.init), dialog: dialog)
    }
}
