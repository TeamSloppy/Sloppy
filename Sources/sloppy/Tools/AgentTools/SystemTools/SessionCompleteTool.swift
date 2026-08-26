import AnyLanguageModel
import Foundation
import Protocols

struct SessionCompleteTool: CoreTool {
    static let toolName = "session.complete"

    let domain = "session"
    let title = "Complete session turn"
    let status = "fully_functional"
    let name = SessionCompleteTool.toolName
    let description = "Finish the active session turn with a typed outcome. Completed Build and Debug turns must reference verification evidence IDs returned by successful tools in the current turn."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(
                name: "status",
                description: "Terminal outcome: completed, blocked, or waiting_input.",
                schema: DynamicGenerationSchema(type: String.self)
            ),
            .init(
                name: "summary",
                description: "Brief user-visible completion, blocker, or handoff summary.",
                schema: DynamicGenerationSchema(type: String.self)
            ),
            .init(
                name: "verification",
                description: "Optional user-facing descriptions of checks performed and their results.",
                schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self)),
                isOptional: true
            ),
            .init(
                name: "verificationEvidenceIds",
                description: "Evidence IDs returned by successful runtime.exec, runtime.process start, browser.screenshot, or computer.screenshot calls in the current turn. Required for completed Build and Debug turns.",
                schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self)),
                isOptional: true
            ),
            .init(
                name: "limitations",
                description: "Known blockers, skipped checks, or environment limitations. Required when status is blocked.",
                schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self)),
                isOptional: true
            ),
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
