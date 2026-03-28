import AnyLanguageModel
import Foundation
import Protocols

struct ProjectCreateTool: CoreTool {
    let domain = "project"
    let title = "Create project"
    let status = "fully_functional"
    let name = "project.create"
    let description = "Create a new dashboard project."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "name", description: "Project name", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "description", description: "Project description", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "actors", description: "List of actor IDs to assign", schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self)), isOptional: true),
            .init(name: "teams", description: "List of team IDs to assign", schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self)), isOptional: true),
            .init(name: "repoUrl", description: "Repository URL", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let svc = context.projectService else {
            return toolFailure(tool: name, code: "not_available", message: "Project service not available.", retryable: false)
        }

        let projectName = arguments["name"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !projectName.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`name` is required.", retryable: false)
        }

        let actors = arguments["actors"]?.asArray?.compactMap(\.asString)
        let teams = arguments["teams"]?.asArray?.compactMap(\.asString)

        do {
            let project = try await svc.createProject(
                ProjectCreateRequest(
                    name: projectName,
                    description: arguments["description"]?.asString,
                    actors: actors,
                    teams: teams,
                    repoUrl: arguments["repoUrl"]?.asString
                )
            )
            return toolSuccess(tool: name, data: .object([
                "projectId": .string(project.id),
                "name": .string(project.name),
                "description": .string(project.description),
                "createdAt": .string(ISO8601DateFormatter().string(from: project.createdAt))
            ]))
        } catch {
            return toolFailure(tool: name, code: "create_failed", message: "Failed to create project: \(error.localizedDescription)", retryable: true)
        }
    }
}
