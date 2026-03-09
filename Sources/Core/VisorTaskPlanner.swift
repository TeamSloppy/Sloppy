import Foundation
import AgentRuntime
import Protocols

/// Immutable input used by the Visor task planner to decide whether the
/// incoming channel message should mutate project tasks.
struct VisorTaskPlanningContext: Sendable {
    var channelId: String
    var content: String
    var recentMessages: [ChannelMessageEntry]
    var tasks: [ProjectTask]
    var actorIDs: Set<String>
    var teamIDs: Set<String>
}

/// Structured planner output that can be executed by `CoreService`
/// without relying on prompt heuristics.
enum VisorTaskIntent: Sendable, Equatable {
    case create(VisorTaskCreateIntent)
    case update(VisorTaskUpdateIntent)
    case cancel(VisorTaskCancelIntent)
    case split(VisorTaskSplitIntent)
}

/// Intent to create a new project task.
struct VisorTaskCreateIntent: Sendable, Equatable {
    var title: String
    var description: String?
    var priority: String?
    var actorId: String?
    var teamId: String?
}

/// Intent to update selected fields on an existing task.
struct VisorTaskUpdateIntent: Sendable, Equatable {
    var reference: String
    var title: String?
    var description: String?
    var priority: String?
    var status: ProjectTaskStatus?
    var actorId: String?
    var teamId: String?
}

/// Intent to safely cancel an existing task.
struct VisorTaskCancelIntent: Sendable, Equatable {
    var reference: String
    var reason: String?
}

/// Intent to split one task into multiple follow-up tasks.
struct VisorTaskSplitIntent: Sendable, Equatable {
    var reference: String
    var items: [String]
}

/// Parser that converts explicit task-management language into typed intents.
enum VisorTaskPlanner {
    static func plan(context: VisorTaskPlanningContext) -> [VisorTaskIntent] {
        let content = normalizeWhitespace(context.content)
        guard !content.isEmpty else {
            return []
        }

        if let slashPlan = slashCommandPlan(content: content) {
            return slashPlan
        }

        if let explicitPlan = explicitTaskPlan(content: content) {
            return explicitPlan
        }

        return []
    }

    private static func slashCommandPlan(content: String) -> [VisorTaskIntent]? {
        guard content.lowercased().hasPrefix("/task") else {
            return nil
        }

        let rawRemainder = content.dropFirst(5)
        let remainder = normalizeWhitespace(String(rawRemainder))
        guard !remainder.isEmpty else {
            return []
        }

        if let split = splitIntent(from: remainder) {
            return [.split(split)]
        }
        if let cancel = cancelIntent(from: remainder) {
            return [.cancel(cancel)]
        }
        if let update = updateIntent(from: remainder) {
            return [.update(update)]
        }
        if let assign = assignmentIntent(from: remainder) {
            return [.update(assign)]
        }
        if let priority = priorityIntent(from: remainder) {
            return [.update(priority)]
        }
        if let status = statusIntent(from: remainder) {
            return [.update(status)]
        }
        if let create = createIntent(from: remainder, commandPrefixes: ["create", "add", "new"]) {
            return [.create(create)]
        }

        return [.create(createIntent(fromDescription: remainder))]
    }

    private static func explicitTaskPlan(content: String) -> [VisorTaskIntent]? {
        if let split = splitIntent(from: content) {
            return [.split(split)]
        }
        if let cancel = cancelIntent(from: content) {
            return [.cancel(cancel)]
        }
        if let update = updateIntent(from: content) {
            return [.update(update)]
        }
        if let assign = assignmentIntent(from: content) {
            return [.update(assign)]
        }
        if let priority = priorityIntent(from: content) {
            return [.update(priority)]
        }
        if let status = statusIntent(from: content) {
            return [.update(status)]
        }
        if let create = createIntent(
            from: content,
            commandPrefixes: ["create task", "add task", "new task", "create todo", "создай задачу", "добавь задачу"]
        ) {
            return [.create(create)]
        }
        return nil
    }

