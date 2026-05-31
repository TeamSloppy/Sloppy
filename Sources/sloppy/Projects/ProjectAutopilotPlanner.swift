import Foundation
import Protocols

struct ProjectAutopilotPlanner: Sendable {
    struct PlannedTask: Sendable, Equatable {
        var temporaryID: String
        var title: String
        var description: String
        var kind: ProjectTaskKind
        var tags: [String]
        var dependsOnTemporaryIds: [String]
        var verificationHints: [String]
    }

    enum PlannerError: Error, LocalizedError {
        case noProvider
        case emptyOutput
        case invalidOutput(String)

        var errorDescription: String? {
            switch self {
            case .noProvider:
                return "No model provider is configured for Autopilot planning."
            case .emptyOutput:
                return "Autopilot planner returned no output."
            case .invalidOutput(let reason):
                return "Autopilot planner returned invalid output: \(reason)"
            }
        }
    }

    private struct Output: Decodable {
        var subtasks: [Subtask]
    }

    private struct Subtask: Decodable {
        var id: String
        var title: String
        var description: String
        var kind: ProjectTaskKind?
        var tags: [String]?
        var dependsOn: [String]?
        var verificationHints: [String]?
    }

    var complete: @Sendable (String) async throws -> String?

    func plan(project: ProjectRecord, rootTask: ProjectTask) async throws -> [PlannedTask] {
        guard let output = try await complete(Self.prompt(project: project, rootTask: rootTask)) else {
            throw PlannerError.noProvider
        }
        return try Self.decode(output)
    }

    static func decode(_ raw: String) throws -> [PlannedTask] {
        let trimmed = stripCodeFence(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PlannerError.emptyOutput
        }
        guard let data = trimmed.data(using: .utf8) else {
            throw PlannerError.invalidOutput("Output is not UTF-8.")
        }
        let output: Output
        do {
            output = try JSONDecoder().decode(Output.self, from: data)
        } catch {
            throw PlannerError.invalidOutput(error.localizedDescription)
        }
        guard !output.subtasks.isEmpty else {
            throw PlannerError.invalidOutput("At least one subtask is required.")
        }

        var seen = Set<String>()
        let ids = Set(output.subtasks.map { $0.id.trimmingCharacters(in: .whitespacesAndNewlines) })
        var planned: [PlannedTask] = []
        for subtask in output.subtasks {
            let id = subtask.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else {
                throw PlannerError.invalidOutput("Subtask id is required.")
            }
            guard seen.insert(id).inserted else {
                throw PlannerError.invalidOutput("Duplicate subtask id \(id).")
            }
            let title = subtask.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                throw PlannerError.invalidOutput("Subtask \(id) title is required.")
            }
            let dependencies = (subtask.dependsOn ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            for dependency in dependencies {
                guard dependency != id else {
                    throw PlannerError.invalidOutput("Subtask \(id) depends on itself.")
                }
                guard ids.contains(dependency) else {
                    throw PlannerError.invalidOutput("Subtask \(id) depends on unknown id \(dependency).")
                }
            }
            planned.append(
                PlannedTask(
                    temporaryID: id,
                    title: String(title.prefix(240)),
                    description: String(subtask.description.trimmingCharacters(in: .whitespacesAndNewlines).prefix(8_000)),
                    kind: subtask.kind ?? .execution,
                    tags: normalizedList(subtask.tags ?? [], limit: 24, itemLimit: 80),
                    dependsOnTemporaryIds: normalizedList(dependencies, limit: 64, itemLimit: 120),
                    verificationHints: normalizedList(subtask.verificationHints ?? [], limit: 12, itemLimit: 240)
                )
            )
        }
        return planned
    }

    static func prompt(project: ProjectRecord, rootTask: ProjectTask) -> String {
        """
        You are Project Autopilot planner. Return strict JSON only.

        JSON schema:
        {
          "subtasks": [
            {
              "id": "short-stable-id",
              "title": "Concrete task title",
              "description": "Clear task details and acceptance notes",
              "kind": "planning|execution|bugfix",
              "tags": ["autopilot"],
              "dependsOn": ["other-short-stable-id"],
              "verificationHints": ["Command or evidence required"]
            }
          ]
        }

        Project: \(project.name)
        Project description: \(project.description.isEmpty ? "(none)" : project.description)
        Root task title: \(rootTask.title)
        Root task description:
        \(rootTask.description.isEmpty ? "(none)" : rootTask.description)

        Break root task into minimal executable subtasks. Use dependencies only when order truly matters.
        """
    }

    private static func stripCodeFence(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else {
            return raw
        }
        var lines = trimmed.components(separatedBy: .newlines)
        if !lines.isEmpty {
            lines.removeFirst()
        }
        if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    private static func normalizedList(_ values: [String], limit: Int, itemLimit: Int) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let normalized = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(itemLimit))
            guard !normalized.isEmpty else {
                continue
            }
            let key = normalized.lowercased()
            guard seen.insert(key).inserted else {
                continue
            }
            result.append(normalized)
            if result.count >= limit {
                break
            }
        }
        return result
    }
}
