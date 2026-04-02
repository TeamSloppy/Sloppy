import Foundation
import AgentRuntime
import Logging
import Protocols

final class ToolExecutionService: @unchecked Sendable {
    private let runtime: RuntimeSystem
    private let memoryStore: any MemoryStore
    private let sessionStore: AgentSessionFileStore
    private let agentCatalogStore: AgentCatalogFileStore
    private let processRegistry: SessionProcessRegistry
    private let channelSessionStore: ChannelSessionFileStore
    private var store: any PersistenceStore
    private let searchProviderService: SearchProviderService
    private let mcpRegistry: MCPClientRegistry
    private let logger: Logger
    private var workspaceRootURL: URL
    private let registry: ToolRegistry
    private var lspManager: LSPServerManager
    var projectService: (any ProjectToolService)?
    var configService: (any RuntimeConfigToolService)?
    var skillsService: (any SkillsToolService)?

    init(
        workspaceRootURL: URL,
        runtime: RuntimeSystem,
        memoryStore: any MemoryStore,
        sessionStore: AgentSessionFileStore,
        agentCatalogStore: AgentCatalogFileStore,
        processRegistry: SessionProcessRegistry,
        channelSessionStore: ChannelSessionFileStore,
        store: any PersistenceStore,
        searchProviderService: SearchProviderService,
        mcpRegistry: MCPClientRegistry,
        lspConfig: CoreConfig.LSP = CoreConfig.LSP(),
        logger: Logger = Logger(label: "sloppy.core.tools")
    ) {
        self.workspaceRootURL = workspaceRootURL
        self.runtime = runtime
        self.memoryStore = memoryStore
        self.sessionStore = sessionStore
        self.agentCatalogStore = agentCatalogStore
        self.processRegistry = processRegistry
        self.channelSessionStore = channelSessionStore
        self.store = store
        self.searchProviderService = searchProviderService
        self.mcpRegistry = mcpRegistry
        self.lspManager = LSPServerManager(config: lspConfig, workspaceRootURL: workspaceRootURL)
        self.logger = logger
        self.registry = ToolRegistry.makeDefault()
    }

    func updateWorkspaceRootURL(_ url: URL) {
        self.workspaceRootURL = url
    }

    func updateLSPConfig(_ config: CoreConfig.LSP) async {
        await lspManager.updateConfig(config, workspaceRootURL: workspaceRootURL)
    }

    func updateStore(_ store: any PersistenceStore) {
        self.store = store
    }

    func cleanupSessionProcesses(_ sessionID: String) async {
        await processRegistry.cleanup(sessionID: sessionID)
    }

    func shutdown() async {
        await processRegistry.shutdown()
        await lspManager.shutdown()
    }

    func activeProcessCount(sessionID: String) async -> Int {
        await processRegistry.activeCount(sessionID: sessionID)
    }

    func invoke(
        agentID: String,
        sessionID: String,
        request: ToolInvocationRequest,
        policy: AgentToolsPolicy
    ) async -> ToolInvocationResult {
        let context = makeContext(agentID: agentID, sessionID: sessionID, policy: policy)
        if let result = await registry.invoke(request: request, context: context) {
            return result
        }
        if let result = try? await mcpRegistry.invokeDynamicTool(
            toolID: request.tool.trimmingCharacters(in: .whitespacesAndNewlines),
            arguments: request.arguments
        ) {
            return result
        }
        let toolID = request.tool.trimmingCharacters(in: .whitespacesAndNewlines)
        return ToolInvocationResult(
            tool: toolID,
            ok: false,
            error: ToolErrorPayload(code: "unknown_tool", message: "Unknown tool '\(toolID)'", retryable: false)
        )
    }

    func makeContext(agentID: String, sessionID: String, policy: AgentToolsPolicy) -> ToolContext {
        ToolContext(
            agentID: agentID,
            sessionID: sessionID,
            policy: policy,
            workspaceRootURL: workspaceRootURL,
            runtime: runtime,
            memoryStore: memoryStore,
            sessionStore: sessionStore,
            agentCatalogStore: agentCatalogStore,
            processRegistry: processRegistry,
            channelSessionStore: channelSessionStore,
            store: store,
            searchProviderService: searchProviderService,
            mcpRegistry: mcpRegistry,
            logger: logger,
            projectService: projectService,
            configService: configService,
            skillsService: skillsService,
            lspManager: lspManager
        )
    }
}
