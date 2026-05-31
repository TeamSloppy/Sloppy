//
//  Message.swift
//  ACPModel
//
//  Agent Client Protocol - JSON-RPC Message Types
//

import Foundation

// MARK: - JSON-RPC Message Types

public enum Message: Codable, Sendable {
    case request(JSONRPCRequest)
    case response(JSONRPCResponse)
    case notification(JSONRPCNotification)

    enum CodingKeys: String, CodingKey {
        case jsonrpc, method, id, params
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hasMethod = container.contains(.method)

        if hasMethod {
            // Some implementations may send notifications with `"id": null` or malformed `id`.
            // Prefer decoding as notification instead of dropping the whole message.
            if container.contains(.id), let request = try? JSONRPCRequest(from: decoder) {
                self = .request(request)
                return
            }

            self = .notification(try JSONRPCNotification(from: decoder))
            return
        }

        self = .response(try JSONRPCResponse(from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .request(let req):
            try req.encode(to: encoder)
        case .response(let res):
            try res.encode(to: encoder)
        case .notification(let notif):
            try notif.encode(to: encoder)
        }
    }
}

public struct JSONRPCRequest: Codable, Sendable {
    public let jsonrpc: String = "2.0"
    public let id: RequestId
    public let method: String
    public let params: AnyCodable?

    enum CodingKeys: String, CodingKey {
        case jsonrpc, id, method, params
    }

    public init(id: RequestId, method: String, params: AnyCodable?) {
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct JSONRPCResponse: Codable, Sendable {
    public let jsonrpc: String = "2.0"
    public let id: RequestId
    public let result: AnyCodable?
    public let error: JSONRPCError?

    enum CodingKeys: String, CodingKey {
        case jsonrpc, id, result, error
    }

    public init(id: RequestId, result: AnyCodable?, error: JSONRPCError?) {
        self.id = id
        self.result = result
        self.error = error
    }
}

public struct JSONRPCNotification: Codable, Sendable {
    public let jsonrpc: String = "2.0"
    public let method: String
    public let params: AnyCodable?

    enum CodingKeys: String, CodingKey {
        case jsonrpc, method, params
    }

    public init(method: String, params: AnyCodable?) {
        self.method = method
        self.params = params
    }
}

public struct JSONRPCError: Codable, Sendable {
    public let code: Int
    public let message: String
    public let data: AnyCodable?

    public init(code: Int, message: String, data: AnyCodable?) {
        self.code = code
        self.message = message
        self.data = data
    }
}

public enum RequestId: Codable, Hashable, CustomStringConvertible, Sendable {
    case string(String)
    case number(Int)

    public var description: String {
        switch self {
        case .string(let str): return str
        case .number(let num): return String(num)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let num = try? container.decode(Int.self) {
            self = .number(num)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid RequestId")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let str):
            try container.encode(str)
        case .number(let num):
            try container.encode(num)
        }
    }
}

// MARK: - AnyCodable Helper

public struct AnyCodable: Codable, Sendable {
    public let value: any Sendable

    public init(_ value: any Sendable) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [any Sendable]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: any Sendable]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        case is NSNull:
            try container.encodeNil()
        default:
            try container.encodeNil()
        }
    }
}

// MARK: - Helper for encoding arbitrary keys

public struct AnyCodingKey: CodingKey, Sendable {
    public let stringValue: String
    public let intValue: Int?

    public init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    public init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
