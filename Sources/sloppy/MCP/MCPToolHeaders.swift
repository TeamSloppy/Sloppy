import Foundation
import Protocols

struct MCPToolHeaders: Sendable {
    private struct Field: Sendable {
        let name: String
        let path: [String]
        let type: String
    }

    private let fields: [Field]

    init(schema: JSONValue) throws {
        var fields: [Field] = []
        var seen: Set<String> = []
        func collect(_ node: JSONValue, path: [String]?, depth: Int) throws {
            guard depth <= 100 else { throw MCPRegistryError.invalidResult("MCP input schema is too deeply nested.") }
            if let object = node.asObject {
                if let annotation = object["x-mcp-header"] {
                    guard let path, !path.isEmpty, let name = annotation.asString, !name.isEmpty,
                          name.utf8.allSatisfy({ Self.tokenBytes.contains($0) }),
                          let type = object["type"]?.asString, ["string", "boolean", "integer"].contains(type),
                          seen.insert(name.lowercased()).inserted else {
                        throw MCPRegistryError.invalidResult("Invalid x-mcp-header annotation.")
                    }
                    fields.append(Field(name: name, path: path, type: type))
                }
                for (key, value) in object where key != "x-mcp-header" {
                    if key == "properties", let path, let properties = value.asObject {
                        for (property, schema) in properties { try collect(schema, path: path + [property], depth: depth + 1) }
                    } else {
                        try collect(value, path: nil, depth: depth + 1)
                    }
                }
            } else if let array = node.asArray {
                for value in array { try collect(value, path: nil, depth: depth + 1) }
            }
        }
        try collect(schema, path: [], depth: 0)
        self.fields = fields
    }

    func encode(_ arguments: [String: JSONValue]) throws -> [String: String] {
        var headers: [String: String] = [:]
        for field in fields {
            let value = field.path.reduce(JSONValue.object(arguments) as JSONValue?) { $0?.asObject?[$1] }
            guard let value, value != .null else { continue }
            let text: String
            switch (field.type, value) {
            case ("string", .string(let value)): text = value
            case ("boolean", .bool(let value)): text = value ? "true" : "false"
            case ("integer", .number(let value)) where abs(value) <= 9_007_199_254_740_991 && value.rounded() == value:
                text = String(Int64(value))
            default:
                throw MCPRegistryError.invalidResult("Invalid MCP argument for mirrored header '\(field.name)'.")
            }
            headers["Mcp-Param-\(field.name)"] = MCPHTTPDiscovery.headerValue(text)
        }
        return headers
    }

    private static let tokenBytes = Set("!#$%&'*+-.^_`|~0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".utf8)
}
