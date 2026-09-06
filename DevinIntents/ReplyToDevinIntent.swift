import AppIntents
import DevinKit
import Foundation

/// "Reply to Devin" — `POST …/sessions/{id}/messages`. The session is re-fetched first so the
/// dialog can say whether the message was delivered or is waking a sleeping session, and so an
/// `exit`/`error` session is refused with the same explanation the app's composer shows.
struct ReplyToDevinIntent: AppIntent {
    static let title: LocalizedStringResource = "Reply to Devin"
    static let description = IntentDescription(
        "Sends a message to one of your Devin sessions. Messaging a sleeping session wakes it.",
        categoryName: "Sessions"
    )

    @Parameter(title: "Session", requestValueDialog: "Which session?")
    var session: SessionEntity

    @Parameter(title: "Message", inputOptions: String.IntentInputOptions(multiline: true),
               requestValueDialog: "What should I tell Devin?")
    var message: String

    static var parameterSummary: some ParameterSummary {
        Summary("Send \(\.$message) to \(\.$session)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { throw DevinIntentError.emptyMessage }

        let devin = try SignedInDevin.current()
        let current = try await devin.session(id: session.id)
        let title = current.displayTitle
        let wakes: Bool
        switch current.messaging {
        case .active: wakes = false
        case .wakesSession: wakes = true
        case .unavailable(let reason): throw DevinIntentError.cannotMessage(title: title, reason: reason)
        }

        try await devin.send(message, to: current.id)
        return .result(dialog: wakes
            ? "Sent. “\(title)” was asleep, so your message is waking it up."
            : "Sent to “\(title)”.")
    }
}