    private static func createIntent(from value: String, commandPrefixes: [String]) -> VisorTaskCreateIntent? {
        let lowercased = value.lowercased()
        for prefix in commandPrefixes {
            guard lowercased.hasPrefix(prefix) else {
                continue
            }

            let suffix = value.dropFirst(prefix.count)
            let description = normalizeWhitespace(String(suffix).trimmingCharacters(in: CharacterSet(charactersIn: " :")))
            guard !description.isEmpty else {
                return nil
            }
            return createIntent(fromDescription: description)
        }
        return nil
    }

    private static func createIntent(fromDescription description: String) -> VisorTaskCreateIntent {
        let normalized = normalizeWhitespace(description)
        return VisorTaskCreateIntent(
            title: summarizedTaskTitle(from: normalized),
            description: normalized,
            priority: nil,
            actorId: nil,
            teamId: nil
        )
    }

    private static func cancelIntent(from value: String) -> VisorTaskCancelIntent? {
        let pattern = #"(?i)^(?:/task\s+)?(?:cancel|drop|remove|отмени)\s+(?:task\s+)?#?([A-Za-z0-9._-]+)(?:\s+(.*))?$"#
        guard let captures = captures(in: value, pattern: pattern),
              let reference = normalizedReference(captures[0])
        else {
            return nil
        }

        let reason = captures.count > 1 ? normalizeWhitespace(captures[1]) : ""
        return VisorTaskCancelIntent(reference: reference, reason: reason.isEmpty ? nil : reason)
    }

    private static func splitIntent(from value: String) -> VisorTaskSplitIntent? {
        let pattern = #"(?i)^(?:/task\s+)?split\s+(?:task\s+)?#?([A-Za-z0-9._-]+)\s*:?\s+(.+)$"#
        guard let captures = captures(in: value, pattern: pattern),
              let reference = normalizedReference(captures[0])
        else {
            return nil
        }

        let items = captures[1]
            .split(separator: ";")
            .map { normalizeWhitespace(String($0)) }
            .filter { !$0.isEmpty }
        guard !items.isEmpty else {
            return nil
        }

        return VisorTaskSplitIntent(reference: reference, items: Array(items.prefix(12)))
    }

    private static func statusIntent(from value: String) -> VisorTaskUpdateIntent? {
        let patterns = [
            #"(?i)^(?:/task\s+)?(?:mark|set)\s+(?:task\s+)?#?([A-Za-z0-9._-]+)\s+(?:as\s+)?(ready|done|blocked|backlog|needs_review|review|pending_approval|pending approval|cancelled)$"#,
            #"(?i)^(?:/task\s+)?(ready|done|blocked|backlog|needs_review|review|pending_approval|pending approval|cancelled)\s+(?:task\s+)?#?([A-Za-z0-9._-]+)$"#
        ]

        for pattern in patterns {
            guard let captures = captures(in: value, pattern: pattern) else {
                continue
            }

            let first = normalizeWhitespace(captures[0])
            let second = normalizeWhitespace(captures[1])
            let referenceCandidate: String
            let statusCandidate: String
            if normalizedReference(first) != nil {
                referenceCandidate = first
                statusCandidate = second
            } else {
                referenceCandidate = second
                statusCandidate = first
            }

            guard let reference = normalizedReference(referenceCandidate),
                  let normalizedStatus = normalizedStatusToken(statusCandidate)
            else {
                continue
            }

            return VisorTaskUpdateIntent(
                reference: reference,
                title: nil,
                description: nil,
                priority: nil,
                status: normalizedStatus,
                actorId: nil,
                teamId: nil
            )
        }

        return nil
    }

    private static func priorityIntent(from value: String) -> VisorTaskUpdateIntent? {
        let pattern = #"(?i)^(?:/task\s+)?(?:priority|reprioritize|set\s+priority)\s+(?:task\s+)?#?([A-Za-z0-9._-]+)\s+(low|medium|high)$"#
        guard let captures = captures(in: value, pattern: pattern),
              let reference = normalizedReference(captures[0])
        else {
            return nil
        }

        return VisorTaskUpdateIntent(
            reference: reference,
            title: nil,
            description: nil,
            priority: normalizeWhitespace(captures[1]).lowercased(),
            status: nil,
            actorId: nil,
            teamId: nil
        )
    }

