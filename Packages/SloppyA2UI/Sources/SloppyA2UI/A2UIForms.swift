import Foundation

public struct A2UIOption: Codable, Sendable, Equatable {
    public var label: String
    public var value: String
    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public struct A2UIComponent: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case text = "Text"
        case column = "Column"
        case row = "Row"
        case textField = "TextField"
        case checkBox = "CheckBox"
        case choicePicker = "ChoicePicker"
        case button = "Button"
    }
    public static let propertyNames: Set<String> = [
        "id", "component", "text", "children", "label", "binding", "inputType", "required", "minimum", "maximum", "options", "action",
    ]
    public var id: String
    public var component: Kind
    public var text: String?
    public var children: [String]?
    public var label: String?
    public var binding: String?
    public var inputType: String?
    public var required: Bool?
    public var minimum: Double?
    public var maximum: Double?
    public var options: [A2UIOption]?
    public var action: String?
    public init(id: String, component: Kind, text: String? = nil, children: [String]? = nil) {
        self.id = id
        self.component = component
        self.text = text
        self.children = children
    }
    public var isInput: Bool { [.textField, .checkBox, .choicePicker].contains(component) }
    func validateShape() throws {
        var allowed: Set<String> = ["id", "component"]
        switch component {
        case .text:
            guard let text, text.utf8.count <= 16_384 else { throw A2UISurfaceSnapshot.ValidationError.invalidComponent(id) }
            allowed.insert("text")
        case .column, .row:
            guard let children, children.count <= 128 else { throw A2UISurfaceSnapshot.ValidationError.invalidComponent(id) }
            allowed.insert("children")
        case .textField, .checkBox, .choicePicker:
            guard let label, !label.isEmpty, label.utf8.count <= 1_024, binding != nil else {
                throw A2UISurfaceSnapshot.ValidationError.invalidComponent(id)
            }
            allowed.formUnion(["label", "binding", "required"])
            if component == .textField {
                guard ["text", "number"].contains(inputType ?? "text"), minimum?.isFinite != false, maximum?.isFinite != false else {
                    throw A2UISurfaceSnapshot.ValidationError.invalidComponent(id)
                }
                if let minimum, let maximum, minimum > maximum { throw A2UISurfaceSnapshot.ValidationError.invalidComponent(id) }
                guard inputType == "number" || (minimum == nil && maximum == nil) else {
                    throw A2UISurfaceSnapshot.ValidationError.invalidComponent(id)
                }
                allowed.formUnion(["inputType", "minimum", "maximum"])
            }
            if component == .choicePicker {
                guard let options, (1...32).contains(options.count), Set(options.map(\.value)).count == options.count,
                    options.allSatisfy({
                        !$0.label.isEmpty && $0.label.utf8.count <= 1_024 && !$0.value.isEmpty && $0.value.utf8.count <= 128
                    })
                else { throw A2UISurfaceSnapshot.ValidationError.invalidComponent(id) }
                allowed.insert("options")
            }
        case .button:
            guard let label, !label.isEmpty, label.utf8.count <= 1_024, let action, !action.isEmpty, action.utf8.count <= 128 else {
                throw A2UISurfaceSnapshot.ValidationError.invalidComponent(id)
            }
            allowed.formUnion(["label", "action"])
        }
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(self)) as? [String: Any] ?? [:]
        guard Set(json.keys).isSubset(of: allowed) else { throw A2UISurfaceSnapshot.ValidationError.invalidComponent(id) }
    }
}

public struct A2UISubmission: Codable, Sendable, Equatable {
    public var actionId: String
    public var revision: Int
    public var componentId: String
    public var values: [String: A2UIValue]
    public init(actionId: String, revision: Int, componentId: String, values: [String: A2UIValue]) {
        self.actionId = actionId
        self.revision = revision
        self.componentId = componentId
        self.values = values
    }
}

extension A2UIValue {
    public static func pointerTokens(_ path: String, input: Bool = false) throws -> [String] {
        guard path.utf8.count <= 1_024, path.hasPrefix("/"), !input || path != "/" else {
            throw A2UITransaction.Failure(path: "binding", reason: "Expected an absolute non-root JSON Pointer")
        }
        let tokens = path == "/" ? [] : String(path.dropFirst()).components(separatedBy: "/")
        guard tokens.count <= 16, tokens.allSatisfy({ $0.range(of: "~(?![01])", options: .regularExpression) == nil }) else {
            throw A2UITransaction.Failure(path: "binding", reason: "Invalid JSON Pointer")
        }
        return tokens.map { $0.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~") }
    }
    public func value(at path: String) -> A2UIValue? {
        guard let tokens = try? Self.pointerTokens(path) else { return nil }
        var value = self
        for token in tokens {
            switch value {
            case .object(let object):
                guard let next = object[token] else { return nil }
                value = next
            case .array(let array):
                guard let index = Int(token), String(index) == token, array.indices.contains(index) else { return nil }
                value = array[index]
            default: return nil
            }
        }
        return value
    }
    public func setting(_ path: String, to value: A2UIValue) throws -> A2UIValue {
        try replacing(Self.pointerTokens(path, input: true)[...], with: value)
    }
    public var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }
    public var boolean: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }
    public var number: Double? {
        if case .number(let value) = self { return value }
        return nil
    }
}

