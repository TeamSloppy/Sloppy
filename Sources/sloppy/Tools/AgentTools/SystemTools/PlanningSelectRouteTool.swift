import AnyLanguageModel
import Foundation
import Protocols

struct PlanningSelectRouteTool: CoreTool {
    let domain = "planning"
    let title = "Select auto route"
    let status = "fully_functional"
    let name = "planning.select_route"
    let description = "Record the route selected by Auto mode before following that route."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(
                name: "route",
                description: "Selected route id from the Auto route catalog, such as mode-plan, mode-build, mode-debug, mode-ask, or skill:<skill-id>.",
                schema: DynamicGenerationSchema(type: String.self)
            ),
            .init(
                name: "reason",
                description: "Short reason for choosing this route.",
                schema: DynamicGenerationSchema(type: String.self),
                isOptional: true
            )
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        toolFailure(
            tool: name,
            code: "not_available",
            message: "`planning.select_route` is handled by the active runtime turn and is only available in auto mode.",
            retryable: false
        )
    }
}
