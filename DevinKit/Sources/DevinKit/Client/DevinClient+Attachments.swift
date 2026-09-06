import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: Attachment upload

public extension DevinClient {
    /// Uploads a file as a multipart `file` part. Pass the returned `url` in `attachment_urls`
    /// when sending a message or creating a session.
    func upload(data: Data, filename: String, mime: String, org: String) async throws -> UploadedAttachment {
        var form = MultipartFormData()
        form.appendFile(name: "file", filename: filename, mimeType: mime, data: data)

        var request = makeRequest(.post, "/v3/organizations/\(org)/attachments")
        request.httpBody = form.encoded()
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")

        let response = try await perform(request)
        return try decode(response)
    }
}

// MARK: Attachment download

public extension DevinClient {
    /// Where an attachment's bytes are fetched from. Relative `url` values are resolved against the API base URL.
    func downloadURL(for attachment: SessionAttachment) -> URL {
        if attachment.url.host != nil { return attachment.url }
        return URL(string: attachment.url.absoluteString, relativeTo: baseURL)?.absoluteURL ?? attachment.url
    }

    /// Raw bytes of an attachment.
    ///
    /// URLs on the API host are fetched with the Bearer token; the API answers with a 307 to a short-lived
    /// presigned URL, which URLSession follows *without* forwarding the Authorization header. URLs on any
    /// other host are fetched anonymously so the token never leaves the API.
    func attachmentData(_ attachment: SessionAttachment) async throws -> Data {
        let url = downloadURL(for: attachment)
        var request: URLRequest
        if url.host == baseURL.host, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            request = makeRequest(.get, components.path, query: components.queryItems ?? [])
        } else {
            request = URLRequest(url: url)
            request.setValue("DevinMobile/\(DevinKitVersion.string)", forHTTPHeaderField: "User-Agent")
        }
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        return try await perform(request)
    }
}

/// The spec documents `GET …/sessions/{id}/attachments` as a bare array; older builds assumed the
/// cursor envelope, so both shapes decode.
struct SessionAttachmentList: Decodable {
    let items: [SessionAttachment]

    init(from decoder: Decoder) throws {
        if let array = try? decoder.singleValueContainer().decode([SessionAttachment].self) {
            items = array
        } else {
            items = try decoder.container(keyedBy: CodingKeys.self).decode([SessionAttachment].self, forKey: .items)
        }
    }

    private enum CodingKeys: String, CodingKey { case items }
}
