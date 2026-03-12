import AnyLanguageModel
import AgentRuntime
import Foundation
import Logging
import Protocols

// MARK: - CoreTool

/// Bridge protocol that extends AnyLanguageModel's `Tool` for use in the Sloppy runtime.
///
/// Each tool conforms to `CoreTool` and is registered in `ToolRegistry`. The `invoke` method
/// is the adapter entry point called by `ToolExecutionService`; `call(arguments:)` is the
/// AnyLanguageModel-facing stub for future LanguageModelSession integration.
protocol CoreTool: Tool, Sendable where Arguments == GeneratedContent, Output == String {
    var toolID: String { get }
    var domain: String { get }
    var title: String { get }
    var status: String { get }
    /// Additional IDs this tool handles (aliases).
    var toolAliases: [String] { get }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult
}

extension CoreTool {
    var toolID: String { name }
    var toolAliases: [String] { [] }

    func call(arguments: GeneratedContent) async throws -> String { "" }
}

// MARK: - ToolContext

/// Per-invocation context carrying all service dependencies needed by tools.
struct ToolContext: @unchecked Sendable {
    let agentID: String
    let sessionID: String
    let policy: AgentToolsPolicy
    let workspaceRootURL: URL
    let runtime: RuntimeSystem
    let memoryStore: any MemoryStore
    let sessionStore: AgentSessionFileStore
    let agentCatalogStore: AgentCatalogFileStore
    let processRegistry: SessionProcessRegistry
    let channelSessionStore: ChannelSessionFileStore
    let store: any PersistenceStore
    let searchProviderService: SearchProviderService
    let logger: Logger
    let projectService: (any ProjectToolService)?
}

// MARK: - ProjectToolService

/// Operations backed by CoreService that project and actor tools require.
/// CoreService conforms to this protocol to provide actor-isolated access.
protocol ProjectToolService: Sendable {
    func findProjectForChannel(channelId: String, topicId: String?) async -> ProjectRecord?
    func createTask(projectID: String, request: ProjectTaskCreateRequest) async throws -> ProjectRecord
    func updateTask(projectID: String, taskID: String, request: ProjectTaskUpdateRequest) async throws -> ProjectRecord
    func cancelTaskWithReason(projectID: String, taskID: String, reason: String?) async throws -> ProjectRecord
    func getTask(reference: String) async throws -> AgentTaskRecord
    func deliverMessage(channelId: String, content: String) async
    func actorBoard() async throws -> ActorBoardSnapshot
}

// MARK: - Result helpers

func toolSuccess(tool: String, data: JSONValue) -> ToolInvocationResult {
    ToolInvocationResult(tool: tool, ok: true, data: data)
}

func toolFailure(tool: String, code: String, message: String, retryable: Bool) -> ToolInvocationResult {
    ToolInvocationResult(
        tool: tool,
        ok: false,
        error: ToolErrorPayload(code: code, message: message, retryable: retryable)
    )
}

// MARK: - GenerationSchema helpers

extension GenerationSchema {
    /// Builds an object schema from a list of DynamicGenerationSchema.Property descriptors.
    static func objectSchema(_ properties: [DynamicGenerationSchema.Property]) -> GenerationSchema {
        let schema = DynamicGenerationSchema(name: "Arguments", properties: properties)
        return (try? GenerationSchema(root: schema, dependencies: [])) ?? String.generationSchema
    }
}
