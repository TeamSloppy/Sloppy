import AnyLanguageModel
import AgentRuntime
import Foundation
import Logging
import PluginSDK
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
    let channelID: String?
    let policy: AgentToolsPolicy
    let workspaceRootURL: URL
    let readOnlyRoots: [String]
    let currentDirectoryURL: URL
    let currentProjectID: String?
    let environmentOverrides: [String: String]
    let runtime: RuntimeSystem
    let memoryStore: any MemoryStore
    let sessionStore: AgentSessionFileStore
    let agentCatalogStore: AgentCatalogFileStore
    let agentSkillsStore: AgentSkillsFileStore?
    let processRegistry: SessionProcessRegistry
    let browserService: BrowserCDPService
    let channelSessionStore: ChannelSessionFileStore
    let store: any PersistenceStore
    let searchProviderService: SearchProviderService
    let mcpRegistry: MCPClientRegistry
    let logger: Logger
    let projectService: (any ProjectToolService)?
    let configService: (any RuntimeConfigToolService)?
    let skillsService: (any SkillsToolService)?
    let lspManager: LSPServerManager?
    /// When set, updates `USER.md` / `MEMORY.md` through the same validation path as the HTTP API.
    let applyAgentMarkdown: ((AgentMarkdownDocumentField, String) async throws -> Void)?
    /// Runs an isolated subagent session; set by `CoreService.configureToolExecutionServices`.
    let delegateSubagent: (@Sendable (String, String, String, String?, [String]?, String?, String?) async -> String?)?

    init(
        agentID: String,
        sessionID: String,
        channelID: String? = nil,
        policy: AgentToolsPolicy,
        workspaceRootURL: URL,
        readOnlyRoots: [String] = [],
        currentDirectoryURL: URL? = nil,
        currentProjectID: String? = nil,
        environmentOverrides: [String: String] = [:],
        runtime: RuntimeSystem,
        memoryStore: any MemoryStore,
        sessionStore: AgentSessionFileStore,
        agentCatalogStore: AgentCatalogFileStore,
        agentSkillsStore: AgentSkillsFileStore?,
        processRegistry: SessionProcessRegistry,
        channelSessionStore: ChannelSessionFileStore,
        store: any PersistenceStore,
        searchProviderService: SearchProviderService,
        mcpRegistry: MCPClientRegistry,
        logger: Logger,
        projectService: (any ProjectToolService)?,
        configService: (any RuntimeConfigToolService)?,
        skillsService: (any SkillsToolService)?,
        lspManager: LSPServerManager?,
        browserService: BrowserCDPService? = nil,
        applyAgentMarkdown: ((AgentMarkdownDocumentField, String) async throws -> Void)?,
        delegateSubagent: (@Sendable (String, String, String, String?, [String]?, String?, String?) async -> String?)?
    ) {
        self.agentID = agentID
        self.sessionID = sessionID
        self.channelID = channelID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.policy = policy
        self.workspaceRootURL = workspaceRootURL
        self.readOnlyRoots = readOnlyRoots
        self.currentDirectoryURL = currentDirectoryURL ?? workspaceRootURL
        let trimmedProjectID = currentProjectID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.currentProjectID = trimmedProjectID?.isEmpty == false ? trimmedProjectID : nil
        self.environmentOverrides = environmentOverrides
        self.runtime = runtime
        self.memoryStore = memoryStore
        self.sessionStore = sessionStore
        self.agentCatalogStore = agentCatalogStore
        self.agentSkillsStore = agentSkillsStore
        self.processRegistry = processRegistry
        self.browserService = browserService ?? BrowserCDPService(config: .init(), workspaceRootURL: workspaceRootURL)
        self.channelSessionStore = channelSessionStore
        self.store = store
        self.searchProviderService = searchProviderService
        self.mcpRegistry = mcpRegistry
        self.logger = logger
        self.projectService = projectService
        self.configService = configService
        self.skillsService = skillsService
        self.lspManager = lspManager
        self.applyAgentMarkdown = applyAgentMarkdown
        self.delegateSubagent = delegateSubagent
    }
}

// MARK: - ProjectToolService

/// Operations backed by CoreService that project and actor tools require.
/// CoreService conforms to this protocol to provide actor-isolated access.
protocol ProjectToolService: Sendable {
    func findProjectForChannel(channelId: String, topicId: String?) async -> ProjectRecord?
    func getProject(id: String) async throws -> ProjectRecord
    func createTask(projectID: String, request: ProjectTaskCreateRequest) async throws -> ProjectRecord
    func updateTask(projectID: String, taskID: String, request: ProjectTaskUpdateRequest) async throws -> ProjectRecord
    func cancelTaskWithReason(projectID: String, taskID: String, reason: String?) async throws -> ProjectRecord
    func deleteTask(projectID: String, taskID: String) async throws -> ProjectRecord
    func getTask(reference: String) async throws -> AgentTaskRecord
    func createTaskClarification(projectID: String, taskID: String, request: TaskClarificationCreateRequest) async throws -> TaskClarificationRecord
    func deliverMessage(channelId: String, content: String) async
    func actorBoard() async throws -> ActorBoardSnapshot
    func requestProjectMemoryCheckpoint(agentID: String, sessionID: String, projectID: String, taskID: String, status: String) async

    func listAllProjects() async -> [ProjectRecord]
    func createProject(_ request: ProjectCreateRequest) async throws -> ProjectCreateResult
    func updateProject(projectID: String, request: ProjectUpdateRequest) async throws -> ProjectRecord
    func linkProjectChannel(projectID: String, request: ProjectChannelLinkRequest) async throws -> ProjectChannelLinkResponse
    func deleteProject(projectID: String) async throws

