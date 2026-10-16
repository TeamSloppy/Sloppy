import Foundation
import Protocols

/// Repairs structurally wrong tool arguments against the tool's own JSON schema before the tool runs.
///
/// Weaker models often send `"10"` for an integer, `"true"` for a boolean, `false` for an unset optional,
/// a scalar where an array is expected, or `file_path` instead of `filePath`. Values are never coerced into strings. Every repair is decided from the
/// schema (types, enum choices, property names) and the argument's JSON type, never from natural-language text,
/// and is reported so the model sees what was changed. Anything ambiguous is left untouched.
struct ToolArgumentNormalizer {
    struct Repair: Equatable {
        var field: String
        var change: String
    }

    struct Property {
        var type: String?
        var enumChoices: [String]
        var itemType: String?
    }

    struct Result {
        var arguments: [String: JSONValue]
        var repairs: [Repair]
    }

    let properties: [String: Property]
    let required: Set<String>

    init(schemaJSON: Data) {
        var parsed: [String: Property] = [:]
        var requiredNames: Set<String> = []
        if let root = (try? JSONSerialization.jsonObject(with: schemaJSON)) as? [String: Any] {
            requiredNames = Set((root["required"] as? [String]) ?? [])
            for (name, raw) in (root["properties"] as? [String: Any]) ?? [:] {
                guard let node = raw as? [String: Any] else { continue }
                let items = node["items"] as? [String: Any]
                parsed[name] = Property(
                    type: node["type"] as? String,
                    enumChoices: (node["enum"] as? [String]) ?? [],
                    itemType: items?["type"] as? String
                )
            }
        }
        properties = parsed
        required = requiredNames
    }

    func normalize(_ arguments: [String: JSONValue]) -> Result {
        guard !properties.isEmpty else { return Result(arguments: arguments, repairs: []) }
        var output: [String: JSONValue] = [:]
        var repairs: [Repair] = []

        // 1. Rename keys that differ from a schema property only by case, `_` or `-`.
        let byCanonicalName = Dictionary(grouping: properties.keys, by: Self.canonicalKey)
        for (key, value) in arguments {
            if properties[key] != nil {
                output[key] = value
            } else if let candidates = byCanonicalName[Self.canonicalKey(key)], candidates.count == 1,
                      arguments[candidates[0]] == nil {
                output[candidates[0]] = value
                repairs.append(Repair(field: key, change: "renamed to `\(candidates[0])`"))
            } else {
                output[key] = value
            }
        }

        // 2. Coerce values to the declared type.
        for (key, property) in properties {
            guard let value = output[key] else { continue }
            let (coerced, change) = coerce(value, to: property, isRequired: required.contains(key))
            if let change {
                repairs.append(Repair(field: key, change: change))
                if let coerced { output[key] = coerced } else { output.removeValue(forKey: key) }
            }
        }
        return Result(arguments: output, repairs: repairs.sorted { $0.field < $1.field })
    }

    private func coerce(_ value: JSONValue, to property: Property, isRequired: Bool) -> (JSONValue?, String?) {
        switch property.type {
        case "integer", "number":
            switch value {
            case .number: return (value, nil)
            case .string(let text):
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                if let number = Double(trimmed), number.isFinite {
                    if property.type == "integer", number != number.rounded() { return (value, nil) }
                    return (.number(number), "string converted to number")
                }
                return (value, nil)
            case .bool, .null:
                // A boolean or null in a numeric slot carries no number; an unset optional is the honest reading.
                return isRequired ? (value, nil) : (nil, "ignored non-numeric \(Self.kind(value)) for optional field")
            default: return (value, nil)
            }
        case "boolean":
            if case .string(let text) = value {
                switch text.trimmingCharacters(in: .whitespaces).lowercased() {
                case "true": return (.bool(true), "string converted to boolean")
                case "false": return (.bool(false), "string converted to boolean")
                default: return (value, nil)
                }
            }
            return (value, nil)
        case "string":
            if !property.enumChoices.isEmpty, case .string(let text) = value {
                if property.enumChoices.contains(text) { return (value, nil) }
                let wanted = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let matches = property.enumChoices.filter { Self.canonicalKey($0) == Self.canonicalKey(wanted) }
                if matches.count == 1 { return (.string(matches[0]), "matched allowed value `\(matches[0])`") }
                return (value, nil)
            }
            // Numbers and booleans are never turned into strings: tools validate identifiers strictly, and a
            // coerced `123` could address the wrong record.
            return (value, nil)
        case "array":
            switch value {
            case .array: return (value, nil)
            case .null: return isRequired ? (value, nil) : (nil, "ignored null for optional field")
            case .string(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("["),
                   let data = trimmed.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode([JSONValue].self, from: data) {
                    return (.array(decoded), "JSON text parsed as array")
                }
                if property.itemType == "string" { return (.array([value]), "single value wrapped in array") }
                return (value, nil)
            case .number, .bool:
                return (.array([value]), "single value wrapped in array")
            default: return (value, nil)
            }
        default:
            return (value, nil)
        }
    }

    static func canonicalKey(_ name: String) -> String {
        name.lowercased().filter { $0 != "_" && $0 != "-" && !$0.isWhitespace }
    }

    private static func kind(_ value: JSONValue) -> String {
        switch value {
        case .bool: return "boolean"
        case .null: return "null"
        case .string: return "string"
        case .number: return "number"
        case .array: return "array"
        case .object: return "object"
        }
    }
}
