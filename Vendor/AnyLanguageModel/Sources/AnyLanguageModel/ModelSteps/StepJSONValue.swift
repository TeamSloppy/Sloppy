import Foundation

public enum StepJSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: StepJSONValue])
    case array([StepJSONValue])
    case null

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
        } else if let value = try? container.decode([String: StepJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([StepJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}


public extension StepJSONValue {
    var asString: String? {
        guard case .string(let value) = self else {
            return nil
        }
        return value
    }

    var asBool: Bool? {
        guard case .bool(let value) = self else {
            return nil
        }
        return value
    }

    var asNumber: Double? {
        guard case .number(let value) = self else {
            return nil
        }
        return value
    }

    var asInt: Int? {
        guard case .number(let value) = self else {
            return nil
        }
        return Int(value)
    }

    var asObject: [String: StepJSONValue]? {
        guard case .object(let value) = self else {
            return nil
        }
        return value
    }

    var asArray: [StepJSONValue]? {
        guard case .array(let value) = self else {
            return nil
        }
        return value
    }
}
