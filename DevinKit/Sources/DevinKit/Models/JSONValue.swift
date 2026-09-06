import Foundation

/// Opaque JSON value. The API returns `structured_output` as a free-form object whose shape is
/// dictated by the caller's `structured_output_schema`, so it is decoded verbatim rather than typed.
public indirect enum JSONValue: Hashable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let value = try? c.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? c.decode(Double.self) {
            self = .number(value)
        } else if let value = try? c.decode(String.self) {
            self = .string(value)
        } else if let value = try? c.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? c.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Not a JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let members): try c.encode(members)
        case .array(let items): try c.encode(items)
        case .string(let value): try c.encode(value)
        case .number(let value): try c.encode(value)
        case .bool(let value): try c.encode(value)
        case .null: try c.encodeNil()
        }
    }
}

public extension JSONValue {
    subscript(key: String) -> JSONValue? {
        if case .object(let members) = self { return members[key] }
        return nil
    }

    subscript(index: Int) -> JSONValue? {
        if case .array(let items) = self, items.indices.contains(index) { return items[index] }
        return nil
    }

    var isContainer: Bool {
        switch self {
        case .object, .array: true
        default: false
        }
    }

    /// Object members sorted by key, so tree views and pretty output are stable across decodes.
    var sortedMembers: [(key: String, value: JSONValue)] {
        guard case .object(let members) = self else { return [] }
        return members.sorted { $0.key < $1.key }.map { (key: $0.key, value: $0.value) }
    }

    /// Two-space indented JSON with sorted keys. Integral numbers print without a fraction.
    var prettyPrinted: String {
        var out = ""
        write(to: &out, indent: 0)
        return out
    }

    /// Single-line rendering of a scalar; containers collapse to a size summary.
    var scalarDescription: String {
        switch self {
        case .object(let members): "{\(members.count)}"
        case .array(let items): "[\(items.count)]"
        case .string(let value): value
        case .number(let value): Self.format(value)
        case .bool(let value): value ? "true" : "false"
        case .null: "null"
        }
    }

    private func write(to out: inout String, indent: Int) {
        let pad = String(repeating: "  ", count: indent)
        let innerPad = String(repeating: "  ", count: indent + 1)
        switch self {
        case .object(let members):
            guard !members.isEmpty else { return out += "{}" }
            out += "{\n"
            for (offset, entry) in sortedMembers.enumerated() {
                out += innerPad
                out += Self.quote(entry.key)
                out += ": "
                entry.value.write(to: &out, indent: indent + 1)
                out += offset == members.count - 1 ? "\n" : ",\n"
            }
            out += pad + "}"
        case .array(let items):
            guard !items.isEmpty else { return out += "[]" }
            out += "[\n"
            for (offset, item) in items.enumerated() {
                out += innerPad
                item.write(to: &out, indent: indent + 1)
                out += offset == items.count - 1 ? "\n" : ",\n"
            }
            out += pad + "]"
        case .string(let value):
            out += Self.quote(value)
        case .number(let value):
            out += Self.format(value)
        case .bool(let value):
            out += value ? "true" : "false"
        case .null:
            out += "null"
        }
    }

    private static func format(_ value: Double) -> String {
        if value.isFinite, value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        return String(value)
    }

    private static func quote(_ string: String) -> String {
        var out = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where scalar.value < 0x20:
                out += String(format: "\\u%04x", scalar.value)
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
}
