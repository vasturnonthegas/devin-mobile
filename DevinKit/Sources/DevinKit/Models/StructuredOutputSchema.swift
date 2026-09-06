import Foundation

/// Validates caller-typed text for `NewSessionRequest.structuredOutputSchema`.
///
/// The spec constrains `structured_output_schema` to a JSON object (Draft 7 schema) of at most
/// 64 KB that is self-contained — every `$ref` must be local (`#...`). Anything else is rejected
/// by the API with a 400, so it is checked here first and surfaced before the request is sent.
public enum StructuredOutputSchema {
    public static let maxBytes = 64 * 1024

    public enum ValidationError: Error, Equatable, Sendable {
        case notJSON(detail: String?)
        case notObject
        case tooLarge(bytes: Int)
        case externalReference(String)
    }

    /// Parses `text` into the value to send. Whitespace-only input is the caller's "not set".
    public static func parse(_ text: String) throws -> JSONValue {
        let data = Data(text.utf8)
        guard data.count <= maxBytes else { throw ValidationError.tooLarge(bytes: data.count) }
        // JSONSerialization is the strict parser (JSONDecoder tolerates trailing commas) and the
        // only one that reports where the text went wrong.
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            let debug = (error as NSError).userInfo["NSDebugDescription"] as? String
            throw ValidationError.notJSON(detail: debug.flatMap { $0.isEmpty ? nil : $0 })
        }
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            throw ValidationError.notJSON(detail: nil)
        }
        guard case .object = value else { throw ValidationError.notObject }
        if let ref = firstExternalReference(in: value) { throw ValidationError.externalReference(ref) }
        return value
    }

    private static func firstExternalReference(in value: JSONValue) -> String? {
        switch value {
        case .object(let members):
            if case .string(let ref)? = members["$ref"], !ref.hasPrefix("#") { return ref }
            for key in members.keys.sorted() {
                if let found = firstExternalReference(in: members[key]!) { return found }
            }
            return nil
        case .array(let items):
            for item in items {
                if let found = firstExternalReference(in: item) { return found }
            }
            return nil
        default:
            return nil
        }
    }
}

extension StructuredOutputSchema.ValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notJSON(let detail):
            if let detail { return "Schema is not valid JSON: \(detail)" }
            return "Schema is not valid JSON."
        case .notObject:
            return "Schema must be a JSON object."
        case .tooLarge(let bytes):
            return "Schema is \(bytes / 1024) KB; the limit is \(StructuredOutputSchema.maxBytes / 1024) KB."
        case .externalReference(let ref):
            return "Schema must be self-contained; external $ref \"\(ref)\" is not allowed."
        }
    }
}
