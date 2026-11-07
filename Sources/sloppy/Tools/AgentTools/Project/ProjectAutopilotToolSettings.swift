import Foundation
import AnyLanguageModel
import Protocols

/// Typed tool schema and partial updates for the existing project settings model.
enum ProjectAutopilotToolSettings {
    static var schema: DynamicGenerationSchema {
        let condition = DynamicGenerationSchema(name: "AutopilotPickupCondition", properties: [
            .init(name: "id", description: "Stable condition ID.", schema: .init(type: String.self)),
            .init(name: "field", description: "author, assignee, queue, priority, tag, title, description, source, kind, issue_type, or external_status.", schema: .init(type: String.self)),
            .init(name: "operation", description: "one_of, not_one_of, contains (title/description only), is_set, or is_not_set.", schema: .init(type: String.self)),
            .init(name: "values", description: "Values to match; empty for is_set/is_not_set.", schema: .init(arrayOf: .init(type: String.self)))
        ])
        let rules = DynamicGenerationSchema(name: "AutopilotPickupRules", properties: [
            .init(name: "matchMode", description: "all or any.", schema: .init(type: String.self), isOptional: true),
            .init(name: "conditions", description: "Replace pickup conditions, up to 50; empty clears them.", schema: .init(arrayOf: condition), isOptional: true)
        ])
        return DynamicGenerationSchema(name: "AutopilotSettingsPatch", properties: [
            .init(name: "enabled", description: "Enable or disable project Autopilot.", schema: .init(type: Bool.self), isOptional: true),
            .init(name: "mode", description: "assistive, sequential, or parallel.", schema: .init(type: String.self), isOptional: true),
            .init(name: "defaultAgentId", description: "Agent that executes tasks. Empty string clears the assignment.", schema: .init(type: String.self), isOptional: true),
            .init(name: "reviewerAgentId", description: "Review agent. Empty string clears the assignment.", schema: .init(type: String.self), isOptional: true),
            .init(name: "includedTags", description: "Replace include tags. Empty means all tags are eligible.", schema: .init(arrayOf: .init(type: String.self)), isOptional: true),
            .init(name: "ignoredTags", description: "Replace excluded tags; exclusions take precedence.", schema: .init(arrayOf: .init(type: String.self)), isOptional: true),
            .init(name: "trustedAuthors", description: "Replace trusted authors. Empty allows all authors.", schema: .init(arrayOf: .init(type: String.self)), isOptional: true),
            .init(name: "pickupRules", description: "Partial pickup-rule update. Omitted fields are preserved.", schema: rules, isOptional: true),
            .init(name: "maxParallelTasks", description: "Maximum concurrent tasks, at least 1.", schema: .init(type: Int.self), isOptional: true),
            .init(name: "canUseWeb", description: "Allow web access.", schema: .init(type: Bool.self), isOptional: true),
            .init(name: "canEditFiles", description: "Allow file edits.", schema: .init(type: Bool.self), isOptional: true),
            .init(name: "canRunCommands", description: "Allow commands.", schema: .init(type: Bool.self), isOptional: true),
            .init(name: "canStartLocalhost", description: "Allow local servers.", schema: .init(type: Bool.self), isOptional: true),
            .init(name: "canCommit", description: "Allow commits.", schema: .init(type: Bool.self), isOptional: true),
            .init(name: "canPush", description: "Allow pushes.", schema: .init(type: Bool.self), isOptional: true)
        ])
    }

    static func applying(_ value: JSONValue, to current: ProjectAutopilotSettings) throws -> ProjectAutopilotSettings {
        guard let patch = value.asObject else { throw InvalidSettings() }
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let encoded = try decoder.decode(JSONValue.self, from: encoder.encode(current))
        guard var object = encoded.asObject else { throw InvalidSettings() }
        object["defaultAgentId"] = object["defaultAgentId"] ?? .null
        object["reviewerAgentId"] = object["reviewerAgentId"] ?? .null
        let merged = try merge(patch, into: object)
        var settings = try decoder.decode(ProjectAutopilotSettings.self, from: encoder.encode(JSONValue.object(merged)))
        guard settings.pickupRules.isValid else { throw InvalidSettings() }
        settings.defaultAgentId = normalizedID(settings.defaultAgentId)
        settings.reviewerAgentId = normalizedID(settings.reviewerAgentId)
        return settings
    }

    private static func merge(_ patch: [String: JSONValue], into current: [String: JSONValue]) throws -> [String: JSONValue] {
        var result = current
        for (key, value) in patch {
            guard current[key] != nil else { throw InvalidSettings() }
            // Providers may include null placeholders for unused optional fields.
            guard value != .null else { continue }
            if let fields = value.asObject, let existing = current[key]?.asObject {
                result[key] = .object(try merge(fields, into: existing))
            } else {
                result[key] = value
            }
        }
        return result
    }

    private static func normalizedID(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private struct InvalidSettings: Error {}
}