    private static func assignmentIntent(from value: String) -> VisorTaskUpdateIntent? {
        let pattern = #"(?i)^(?:/task\s+)?(?:assign|reassign)\s+(?:task\s+)?#?([A-Za-z0-9._-]+)\s+(?:to\s+)?(actor|team)\s+([A-Za-z0-9._-]+)$"#
        guard let captures = captures(in: value, pattern: pattern),
              let reference = normalizedReference(captures[0])
        else {
            return nil
        }

        let kind = normalizeWhitespace(captures[1]).lowercased()
        let id = normalizeWhitespace(captures[2])
        guard !id.isEmpty else {
            return nil
        }

        return VisorTaskUpdateIntent(
            reference: reference,
            title: nil,
            description: nil,
            priority: nil,
            status: nil,
            actorId: kind == "actor" ? id : nil,
            teamId: kind == "team" ? id : nil
        )
    }

    private static func updateIntent(from value: String) -> VisorTaskUpdateIntent? {
        let pattern = #"(?i)^(?:/task\s+)?update\s+(?:task\s+)?#?([A-Za-z0-9._-]+)\s+(.+)$"#
        guard let captures = captures(in: value, pattern: pattern),
              let reference = normalizedReference(captures[0])
        else {
            return nil
        }

        let fields = parseFieldAssignments(captures[1])
        guard !fields.isEmpty else {
            return nil
        }

        let title = fields["title"]
        let description = fields["description"]
        let priority = fields["priority"]?.lowercased()
        let status = fields["status"].flatMap(normalizedStatusToken)
        let actorId = fields["actor"]
        let teamId = fields["team"]

        guard title != nil || description != nil || priority != nil || status != nil || actorId != nil || teamId != nil else {
            return nil
        }

        return VisorTaskUpdateIntent(
            reference: reference,
            title: title,
            description: description,
            priority: priority,
            status: status,
            actorId: actorId,
            teamId: teamId
        )
    }

    private static func parseFieldAssignments(_ raw: String) -> [String: String] {
        let normalized = normalizeWhitespace(raw)
        guard !normalized.isEmpty else {
            return [:]
        }

        var result: [String: String] = [:]
        let segments = normalized.split(separator: ";").map(String.init)
        for segment in segments {
            guard let separator = segment.firstIndex(of: ":") else {
                continue
            }
            let key = normalizeWhitespace(String(segment[..<separator])).lowercased()
            let value = normalizeWhitespace(String(segment[segment.index(after: separator)...]))
            guard !key.isEmpty, !value.isEmpty else {
                continue
            }
            result[key] = value
        }
        return result
    }

    private static func summarizedTaskTitle(from description: String) -> String {
        let separators = CharacterSet(charactersIn: "\n.;:")
        if let splitRange = description.rangeOfCharacter(from: separators) {
            let prefix = normalizeWhitespace(String(description[..<splitRange.lowerBound]))
            if prefix.count >= 6 {
                return String(prefix.prefix(120))
            }
        }
        return String(description.prefix(120))
    }

    private static func normalizedReference(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
    }

    private static func normalizedStatusToken(_ raw: String) -> ProjectTaskStatus? {
        let trimmed = normalizeWhitespace(raw).lowercased()
        switch trimmed {
        case "review":
            return .needsReview
        case "pending approval":
            return .pendingApproval
        default:
            return ProjectTaskStatus(rawValue: trimmed)
        }
    }

    private static func captures(in source: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let nsSource = source as NSString
        let range = NSRange(location: 0, length: nsSource.length)
        guard let match = regex.firstMatch(in: source, options: [], range: range),
              match.numberOfRanges > 1
        else {
            return nil
        }

        return (1..<match.numberOfRanges).compactMap { index in
            let captureRange = match.range(at: index)
            guard captureRange.location != NSNotFound else {
                return nil
            }
            return nsSource.substring(with: captureRange)
        }
    }

    private static func normalizeWhitespace(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
