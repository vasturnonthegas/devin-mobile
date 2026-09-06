#if DEBUG
import Foundation
import DevinKit

/// Knowledge notes, folders and secret metadata for the New Session pickers. Launch with
/// `-MockForbidKnowledge` / `-MockForbidSecrets` to have the corresponding route answer 403 and
/// exercise the "hide the section" path.
extension MockAPI {
    static let knowledgeFolders = KnowledgeFolderTree(
        folders: [
            KnowledgeFolder(folderID: "folder-eng", name: "Engineering", path: "Engineering", noteCount: 2),
            KnowledgeFolder(folderID: "folder-ci", name: "CI", parentFolderID: "folder-eng", path: "Engineering/CI", noteCount: 2),
            KnowledgeFolder(folderID: "folder-mobile", name: "Mobile", path: "Mobile", noteCount: 3),
            KnowledgeFolder(folderID: "folder-empty", name: "Archive", path: "Archive", noteCount: 0),
        ],
        rootNoteCount: 2
    )

    static let knowledgeNotes: [KnowledgeNote] = {
        let day: TimeInterval = 86_400
        let base = Date(timeIntervalSince1970: 1_756_900_000)
        func note(_ id: String, _ name: String, folder: String, trigger: String, repo: String? = nil, enabled: Bool = true, daysAgo: Double) -> KnowledgeNote {
            KnowledgeNote(
                noteID: "note-mock-\(id)",
                folderID: knowledgeFolders.folders.first { $0.path == folder }?.folderID,
                folderPath: folder,
                name: name,
                body: "Body of \(name).",
                trigger: trigger,
                isEnabled: enabled,
                pinnedRepo: repo,
                createdAt: base.addingTimeInterval(-daysAgo * day),
                updatedAt: base.addingTimeInterval(-daysAgo * day / 2)
            )
        }
        return [
            note("style", "Code style", folder: "", trigger: "Always", daysAgo: 40),
            note("tone", "Commit message tone", folder: "", trigger: "When writing commit messages", enabled: false, daysAgo: 12),
            note("review", "Review checklist", folder: "Engineering", trigger: "Before opening a PR", daysAgo: 30),
            note("deploy", "Déploiement", folder: "Engineering", trigger: "When touching infra/", daysAgo: 9),
            note("ci", "CI conventions", folder: "Engineering/CI", trigger: "When touching GitHub Actions", repo: "github.com/acme/api", daysAgo: 5),
            note("flaky", "Flaky test triage", folder: "Engineering/CI", trigger: "When a test fails intermittently", daysAgo: 3),
            note("swiftui", "SwiftUI conventions", folder: "Mobile", trigger: "When editing DevinMobile/", repo: "github.com/acme/devin-mobile", daysAgo: 2),
            note("kit", "DevinKit API rules", folder: "Mobile", trigger: "When adding a client method", repo: "github.com/acme/devin-mobile", daysAgo: 1),
            note("a11y", "Accessibility audit", folder: "Mobile", trigger: "When adding a screen", daysAgo: 0.5),
        ]
    }()

    static let secrets: [OrgSecret] = {
        let base = Date(timeIntervalSince1970: 1_756_900_000)
        return [
            OrgSecret(secretID: "secret-mock-npm", key: "NPM_TOKEN", note: "Publish token for @acme", createdBy: "user-mock", createdAt: base, secretType: .keyValue),
            OrgSecret(secretID: "secret-mock-aws", key: "AWS_SECRET_ACCESS_KEY", note: nil, createdBy: "user-mock-2", createdAt: base, secretType: .keyValue),
            OrgSecret(secretID: "secret-mock-gh", key: nil, note: "GitHub session cookie", createdBy: "user-mock", createdAt: base, secretType: .cookie, accessType: .personal),
            OrgSecret(secretID: "secret-mock-otp", key: nil, note: "Okta TOTP", createdBy: "user-mock-3", createdAt: base, secretType: .totp),
            OrgSecret(secretID: "secret-mock-sentry", key: "SENTRY_AUTH_TOKEN", note: "Read-only", isSensitive: false, createdBy: "user-mock", createdAt: base, secretType: .keyValue),
        ]
    }()

    private static let knowledgeEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    /// Handles `GET …/knowledge/notes`, `…/knowledge/folders` and `…/secrets`; nil for every other route.
    static func knowledgeResponse(method: String, parts: [String], url: URL) -> (Int, Data)? {
        guard method == "GET", parts.count >= 4, parts[0] == "v3", parts[1] == "organizations" else { return nil }
        let arguments = ProcessInfo.processInfo.arguments
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        switch Array(parts[3...]) {
        case ["knowledge", "notes"]:
            if arguments.contains("-MockForbidKnowledge") { return forbidden("ViewOrgKnowledge") }
            let search = items.first { $0.name == "search" }?.value ?? ""
            let folder = items.first { $0.name == "folder_path" }?.value
            let notes = knowledgeNotes.filter { $0.matches(search) && (folder == nil || $0.folderPath == folder) }
            return encode(Page(items: notes, total: notes.count))
        case ["knowledge", "folders"]:
            if arguments.contains("-MockForbidKnowledge") { return forbidden("ViewOrgKnowledge") }
            return encode(knowledgeFolders)
        case ["secrets"]:
            if arguments.contains("-MockForbidSecrets") { return forbidden("ViewOrgSecrets") }
            return encode(Page(items: secrets, total: secrets.count))
        default:
            return nil
        }
    }

    private static func encode<T: Encodable>(_ value: T) -> (Int, Data) {
        (200, (try? knowledgeEncoder.encode(value)) ?? Data())
    }

    private static func forbidden(_ permission: String) -> (Int, Data) {
        (403, Data(#"{"status":403,"title":"Forbidden","detail":"Missing permission: \#(permission)","type":"about:blank"}"#.utf8))
    }
}
#endif
