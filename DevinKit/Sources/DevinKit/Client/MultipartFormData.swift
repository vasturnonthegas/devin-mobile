import Foundation

/// Builds a `multipart/form-data` body (RFC 7578) with CRLF line endings.
struct MultipartFormData: Sendable {
    let boundary: String
    private var body = Data()

    init(boundary: String = "DevinKit-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func appendFile(name: String, filename: String, mimeType: String, data: Data) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(Self.sanitize(filename))\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.append("\r\n")
    }

    func encoded() -> Data {
        var data = body
        data.append("--\(boundary)--\r\n")
        return data
    }

    /// Filenames go inside a quoted header parameter; quotes, backslashes and line breaks would
    /// terminate or corrupt it, so they are replaced rather than escaped (servers differ on escaping).
    /// Works on scalars because `"\r\n"` is a single `Character`.
    static func sanitize(_ filename: String) -> String {
        var result = String.UnicodeScalarView()
        for scalar in filename.unicodeScalars {
            switch scalar {
            case "\"", "\\", "\r", "\n": result.append("_")
            default: result.append(scalar)
            }
        }
        return result.isEmpty ? "file" : String(result)
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
