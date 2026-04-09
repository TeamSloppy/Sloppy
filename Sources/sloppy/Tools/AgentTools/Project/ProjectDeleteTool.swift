import AnyLanguageModel
import Foundation
import Protocols

struct ProjectDeleteTool: CoreTool {
    let domain = "project"
    let title = "Delete project"
    let status = "fully_functional"
    let name = "project.delete"
    let description = "Delete a dashboard project by ID. All nested tasks and channels will be removed."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "projectId", description: "Project ID to delete", schema: DynamicGenerationSchema(type: String.self)),
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

        do {
            try await svc.deleteProject(projectID: projectId)
            return toolSuccess(tool: name, data: .object([
                "projectId": .string(projectId),
                "deleted": .bool(true)
            ]))
        } catch {
            return toolFailure(tool: name, code: "delete_failed", message: "Failed to delete project: \(error.localizedDescription)", retryable: true)
        }
    }
}
