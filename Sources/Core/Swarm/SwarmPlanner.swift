import Foundation
import Protocols

struct SwarmPlannedSubtask: Codable, Sendable, Equatable {
    var swarmTaskId: String
    var title: String
    var objective: String
    var depth: Int
    var dependencyIds: [String]
    var tools: [String]
}

enum SwarmPlannerError: Error {
    case modelUnavailable
    case invalidResponse
}

struct SwarmPlanner {
    typealias Completion = @Sendable (_ prompt: String, _ maxTokens: Int) async -> String?

    private let complete: Completion

    init(complete: @escaping Completion) {
        self.complete = complete
    }

    func plan(rootTask: ProjectTask, actorLevels: [[String]]) async throws -> [SwarmPlannedSubtask] {
        let levelsPreview = actorLevels.enumerated().map { index, actors in
            "depth \(index + 1): \(actors.joined(separator: ", "))"
        }.joined(separator: "\n")

        let prompt =
            """
            [swarm_planner_v1]
            Build a strict JSON object with key "subtasks" only.
            Each subtask item fields:
            - swarmTaskId: string (unique, lowercase slug-like)
            - title: string
            - objective: string
            - depth: integer >= 1
            - dependencyIds: string[]
            - tools: string[]

            Root task title: \(rootTask.title)
            Root task description:
            \(rootTask.description)

            Actor hierarchy levels:
            \(levelsPreview)

            Constraints:
            - depth must not exceed \(max(actorLevels.count, 1))
            - at least one subtask per level
            - dependencyIds must reference existing swarmTaskId values
            - return JSON only (no markdown, no comments)
            """

        guard let raw = await complete(prompt, 1_400) else {
            throw SwarmPlannerError.modelUnavailable
        }

        let json = extractJSON(from: raw) ?? raw
        guard let data = json.data(using: .utf8) else {
            throw SwarmPlannerError.invalidResponse
        }

        struct Response: Codable {
            var subtasks: [SwarmPlannedSubtask]
        }

        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw SwarmPlannerError.invalidResponse
        }

        let normalized = normalize(decoded.subtasks, maxDepth: max(actorLevels.count, 1))
        guard !normalized.isEmpty else {
            throw SwarmPlannerError.invalidResponse
        }

        let ids = Set(normalized.map(\.swarmTaskId))
        guard normalized.allSatisfy({ task in
            !task.title.isEmpty
                && !task.objective.isEmpty
                && task.depth >= 1
                && task.depth <= max(actorLevels.count, 1)
                && task.dependencyIds.allSatisfy { ids.contains($0) }
        }) else {
            throw SwarmPlannerError.invalidResponse
        }

        return normalized
    }

    private func normalize(_ tasks: [SwarmPlannedSubtask], maxDepth: Int) -> [SwarmPlannedSubtask] {
        var seen: Set<String> = []
        var result: [SwarmPlannedSubtask] = []

        for var task in tasks {
            task.swarmTaskId = task.swarmTaskId
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
            task.objective = task.objective.trimmingCharacters(in: .whitespacesAndNewlines)
            task.depth = min(max(task.depth, 1), maxDepth)
            task.tools = task.tools.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            task.dependencyIds = task.dependencyIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            guard !task.swarmTaskId.isEmpty, seen.insert(task.swarmTaskId).inserted else {
                continue
            }
            if task.tools.isEmpty {
                task.tools = ["shell", "file", "exec", "browser"]
            }
            result.append(task)
        }

        return result
    }

    private func extractJSON(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
            return trimmed
        }

        let normalized = trimmed.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("```") else {
            return nil
        }

        let withoutPrefix: String
        if normalized.hasPrefix("```json\n") {
            withoutPrefix = String(normalized.dropFirst("```json\n".count))
        } else if normalized.hasPrefix("```\n") {
            withoutPrefix = String(normalized.dropFirst("```\n".count))
        } else {
            return nil
        }

        guard let range = withoutPrefix.range(of: "\n```") else {
            return nil
        }
        return String(withoutPrefix[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