extension A2UISurfaceSnapshot {
    public var initialValues: [String: A2UIValue] {
        var values: [String: A2UIValue] = [:]
        for field in components where field.isInput {
            guard let path = field.binding else { continue }
            values[path] =
                dataModel?.value(at: path)
                ?? (field.component == .checkBox
                    ? .bool(false) : field.component == .textField && field.inputType != "number" ? .string("") : .null)
        }
        return values
    }
    public func normalizedValues(_ values: [String: A2UIValue]) -> [String: A2UIValue] {
        var result = values
        for field in components where field.component == .textField && field.inputType == "number" {
            guard let path = field.binding, let text = values[path]?.string else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                result[path] = .null
            } else if let number = Double(trimmed), number.isFinite {
                result[path] = .number(number)
            }
        }
        return result
    }
    public func validationErrors(_ rawValues: [String: A2UIValue], normalizeNumbers: Bool = true) -> [String: String] {
        let values = normalizeNumbers ? normalizedValues(rawValues) : rawValues
        var errors: [String: String] = [:]
        for field in components where field.isInput {
            guard let path = field.binding else { continue }
            let value = values[path] ?? .null
            if value == .null, field.required != true { continue }
            var valid = false
            switch field.component {
            case .textField where field.inputType == "number":
                if let number = value.number {
                    valid = number.isFinite && (field.minimum.map { number >= $0 } ?? true) && (field.maximum.map { number <= $0 } ?? true)
                }
            case .textField:
                if let string = value.string {
                    valid =
                        string.utf8.count <= 16_384
                        && (field.required != true || !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            case .checkBox: valid = value.boolean != nil && (field.required != true || value.boolean == true)
            case .choicePicker: valid = field.options?.contains(where: { $0.value == value.string }) == true
            default: break
            }
            if !valid { errors[path] = "Check \(field.label ?? path)" }
        }
        return errors
    }
    public func accepting(_ submission: A2UISubmission) throws -> A2UISurfaceSnapshot {
        try validate()
        guard UUID(uuidString: submission.actionId) != nil, isDeleted != true, submittedActionId == nil,
            submission.revision == revision, revision < Int.max,
            components.contains(where: { $0.id == submission.componentId && $0.component == .button }),
            Set(submission.values.keys) == Set(initialValues.keys), validationErrors(submission.values, normalizeNumbers: false).isEmpty
        else {
            throw A2UITransaction.Failure(path: "submission", reason: "Invalid values, button or stale surface")
        }
        var result = self
        var model = dataModel ?? .object([:])
        for (path, value) in submission.values { model = try model.setting(path, to: value) }
        result.dataModel = model
        result.submittedActionId = submission.actionId
        result.revision += 1
        try result.validate()
        return result
    }
}

extension A2UIComponent {
    public static func catalogSchemaData() throws -> Data {
        let string: [String: Any] = ["type": "string"]
        var result: [String: Any] = [:]
        for kind in [Kind.text, .row, .column, .textField, .checkBox, .choicePicker, .button] {
            var properties: [String: Any] = ["id": string, "component": ["const": kind.rawValue]]
            var required = ["id", "component"]
            switch kind {
            case .text:
                properties["text"] = string
                required.append("text")
            case .row, .column:
                properties["children"] = ["type": "array", "items": string, "maxItems": 128]
                required.append("children")
            case .button:
                properties["label"] = string
                properties["action"] = string
                required += ["label", "action"]
            default:
                properties["label"] = string
                properties["binding"] = string
                properties["required"] = ["type": "boolean"]
                required += ["label", "binding"]
                if kind == .textField {
                    properties["inputType"] = ["enum": ["text", "number"]]
                    properties["minimum"] = ["type": "number"]
                    properties["maximum"] = ["type": "number"]
                }
                if kind == .choicePicker {
                    properties["options"] = [
                        "type": "array", "minItems": 1, "maxItems": 32,
                        "items": [
                            "type": "object", "properties": ["label": string, "value": string], "required": ["label", "value"],
                            "additionalProperties": false,
                        ],
                    ]
                    required.append("options")
                }
            }
            result[kind.rawValue] = ["type": "object", "properties": properties, "required": required, "additionalProperties": false]
        }
        return try JSONSerialization.data(withJSONObject: result, options: .sortedKeys)
    }
}
