import AnyLanguageModel
import Foundation
import Protocols

struct SessionCompleteTool: CoreTool {
    static let toolName = "session.complete"

    let domain = "session"
    let title = "Complete session turn"
    let status = "fully_functional"
    let name = SessionCompleteTool.toolName
    let description = "Explicitly mark the current tool-driven session turn complete after the requested work is finished, blocked, or ready for user input."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(
                name: "summary",
                description: "Brief user-visible completion, blocker, or handoff summary.",
                schema: DynamicGenerationSchema(type: String.self)
            )
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        toolFailure(
            tool: name,
            code: "not_available",
            message: "`session.complete` is handled by the active runtime turn and is only available while the agent is responding.",
            retryable: false
        )
    }
}
