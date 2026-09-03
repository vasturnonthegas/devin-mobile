import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Minimal abstraction over URLSession so the client can be tested without network access.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DevinError.transport("Non-HTTP response")
        }
        return (data, http)
    }
}

#if canImport(FoundationNetworking)
// swift-corelibs-foundation does not ship the async `data(for:)` overload.
extension URLSession {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, let response {
                    continuation.resume(returning: (data, response))
                } else {
                    continuation.resume(throwing: DevinError.transport("Empty response"))
                }
            }
            task.resume()
        }
    }
}
#endif
