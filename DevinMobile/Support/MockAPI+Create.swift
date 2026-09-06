#if DEBUG
import Foundation
import DevinKit

/// The attachment side of `POST …/sessions`. `MockAPI.create(prompt:)` owns the session itself; this
/// remembers what was uploaded and which URLs each created session was started with, so its transcript
/// quotes them (as the real API does) and `GET …/attachments` lists exactly those files.
extension MockAPI {
    static let uploads = MockUploads()

    final class MockUploads: @unchecked Sendable {
        struct Upload {
            let name: String
            let mime: String
            let data: Data
        }

        private let lock = NSLock()
        private var uploads: [String: Upload] = [:]
        private var attachmentURLs: [String: [URL]] = [:]
        private var prompts: [String: String] = [:]

        func upload(uuid: String) -> Upload? { lock.withLock { uploads[uuid] } }
        func attachmentURLs(for sessionID: String) -> [URL]? { lock.withLock { attachmentURLs[sessionID] } }
        func prompt(for sessionID: String) -> String? { lock.withLock { prompts[sessionID] } }

        fileprivate func store(_ upload: Upload, uuid: String) {
            lock.withLock { uploads[uuid] = upload }
        }

        fileprivate func store(prompt: String, attachmentURLs urls: [URL], for sessionID: String) {
            lock.withLock {
                prompts[sessionID] = prompt
                attachmentURLs[sessionID] = urls
            }
        }
    }

    static func createSession(body: Data?) -> Session {
        struct Body: Decodable {
            let prompt: String
            let attachmentURLs: [URL]?
            enum CodingKeys: String, CodingKey {
                case prompt
                case attachmentURLs = "attachment_urls"
            }
        }
        let request = body.flatMap { try? JSONDecoder().decode(Body.self, from: $0) }
        let session = create(prompt: request?.prompt ?? "New session")
        uploads.store(prompt: request?.prompt ?? "New session", attachmentURLs: request?.attachmentURLs ?? [], for: session.sessionID)
        return session
    }

    /// Parses the single `file` part of a `multipart/form-data` body and keeps the bytes so the
    /// detail screen can download what was just uploaded.
    static func storeUpload(body: Data?, contentType: String?) -> UploadedAttachment {
        let uuid = UUID().uuidString.lowercased()
        let part = body.flatMap { multipartFilePart($0, contentType: contentType) }
        let name = part?.name ?? "upload.bin"
        uploads.store(MockUploads.Upload(name: name, mime: part?.mime ?? "application/octet-stream", data: part?.data ?? Data()), uuid: uuid)
        let escaped = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "upload.bin"
        return UploadedAttachment(
            attachmentID: "att-\(uuid.prefix(8))",
            name: name,
            url: URL(string: "https://api.devin.ai/v3/organizations/org-mock/attachments/\(uuid)/\(escaped)")!
        )
    }

    static func uploadedBody(uuid: String, name: String) -> Data? {
        uploads.upload(uuid: uuid).flatMap { $0.name == name ? $0.data : nil }
    }

    /// Transcript of a session created this launch: the prompt quoting every attachment URL, then one
    /// Devin reply. nil for catalogue sessions.
    static func createdMessages(for sessionID: String) -> [SessionMessage]? {
        guard let prompt = uploads.prompt(for: sessionID), let session = session(id: sessionID) else { return nil }
        var text = prompt
        if let urls = uploads.attachmentURLs(for: sessionID), !urls.isEmpty {
            text += "\n\n" + urls.map(\.absoluteString).joined(separator: "\n")
        }
        return [
            SessionMessage(eventID: "\(sessionID)-m1", source: .user, message: text, createdAt: session.createdAt),
            SessionMessage(eventID: "\(sessionID)-m2", source: .devin,
                           message: "On it — setting up the workspace and reading the attachments.",
                           createdAt: session.createdAt.addingTimeInterval(5)),
        ]
    }

    static func createdAttachmentsJSON(for sessionID: String) -> Data? {
        guard let urls = uploads.attachmentURLs(for: sessionID) else { return nil }
        let items = urls.compactMap { url -> String? in
            let parts = url.pathComponents.filter { $0 != "/" }
            guard parts.count >= 6, let upload = uploads.upload(uuid: parts[4]) else { return nil }
            return #"{"attachment_id":"att-\#(parts[4].prefix(8))","name":"\#(upload.name)","source":"user","url":"\#(url.absoluteString)","content_type":"\#(upload.mime)"}"#
        }
        return Data("[\(items.joined(separator: ","))]".utf8)
    }

    private static func multipartFilePart(_ body: Data, contentType: String?) -> (name: String, mime: String, data: Data)? {
        guard let boundary = contentType?.components(separatedBy: "boundary=").last, !boundary.isEmpty,
              let headerEnd = body.range(of: Data("\r\n\r\n".utf8)),
              let headers = String(data: body[body.startIndex..<headerEnd.lowerBound], encoding: .utf8),
              let closing = body.range(of: Data("\r\n--\(boundary)".utf8), in: headerEnd.upperBound..<body.endIndex)
        else { return nil }
        let name = headers.components(separatedBy: "filename=\"").last?.components(separatedBy: "\"").first ?? "upload.bin"
        let mime = headers.components(separatedBy: "Content-Type: ").last?.components(separatedBy: "\r\n").first ?? "application/octet-stream"
        return (name, mime, Data(body[headerEnd.upperBound..<closing.lowerBound]))
    }
}
#endif
