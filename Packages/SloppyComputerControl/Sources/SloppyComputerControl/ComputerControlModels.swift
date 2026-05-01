import Foundation

public enum ComputerControlValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([ComputerControlValue])
    case object([String: ComputerControlValue])

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
        } else if let value = try? container.decode([ComputerControlValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: ComputerControlValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported computer control value.")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

public struct ComputerClickPayload: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double?
    public var height: Double?

    public init(x: Double, y: Double, width: Double? = nil, height: Double? = nil) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct ComputerTypeTextPayload: Codable, Sendable, Equatable {
    public var text: String

    public init(text: String) {
        self.text = text
    }
}

public struct ComputerKeyPayload: Codable, Sendable, Equatable {
    public var key: String
    public var modifiers: [String]

    public init(key: String, modifiers: [String] = []) {
        self.key = key
        self.modifiers = modifiers
    }
}

public struct ComputerScreenshotPayload: Codable, Sendable, Equatable {
    public var outputPath: String?

    public init(outputPath: String? = nil) {
        self.outputPath = outputPath
    }
}

public struct ComputerScreenshotResult: Codable, Sendable, Equatable {
    public var path: String
    public var width: Int
    public var height: Int
    public var mediaType: String
    public var displayId: String?

    public init(path: String, width: Int, height: Int, mediaType: String, displayId: String? = nil) {
        self.path = path
        self.width = width
        self.height = height
        self.mediaType = mediaType
        self.displayId = displayId
    }
}
