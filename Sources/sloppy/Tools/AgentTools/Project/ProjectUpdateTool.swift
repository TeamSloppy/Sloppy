import AnyLanguageModel
import Foundation
import Protocols

struct ProjectUpdateTool: CoreTool {
    let domain = "project"
    let title = "Update project"
    let status = "fully_functional"
    let name = "project.update"
    let description = "Update an existing dashboard project by ID. Only provided fields are changed."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "projectId", description: "Project ID to update", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "name", description: "New project name", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "description", description: "New project description", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "icon", description: "New project icon", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "actors", description: "Updated list of actor IDs", schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self)), isOptional: true),
            .init(name: "teams", description: "Updated list of team IDs", schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self)), isOptional: true),
            .init(name: "repoPath", description: "Repository path", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "kind", description: "Project kind: project or workspace", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "directoryPaths", description: "Replacement ordered workspace directories", schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self)), isOptional: true),
            .init(name: "autopilotSettings", description: "Partial Autopilot settings update. Omitted/null fields preserve saved values. Read project.current first; set enabled and defaultAgentId plus the required action permissions to configure execution.", schema: ProjectAutopilotToolSettings.schema, isOptional: true),
            .init(name: "automaticTaskPickupEnabled", description: "Enable or pause automatic task pickup.", schema: DynamicGenerationSchema(type: Bool.self), isOptional: true),
            .init(name: "taskLoopMode", description: "Project task loop mode: human or agent.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "isFavorite", description: "Whether the project is pinned to favorites", schema: DynamicGenerationSchema(type: Bool.self), isOptional: true),
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let svc = context.projectService else {
            return toolFailure(tool: name, code: "not_available", message: "Project service not available.", retryable: false)
        }

        let projectId = arguments["projectId"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !projectId.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`projectId` is required.", retryable: false)
        }

        let actors = arguments["actors"]?.asArray?.compactMap(\.asString)
        let teams = arguments["teams"]?.asArray?.compactMap(\.asString)

        let loopMode = trimmedStringArgument(arguments, "taskLoopMode")
        if let value = arguments["taskLoopMode"], value != .null,
           value.asString == nil || (loopMode != nil && ProjectLoopMode(rawValue: loopMode ?? "") == nil) {
            return toolFailure(tool: name, code: "invalid_arguments", message: "taskLoopMode must be human or agent.", retryable: false)
        }
        if let value = arguments["automaticTaskPickupEnabled"], value != .null, value.asBool == nil {
            return toolFailure(tool: name, code: "invalid_arguments", message: "automaticTaskPickupEnabled must be a boolean.", retryable: false)
        }

        do {
            var autopilotSettings: ProjectAutopilotSettings?
            if let patch = arguments["autopilotSettings"], patch != .null {
                let current = try await svc.getProject(id: projectId)
                do {
                    autopilotSettings = try ProjectAutopilotToolSettings.applying(patch, to: current.autopilotSettings)
                } catch {
                    return toolFailure(tool: name, code: "invalid_arguments", message: "autopilotSettings must be a typed settings object with valid fields, modes, permissions and pickup rules. Omit fields to preserve them; use empty agent IDs to clear assignments.", retryable: false)
                }
            }
            let project = try await svc.updateProject(
                projectID: projectId,
                request: ProjectUpdateRequest(
                    name: arguments["name"]?.asString,
                    description: arguments["description"]?.asString,
                    icon: arguments["icon"]?.asString,
                    actors: actors,
                    teams: teams,
                    repoPath: arguments["repoPath"]?.asString,
                    kind: arguments["kind"]?.asString.flatMap(ProjectKind.init(rawValue:)),
                    directoryPaths: arguments["directoryPaths"]?.asArray?.compactMap(\.asString),
                    automaticTaskPickupEnabled: arguments["automaticTaskPickupEnabled"]?.asBool,
                    autopilotSettings: autopilotSettings,
                    taskLoopMode: loopMode.flatMap(ProjectLoopMode.init(rawValue:)),
                    isFavorite: arguments["isFavorite"]?.asBool
                )
            )
            return toolSuccess(tool: name, data: .object([
                "projectId": .string(project.id),
                "name": .string(project.name),
                "description": .string(project.description),
                "autopilotSettings": autopilotSettingsJSONValue(project.autopilotSettings),
                "automaticTaskPickupEnabled": .bool(project.automaticTaskPickupEnabled),
                "taskLoopMode": .string(project.taskLoopMode.rawValue),
                "updatedAt": .string(ISO8601DateFormatter().string(from: project.updatedAt))
            ]))
        } catch {
            return toolFailure(tool: name, code: "update_failed", message: "Failed to update project: \(error.localizedDescription)", retryable: true)
        }
    }
}
