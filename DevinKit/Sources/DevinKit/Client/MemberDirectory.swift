import Foundation

/// In-memory `user_id` → `OrgMember` cache backed by the members endpoint.
///
/// The directory is fetched at most once per instance; concurrent lookups share the in-flight
/// request. A 403 marks the directory `.forbidden` permanently (PATs and service users without
/// the members permission), so callers can hide owner UI instead of retrying every poll.
public actor MemberDirectory {
    public enum Availability: Sendable, Equatable {
        case unknown
        case available
        case forbidden
    }

    private let client: DevinClient
    private let org: String
    private var byID: [String: OrgMember] = [:]
    private var availability: Availability = .unknown
    private var loading: Task<Result<[OrgMember], DevinError>, Never>?

    public init(client: DevinClient, org: String) {
        self.client = client
        self.org = org
    }

    public var state: Availability { availability }

    public var members: [OrgMember] {
        byID.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Resolves a member, fetching the directory on first use. `nil` when unknown or forbidden.
    public func member(id: String) async -> OrgMember? {
        if let hit = byID[id] { return hit }
        guard await load() == .available else { return nil }
        return byID[id]
    }

    /// Fetches the directory once. Transport/server failures leave the state `.unknown` so the
    /// next call retries; `.forbidden` is sticky.
    @discardableResult
    public func load() async -> Availability {
        if availability != .unknown { return availability }
        if let loading { return apply(await loading.value) }

        let task = Task<Result<[OrgMember], DevinError>, Never> { [client, org] in
            do {
                return .success(try await client.allMembers(org: org))
            } catch let error as DevinError {
                return .failure(error)
            } catch {
                return .failure(.transport(error.localizedDescription))
            }
        }
        loading = task
        let result = apply(await task.value)
        loading = nil
        return result
    }

    private func apply(_ result: Result<[OrgMember], DevinError>) -> Availability {
        switch result {
        case .success(let members):
            byID = Dictionary(members.map { ($0.userID, $0) }, uniquingKeysWith: { _, last in last })
            availability = .available
        case .failure(.forbidden):
            availability = .forbidden
        case .failure:
            break
        }
        return availability
    }
}
