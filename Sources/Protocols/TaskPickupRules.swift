import Foundation

public enum TaskPickupField: String, Codable, Sendable, CaseIterable {
    case author, assignee, queue, priority, tag, title, description, source, kind
    case issueType = "issue_type"
    case externalStatus = "external_status"
}

public enum TaskPickupOperator: String, Codable, Sendable, CaseIterable {
    case oneOf = "one_of"
    case notOneOf = "not_one_of"
    case contains
    case isSet = "is_set"
    case isNotSet = "is_not_set"
}

public struct TaskPickupCondition: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var field: TaskPickupField
    public var operation: TaskPickupOperator
    public var values: [String]

    public init(id: String = UUID().uuidString, field: TaskPickupField, operation: TaskPickupOperator = .oneOf, values: [String] = []) {
        self.id = id
        self.field = field
        self.operation = operation
        self.values = values
    }

    public var isValid: Bool {
        if operation == .contains && field != .title && field != .description { return false }
        return operation == .isSet || operation == .isNotSet || !normalizedPickupValues(values).isEmpty
    }

    public func matches(_ task: ProjectTask) -> Bool {
        guard isValid else { return false }
        let actual = normalizedPickupValues(task.pickupValues(for: field))
        if operation == .isSet { return !actual.isEmpty }
        if operation == .isNotSet { return actual.isEmpty }
        // Tags are a known list, including when that list is empty.
        if field == .tag && operation == .notOneOf && actual.isEmpty { return true }
        // Unknown source metadata must not pass a negative identity condition.
        guard !actual.isEmpty else { return false }
        let expected = normalizedPickupValues(values)
        switch operation {
        case .oneOf: return !Set(actual).isDisjoint(with: expected)
        case .notOneOf: return Set(actual).isDisjoint(with: expected)
        case .contains: return actual.contains { value in expected.contains { value.contains($0) } }
        case .isSet, .isNotSet: return false
        }
    }
}

public struct ProjectTaskPickupRules: Codable, Sendable, Equatable {
    public enum MatchMode: String, Codable, Sendable { case all, any }
    public var matchMode: MatchMode
    public var conditions: [TaskPickupCondition]

    public init(matchMode: MatchMode = .all, conditions: [TaskPickupCondition] = []) {
        self.matchMode = matchMode
        self.conditions = conditions
    }

    public var isValid: Bool {
        conditions.count <= 50 && conditions.allSatisfy(\.isValid)
    }

    public func matches(_ task: ProjectTask) -> Bool {
        guard isValid else { return false }
        guard !conditions.isEmpty else { return true }
        switch matchMode {
        case .all: return conditions.allSatisfy { $0.matches(task) }
        case .any: return conditions.contains { $0.matches(task) }
        }
    }
}

private func normalizedPickupValues(_ values: [String]) -> [String] {
    values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
}

extension ProjectTask {
    public func pickupValues(for field: TaskPickupField) -> [String] {
        let metadata = externalMetadata
        switch field {
        case .author:
            if metadata?.providerId != nil {
                return [metadata?.externalCreator?.id, metadata?.externalCreator?.login].compactMap { $0 }
            }
            return [createdBy].compactMap { $0 }
        case .assignee:
            if metadata?.providerId != nil {
                return [metadata?.externalAssigneeIdentity?.id, metadata?.externalAssigneeIdentity?.login].compactMap { $0 }
            }
            return [actorId].compactMap { $0 }
        case .queue: return [metadata?.externalQueue].compactMap { $0 }
        case .issueType: return [metadata?.externalIssueType].compactMap { $0 }
        case .priority: return [priority, metadata?.externalPriorityKey].compactMap { $0 }
        case .externalStatus: return [metadata?.externalStatus?.key].compactMap { $0 }
        case .tag: return tags
        case .title: return [title]
        case .description: return [description]
        case .source: return [metadata?.providerId ?? "local"]
        case .kind: return [kind?.rawValue].compactMap { $0 }
        }
    }
}