    func listWorkflowDefinitions(projectID: String) async throws -> [WorkflowDefinition]
    func getWorkflowDefinition(projectID: String, workflowID: String) async throws -> WorkflowDefinition
    func createWorkflowDefinition(projectID: String, request: WorkflowDefinitionUpsertRequest) async throws -> WorkflowDefinition
    func updateWorkflowDefinition(projectID: String, workflowID: String, request: WorkflowDefinitionUpsertRequest) async throws -> WorkflowDefinition
    func startWorkflowRun(projectID: String, workflowID: String, request: WorkflowRunCreateRequest) async throws -> WorkflowRunDetail
    func getWorkflowRunDetail(projectID: String, runID: String) async throws -> WorkflowRunDetail
    func validateWorkflowDefinition(_ definition: WorkflowDefinition) -> [WorkflowValidationIssue]
}

enum ProjectToolServiceWorkflowError: Error {
    case unsupported
}

extension ProjectToolService {
    func listWorkflowDefinitions(projectID _: String) async throws -> [WorkflowDefinition] {
        throw ProjectToolServiceWorkflowError.unsupported
    }

    func getWorkflowDefinition(projectID _: String, workflowID _: String) async throws -> WorkflowDefinition {
        throw ProjectToolServiceWorkflowError.unsupported
    }

    func createWorkflowDefinition(projectID _: String, request _: WorkflowDefinitionUpsertRequest) async throws -> WorkflowDefinition {
        throw ProjectToolServiceWorkflowError.unsupported
    }

    func updateWorkflowDefinition(projectID _: String, workflowID _: String, request _: WorkflowDefinitionUpsertRequest) async throws -> WorkflowDefinition {
        throw ProjectToolServiceWorkflowError.unsupported
    }

    func startWorkflowRun(projectID _: String, workflowID _: String, request _: WorkflowRunCreateRequest) async throws -> WorkflowRunDetail {
        throw ProjectToolServiceWorkflowError.unsupported
    }

    func getWorkflowRunDetail(projectID _: String, runID _: String) async throws -> WorkflowRunDetail {
        throw ProjectToolServiceWorkflowError.unsupported
    }

    func validateWorkflowDefinition(_ definition: WorkflowDefinition) -> [WorkflowValidationIssue] {
        WorkflowRunner().validate(definition: definition)
    }
}

protocol RuntimeConfigToolService: Sendable {
    func runtimeConfig() async -> CoreConfig
    func updateRuntimeConfig(_ config: CoreConfig) async throws -> CoreConfig
}

protocol SkillsToolService: Sendable {
    func fetchSkillsRegistry(search: String?, sort: String, limit: Int, offset: Int) async throws -> SkillsRegistryResponse
    func listAgentSkills(agentID: String) async throws -> AgentSkillsResponse
    func installAgentSkill(agentID: String, request: SkillInstallRequest) async throws -> InstalledSkill
    func uninstallAgentSkill(agentID: String, skillID: String) async throws
    func saveAgentSkill(agentID: String, request: SkillSaveRequest) async throws -> SkillSaveResult
}

struct SkillSaveRequest: Sendable {
    var owner: String
    var repo: String
    var skillMarkdown: String
    var files: [String: String]
    var userInvocable: Bool?
    var allowedTools: [String]?
    var context: SkillContext?
    var agent: String?
    var autoRoute: String?

    init(
        owner: String = "local",
        repo: String,
        skillMarkdown: String,
        files: [String: String] = [:],
        userInvocable: Bool? = nil,
        allowedTools: [String]? = nil,
        context: SkillContext? = nil,
        agent: String? = nil,
        autoRoute: String? = nil
    ) {
        self.owner = owner
        self.repo = repo
        self.skillMarkdown = skillMarkdown
        self.files = files
        self.userInvocable = userInvocable
        self.allowedTools = allowedTools
        self.context = context
        self.agent = agent
        self.autoRoute = autoRoute
    }
}

struct SkillSaveResult: Sendable {
    var skill: InstalledSkill
    var created: Bool
}

// MARK: - Argument resolution helpers

private let sessionIDPlaceholders: Set<String> = ["current", "self", "this"]

func resolveSessionID(_ raw: String?, context: ToolContext) -> String {
    guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
          !raw.isEmpty,
          !sessionIDPlaceholders.contains(raw.lowercased())
    else {
        return context.sessionID
    }
    return raw
}

// MARK: - Result helpers

func toolSuccess(tool: String, data: JSONValue) -> ToolInvocationResult {
    ToolInvocationResult(tool: tool, ok: true, data: data)
}

func toolFailure(tool: String, code: String, message: String, retryable: Bool, hint: String? = nil) -> ToolInvocationResult {
    ToolInvocationResult(
        tool: tool,
        ok: false,
        error: ToolErrorPayload(code: code, message: message, retryable: retryable, hint: hint)
    )
}

// MARK: - GenerationSchema helpers

extension GenerationSchema {
    /// Builds an object schema from a list of DynamicGenerationSchema.Property descriptors.
    static func objectSchema(_ properties: [DynamicGenerationSchema.Property]) -> GenerationSchema {
        let schema = DynamicGenerationSchema(name: "Arguments", properties: properties)
        guard let generated = try? GenerationSchema(root: schema, dependencies: []) else {
            return String.generationSchema
        }
        let normalized = ModelToolSchemaNormalizer.providerSafeObjectSchema(generated)
        guard let data = try? JSONSerialization.data(withJSONObject: normalized),
              let decoded = try? JSONDecoder().decode(GenerationSchema.self, from: data) else {
            return generated
        }
        return decoded
    }
}
