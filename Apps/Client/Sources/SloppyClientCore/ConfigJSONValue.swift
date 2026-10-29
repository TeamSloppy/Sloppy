import Foundation

/// Lossless JSON backing for configuration fields added by newer servers.
public enum ConfigJSONValue: Codable, Sendable, Equatable {
    case object([String: ConfigJSONValue]), array([ConfigJSONValue]), string(String), number(Double), bool(Bool), null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(Double.self) { self = .number(value) }
        else if let value = try? c.decode(String.self) { self = .string(value) }
        else if let value = try? c.decode([String: Self].self) { self = .object(value) }
        else { self = .array(try c.decode([Self].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public static func encoded<T: Encodable>(_ value: T) throws -> Self {
        try JSONDecoder().decode(Self.self, from: JSONEncoder().encode(value))
    }
    public func decoded<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(self))
    }
    public var formatted: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? String(data: encoder.encode(self), encoding: .utf8)) ?? "null"
    }

    /// Apply only edits made by this client; keep unknown object fields and array item metadata.
    public func applyingChanges(from previous: Self, to updated: Self) -> Self {
        guard previous != updated else { return self }
        if case .object(var raw) = self, case .object(let old) = previous, case .object(let new) = updated {
            for key in Set(old.keys).union(new.keys) where old[key] != new[key] {
                if let value = new[key] {
                    raw[key] = raw[key]?.applyingChanges(from: old[key] ?? .null, to: value) ?? value
                } else { raw.removeValue(forKey: key) }
            }
            return .object(raw)
        }
        if case .array(let raw) = self, case .array(let old) = previous, case .array(let new) = updated {
            return .array(new.enumerated().map { index, value in
                let identity = value.identity
                let oldIndex = identity.flatMap { id in old.firstIndex { $0.identity == id } } ?? (identity == nil && index < old.count ? index : nil)
                guard let oldIndex, raw.indices.contains(oldIndex) else { return value }
                return raw[oldIndex].applyingChanges(from: old[oldIndex], to: value)
            })
        }
        return updated
    }
    private var identity: Self? {
        guard case .object(let object) = self else { return nil }
        return object["id"] ?? object["title"]
    }
}
