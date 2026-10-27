import Foundation

public indirect enum A2UIValue: Codable, Sendable, Equatable {
    case string(String), number(Double), bool(Bool), object([String: A2UIValue]), array([A2UIValue]), null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let v = try? c.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? c.decode(Double.self) {
            self = .number(v)
        } else if let v = try? c.decode(String.self) {
            self = .string(v)
        } else if let v = try? c.decode([String: A2UIValue].self) {
            self = .object(v)
        } else {
            self = .array(try c.decode([A2UIValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    func validate(depth: Int = 0) throws {
        guard depth <= 16 else { throw A2UISurfaceSnapshot.ValidationError.sizeLimit }
        switch self {
        case .object(let values): for value in values.values { try value.validate(depth: depth + 1) }
        case .array(let values): for value in values { try value.validate(depth: depth + 1) }
        default: break
        }
    }

    func replacing(_ tokens: ArraySlice<String>, with value: A2UIValue?) throws -> A2UIValue {
        guard let key = tokens.first else { return value ?? .null }
        let tail = tokens.dropFirst()
        switch self {
        case .object(var object):
            if tail.isEmpty {
                object[key] = value
            } else if let existing = object[key] {
                object[key] = try existing.replacing(tail, with: value)
            } else if value != nil {
                object[key] = try A2UIValue.object([:]).replacing(tail, with: value)
            }
            return .object(object)
        case .array(var array):
            guard let index = Int(key), String(index) == key, array.indices.contains(index) else {
                throw A2UITransaction.Failure(path: "updateDataModel.path", reason: "Invalid array index")
            }
            if tail.isEmpty, value == nil { array.remove(at: index) } else { array[index] = try array[index].replacing(tail, with: value) }
            return .array(array)
        default: throw A2UITransaction.Failure(path: "updateDataModel.path", reason: "Cannot traverse a scalar")
        }
    }
}
