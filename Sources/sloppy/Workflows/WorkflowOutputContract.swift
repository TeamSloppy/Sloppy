import Foundation
import Protocols

enum WorkflowOutputContract {
    private static let types = ["object", "array", "string", "number", "integer", "boolean", "null"]
    private static let keywords: Set<String> = ["type", "properties", "required", "items", "enum", "minLength", "additionalProperties", "description"]

    static func validateDefinition(_ schema: JSONValue?) throws {
        guard let schema, schema != .null else { return }
        try checkSchema(schema, path: "outputSchema", depth: 0)
        guard schema.asObject?["type"] == .string("object") else { throw WorkflowGraphContracts.Violation("outputSchema must describe the step output object.") }
    }

    static func validate(node: WorkflowNode, output: [String: JSONValue]) throws {
        guard let schema = node.config["outputSchema"], schema != .null else { return }
        try validateDefinition(schema)
        try checkValue(.object(output), schema: schema, path: "output")
    }

    private static func checkSchema(_ schema: JSONValue, path: String, depth: Int) throws {
        func invalid(_ message: String) -> WorkflowGraphContracts.Violation { .init("\(path): \(message)") }
        guard depth <= 16, let object = schema.asObject, let type = object["type"]?.asString, types.contains(type) else {
            throw invalid("expected a supported type; maximum schema depth is 16.")
        }
        if let unknown = Set(object.keys).subtracting(keywords).sorted().first { throw invalid("unsupported keyword \(unknown).") }
        if let properties = object["properties"] {
            guard type == "object", let fields = properties.asObject else { throw invalid("properties must be an object schema map.") }
            for key in fields.keys.sorted() { try checkSchema(fields[key] ?? .null, path: "\(path).\(key)", depth: depth + 1) }
        }
        if let required = object["required"] {
            guard type == "object", case .array(let fields) = required,
                  fields.allSatisfy({ $0.asString?.isEmpty == false }),
                  Set(fields.compactMap(\.asString)).count == fields.count else { throw invalid("required must contain unique nonempty field names.") }
        }
        if let items = object["items"] {
            guard type == "array" else { throw invalid("items is only supported for arrays.") }
            try checkSchema(items, path: "\(path).items", depth: depth + 1)
        }
        if let values = object["enum"] {
            guard case .array(let allowed) = values, !allowed.isEmpty, allowed.allSatisfy({ matches($0, type: type) }) else {
                throw invalid("enum must contain values of the declared type.")
            }
        }
        if let minimum = object["minLength"] {
            guard type == "string", case .number(let count) = minimum, count.isFinite, count >= 0, count.rounded() == count else {
                throw invalid("minLength must be a nonnegative integer on a string.")
            }
        }
        if let additional = object["additionalProperties"] {
            guard type == "object", case .bool = additional else { throw invalid("additionalProperties must be boolean on an object.") }
            if additional == .bool(false), case .array(let required) = object["required"],
               required.contains(where: { object["properties"]?.asObject?[$0.asString ?? ""] == nil }) {
                throw invalid("required fields must be declared when additionalProperties is false.")
            }
        }
        if let description = object["description"], description.asString == nil { throw invalid("description must be a string.") }
    }

    private static func checkValue(_ value: JSONValue, schema: JSONValue, path: String) throws {
        guard let object = schema.asObject, let type = object["type"]?.asString else { return }
        func invalid(_ message: String) -> WorkflowGraphContracts.Violation { .init("\(path): \(message)") }
        guard matches(value, type: type) else { throw invalid("expected \(type).") }
        if case .array(let allowed) = object["enum"], !allowed.contains(value) { throw invalid("value is outside enum.") }
        if case .string(let text) = value, case .number(let minimum) = object["minLength"], Double(text.unicodeScalars.count) < minimum {
            throw invalid("string is shorter than minLength.")
        }
        if case .object(let fields) = value {
            let properties = object["properties"]?.asObject ?? [:]
            if case .array(let required) = object["required"] {
                for key in required.compactMap(\.asString) where fields[key] == nil { throw invalid("missing required field \(key).") }
            }
            if object["additionalProperties"] == .bool(false), let unknown = Set(fields.keys).subtracting(properties.keys).sorted().first {
                throw invalid("unexpected field \(unknown).")
            }
            for key in properties.keys.sorted() {
                if let field = fields[key], let schema = properties[key] { try checkValue(field, schema: schema, path: "\(path).\(key)") }
            }
        }
        if case .array(let values) = value, let itemSchema = object["items"] {
            for (index, item) in values.enumerated() { try checkValue(item, schema: itemSchema, path: "\(path).\(index)") }
        }
    }

    private static func matches(_ value: JSONValue, type: String) -> Bool {
        switch (type, value) {
        case ("object", .object), ("array", .array), ("string", .string), ("number", .number), ("boolean", .bool), ("null", .null): return true
        case ("integer", .number(let number)): return number.isFinite && number.rounded() == number
        default: return false
        }
    }
}
