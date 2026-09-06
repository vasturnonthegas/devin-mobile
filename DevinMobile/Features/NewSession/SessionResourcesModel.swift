import Foundation
import Observation
import DevinKit

/// Knowledge notes and secrets the user can attach to a session being created. Both lists are
/// fetched once per sheet; a 403 on either endpoint hides that list for the sheet's lifetime
/// (RBAC-gated service keys) instead of surfacing an error. Secret values never exist client-side —
/// `OrgSecret` has no field for them.
@Observable
@MainActor
final class SessionResourcesModel {
    enum LoadState: Equatable, Sendable {
        case loading
        case loaded
        case forbidden
        case failed(String)
    }

    struct NoteGroup: Identifiable, Hashable {
        let folder: String
        let notes: [KnowledgeNote]
        var id: String { folder }
    }

    let store: SessionStore

    private(set) var notes: [KnowledgeNote] = []
    private(set) var folders: [KnowledgeFolder] = []
    private(set) var secrets: [OrgSecret] = []
    private(set) var knowledgeState: LoadState = .loading
    private(set) var secretsState: LoadState = .loading

    init(store: SessionStore) {
        self.store = store
    }

    var showsKnowledge: Bool { knowledgeState != .forbidden }
    var showsSecrets: Bool { secretsState != .forbidden }
    /// The whole section disappears only when neither list is permitted.
    var isHidden: Bool { !showsKnowledge && !showsSecrets }

    func load() async {
        async let knowledge: Void = loadKnowledge()
        async let secretList: Void = loadSecrets()
        _ = await (knowledge, secretList)
    }

    func loadKnowledge() async {
        knowledgeState = .loading
        let client = store.client
        let org = store.orgID
        do {
            async let noteList = client.allKnowledgeNotes(org: org)
            // Folder ordering is cosmetic; a failure there must not hide the notes.
            async let tree = try? client.knowledgeFolders(org: org)
            notes = try await noteList
            folders = await tree?.folders ?? []
            knowledgeState = .loaded
        } catch DevinError.forbidden {
            knowledgeState = .forbidden
        } catch {
            knowledgeState = .failed(error.localizedDescription)
        }
    }

    func loadSecrets() async {
        secretsState = .loading
        do {
            secrets = try await store.client.allSecrets(org: store.orgID)
            secretsState = .loaded
        } catch DevinError.forbidden {
            secretsState = .forbidden
        } catch {
            secretsState = .failed(error.localizedDescription)
        }
    }

    func note(id: String) -> KnowledgeNote? { notes.first { $0.noteID == id } }
    func secret(id: String) -> OrgSecret? { secrets.first { $0.secretID == id } }

    /// Notes matching `search`, grouped by folder. Root notes come first, then folders in the
    /// server's tree order (falling back to path order for folders the tree didn't list).
    func noteGroups(matching search: String) -> [NoteGroup] {
        var byFolder: [String: [KnowledgeNote]] = [:]
        for note in notes where note.matches(search) {
            byFolder[note.folderPath, default: []].append(note)
        }
        var order: [String] = [""]
        order += folders.map(\.path)
        order += byFolder.keys.filter { !order.contains($0) }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return order.compactMap { path in
            guard let group = byFolder[path], !group.isEmpty else { return nil }
            let sorted = group.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            return NoteGroup(folder: path.isEmpty ? KnowledgeNote.rootFolderName : path, notes: sorted)
        }
    }

    func secrets(matching search: String) -> [OrgSecret] {
        secrets
            .filter { $0.matches(search) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}
