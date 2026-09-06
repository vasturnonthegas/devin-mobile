import AppIntents
import DevinKit
import Foundation

/// "Ask Devin to …" — `POST …/sessions` with a prompt and an optional repository.
struct StartDevinSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Devin Session"
    static let description = IntentDescription(
        "Starts a new Devin session from a prompt, optionally scoped to a repository.",
        categoryName: "Sessions",
        resultValueName: "Session"
    )

    @Parameter(title: "Prompt", description: "What Devin should do.",
               inputOptions: String.IntentInputOptions(multiline: true),
               requestValueDialog: "What should Devin do?")
    var prompt: String

    @Parameter(title: "Repository", description: "Optional. owner/repo or github.com/owner/repo.",
               inputOptions: String.IntentInputOptions(capitalizationType: .none, autocorrect: false))
    var repo: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Ask Devin to \(\.$prompt)") {
            \.$repo
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<SessionEntity> & ProvidesDialog {
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { throw DevinIntentError.emptyPrompt }

        var repos: [String]?
        if let repo, !repo.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let path = Repository.typedPath(repo) else { throw DevinIntentError.invalidRepository(repo) }
            repos = [path]
        }

        let devin = try SignedInDevin.current()
        let session = SessionEntity(try await devin.createSession(NewSessionRequest(prompt: prompt, repos: repos)))
        let dialog: IntentDialog = repos == nil
            ? "Started “\(session.title)”. Devin is on it."
            : "Started “\(session.title)” in \(repos?.first ?? ""). Devin is on it."
        return .result(value: session, dialog: dialog)
    }
}
