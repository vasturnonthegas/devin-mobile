import Foundation

public struct DevinCredentials: Codable, Hashable, Sendable {
    public var token: String
    public var orgID: String
    public var displayName: String?

    public init(token: String, orgID: String, displayName: String? = nil) {
        self.token = token
        self.orgID = orgID
        self.displayName = displayName
    }
}

public protocol CredentialStore: Sendable {
    func load() throws -> DevinCredentials?
    func save(_ credentials: DevinCredentials) throws
    func clear() throws
}

/// Non-persistent store for tests and previews.
public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: DevinCredentials?

    public init(_ value: DevinCredentials? = nil) {
        self.value = value
    }

    public func load() throws -> DevinCredentials? {
        lock.withLock { value }
    }

    public func save(_ credentials: DevinCredentials) throws {
        lock.withLock { value = credentials }
    }

    public func clear() throws {
        lock.withLock { value = nil }
    }
}
