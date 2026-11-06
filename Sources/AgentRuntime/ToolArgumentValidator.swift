import Foundation
import Protocols

/// Structural validation of the schema vocabulary emitted by tool declarations.
/// Local references are bounded; unsupported assertions fail closed rather than being ignored.
public enum ToolArgumentValidator {
    struct Invalid: Error, CustomStringConvertible {
        var description: String
    }

    public static func arguments(_ raw: String, schema: JSONValue) throws -> [String: JSONValue] {
        guard raw.utf8.count <= 1_048_576, let data = raw.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              case .object(let arguments) = value else {
            throw Invalid(description: "Arguments must be a complete JSON object (at most 1 MiB).")
        }
        try validate(value, schema: schema, root: schema, path: "$", depth: 0)
        return arguments
    }

    private static func validate(_ value: JSONValue, schema: JSONValue, root: JSONValue, path: String, depth: Int) throws {
        guard depth < 64 else { throw Invalid(description: "\(path): schema recursion limit exceeded.") }
        if case .bool(let allowed) = schema {
            if !allowed { throw Invalid(description: "\(path): value is forbidden.") }
            return
        }
        guard case .object(let fields) = schema else { throw Invalid(description: "\(path): invalid schema.") }
        let supported: Set<String> = ["$schema", "$id", "$defs", "definitions", "$ref", "title", "description", "default", "examples", "deprecated", "readOnly", "writeOnly", "type", "enum", "const", "anyOf", "oneOf", "allOf", "not", "properties", "required", "additionalProperties", "items", "minItems", "maxItems", "uniqueItems", "minLength", "maxLength", "pattern", "format", "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "multipleOf", "minProperties", "maxProperties"]
        if let key = fields.keys.sorted().first(where: { !supported.contains($0) }) {
            throw Invalid(description: "\(path): unsupported schema assertion \(key).")
        }
        if case .string(let reference) = fields["$ref"] {
            guard reference.hasPrefix("#/") else { throw Invalid(description: "\(path): only local schema references are supported.") }
            var target = root
            for component in reference.dropFirst(2).components(separatedBy: "/") {
                let key = component.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
                guard case .object(let object) = target, let next = object[key] else { throw Invalid(description: "\(path): unresolved schema reference.") }
                target = next
            }
            try validate(value, schema: target, root: root, path: path, depth: depth + 1)
        }
        if case .array(let choices) = fields["enum"], !choices.contains(value) { throw Invalid(description: "\(path): value is outside enum.") }
        if let constant = fields["const"], constant != value { throw Invalid(description: "\(path): value does not match const.") }
        for keyword in ["anyOf", "oneOf", "allOf"] {
            if case .array(let choices) = fields[keyword] {
                let matches = choices.filter { (try? validate(value, schema: $0, root: root, path: path, depth: depth + 1)) != nil }.count
                let valid = keyword == "anyOf" ? matches > 0 : (keyword == "oneOf" ? matches == 1 : matches == choices.count)
                if !valid { throw Invalid(description: "\(path): \(keyword) did not match.") }
            }
        }
        if let excluded = fields["not"], (try? validate(value, schema: excluded, root: root, path: path, depth: depth + 1)) != nil {
            throw Invalid(description: "\(path): forbidden schema matched.")
        }
        if let type = fields["type"] {
            let types: [String]
            switch type {
            case .string(let name): types = [name]
            case .array(let values): types = values.compactMap { if case .string(let name) = $0 { name } else { nil } }
            default: types = []
            }
            guard types.contains(where: { matches(value, type: $0) }) else { throw Invalid(description: "\(path): wrong value type.") }
        }
        func bound(_ key: String) -> Double? { if case .number(let number) = fields[key] { number } else { nil } }
        func checkSize(_ size: Int, minimum: String, maximum: String) throws {
            if let min = bound(minimum), Double(size) < min { throw Invalid(description: "\(path): below \(minimum).") }
            if let max = bound(maximum), Double(size) > max { throw Invalid(description: "\(path): above \(maximum).") }
        }
        switch value {
        case .object(let object):
            try checkSize(object.count, minimum: "minProperties", maximum: "maxProperties")
            if case .array(let required) = fields["required"] {
                for case .string(let key) in required where object[key] == nil { throw Invalid(description: "\(path).\(key): required property is missing.") }
            }
            let properties = fields["properties"]?.asObject ?? [:]
            for (key, child) in object {
                if let childSchema = properties[key] {
                    try validate(child, schema: childSchema, root: root, path: path + "." + key, depth: depth + 1)
                } else if let additional = fields["additionalProperties"] {
                    try validate(child, schema: additional, root: root, path: path + "." + key, depth: depth + 1)
                }
            }
        case .array(let array):
            try checkSize(array.count, minimum: "minItems", maximum: "maxItems")
            if fields["uniqueItems"] == .bool(true), array.indices.contains(where: { array[..<$0].contains(array[$0]) }) { throw Invalid(description: "\(path): duplicate array items.") }
            if let items = fields["items"] {
                for (index, child) in array.enumerated() { try validate(child, schema: items, root: root, path: "\(path)[\(index)]", depth: depth + 1) }
            }
        case .string(let string):
            try checkSize(string.unicodeScalars.count, minimum: "minLength", maximum: "maxLength")
            if case .string(let pattern) = fields["pattern"] {
                guard let regex = try? NSRegularExpression(pattern: pattern), regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) != nil else { throw Invalid(description: "\(path): pattern did not match.") }
            }
        case .number(let number):
            if let min = bound("minimum"), number < min { throw Invalid(description: "\(path): below minimum.") }
            if let max = bound("maximum"), number > max { throw Invalid(description: "\(path): above maximum.") }
            if let min = bound("exclusiveMinimum"), number <= min { throw Invalid(description: "\(path): below exclusive minimum.") }
            if let max = bound("exclusiveMaximum"), number >= max { throw Invalid(description: "\(path): above exclusive maximum.") }
            if let divisor = bound("multipleOf"), divisor <= 0 || abs(number / divisor - (number / divisor).rounded()) > 1e-9 { throw Invalid(description: "\(path): invalid numeric multiple.") }
        default: break
        }
    }

    private static func matches(_ value: JSONValue, type: String) -> Bool {
        switch (type, value) {
        case ("object", .object), ("array", .array), ("string", .string), ("number", .number), ("boolean", .bool), ("null", .null): return true
        case ("integer", .number(let value)): return value.isFinite && value.rounded() == value
        default: return false
        }
    }
}
