import Foundation

/// Arbitrary JSON, decoded without assuming a schema.
///
/// Grok Bot's local cache format is internal and may change between releases,
/// so BotPeek decodes it into this type and extracts fields defensively instead
/// of relying on strict `Decodable` models that would fail on any change.
public enum JSONValue: Equatable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

public extension JSONValue {
    static func parse(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// A string for identifiers that may be stored as either strings or numbers.
    var identifierString: String? {
        switch self {
        case .string(let value): return value.isEmpty ? nil : value
        case .number(let value) where value.rounded() == value: return String(Int64(value))
        default: return nil
        }
    }

    /// `true` for values that carry no meaning as a signal: null, false, empty
    /// strings, empty objects and empty arrays.
    var isEmptySignal: Bool {
        switch self {
        case .null: return true
        case .bool(let value): return !value
        case .string(let value): return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .object(let value): return value.isEmpty
        case .array(let value): return value.isEmpty
        case .number: return false
        }
    }

    /// Deterministic serialization with sorted keys, used for fingerprints.
    var canonicalString: String {
        switch self {
        case .null: return "null"
        case .bool(let value): return value ? "true" : "false"
        case .number(let value): return String(value)
        case .string(let value): return "\"" + value.replacingOccurrences(of: "\"", with: "\\\"") + "\""
        case .array(let values): return "[" + values.map(\.canonicalString).joined(separator: ",") + "]"
        case .object(let object):
            let body = object.keys.sorted().map { key in
                "\"\(key)\":" + (object[key]?.canonicalString ?? "null")
            }
            return "{" + body.joined(separator: ",") + "}"
        }
    }
}

/// Stable, platform-independent 64-bit FNV-1a hash rendered as hex.
public enum StableHash {
    public static func fnv1a(_ string: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }
}
