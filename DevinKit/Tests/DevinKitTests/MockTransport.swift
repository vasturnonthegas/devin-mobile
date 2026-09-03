import Foundation
@testable import DevinKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class MockTransport: HTTPTransport, @unchecked Sendable {
    struct Stub {
        let status: Int
        let body: Data
        let headers: [String: String]
    }

    private let lock = NSLock()
    private var stubs: [Stub] = []
    private(set) var requests: [URLRequest] = []

    func stub(_ status: Int = 200, json: String, headers: [String: String] = [:]) {
        lock.withLock { stubs.append(Stub(status: status, body: Data(json.utf8), headers: headers)) }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let stub: Stub = lock.withLock {
            requests.append(request)
            precondition(!stubs.isEmpty, "No stub for \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "")")
            return stubs.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: stub.headers)!
        return (stub.body, response)
    }

    var lastRequest: URLRequest { requests.last! }
}

extension URLRequest {
    var bodyJSON: [String: Any] {
        guard let httpBody else { return [:] }
        return (try? JSONSerialization.jsonObject(with: httpBody)) as? [String: Any] ?? [:]
    }
}
