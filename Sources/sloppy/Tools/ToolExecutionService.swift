import Foundation
import AgentRuntime
import Logging
import Protocols

final class ToolExecutionService: @unchecked Sendable {
    private let runtime: RuntimeSystem
    private let memoryStore: any MemoryStore
    private let sessionStore: AgentSessionFileStore
    private let agentCatalogStore: AgentCatalogFileStore
    private let agentSkillsStore: AgentSkillsFileStore?
    private let processRegistry: SessionProcessRegistry
    private let browserService: BrowserCDPService
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
    /// `(agentID, field, markdown)` — used to build per-invocation `ToolContext.applyAgentMarkdown`.
    var applyAgentMarkdown: ((String, AgentMarkdownDocumentField, String) async throws -> Void)?
    var delegateSubagent: (@Sendable (String, String, String, String?, [String]?, String?) async -> String?)?

    init(
        workspaceRootURL: URL,
        runtime: RuntimeSystem,
        memoryStore: any MemoryStore,
        sessionStore: AgentSessionFileStore,
        agentCatalogStore: AgentCatalogFileStore,
        agentSkillsStore: AgentSkillsFileStore? = nil,
        processRegistry: SessionProcessRegistry,
        browserConfig: CoreConfig.Browser = CoreConfig.Browser(),
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
        self.agentSkillsStore = agentSkillsStore
        self.processRegistry = processRegistry
        self.browserService = BrowserCDPService(config: browserConfig, workspaceRootURL: workspaceRootURL)
        self.channelSessionStore = channelSessionStore
        self.store = store
        self.searchProviderService = searchProviderService
        self.mcpRegistry = mcpRegistry
        self.lspManager = LSPServerManager(config: lspConfig, workspaceRootURL: workspaceRootURL)
        self.logger = logger
        self.registry = ToolRegistry.makeDefault()
        self.applyAgentMarkdown = nil
        self.delegateSubagent = nil
    }

    func updateWorkspaceRootURL(_ url: URL) {
        self.workspaceRootURL = url
    }

    func updateBrowserConfig(_ config: CoreConfig.Browser) async {
        await browserService.updateConfig(config, workspaceRootURL: workspaceRootURL)
    }

    func updateLSPConfig(_ config: CoreConfig.LSP) async {
        await lspManager.updateConfig(config, workspaceRootURL: workspaceRootURL)
    }

    func updateStore(_ store: any PersistenceStore) {
        self.store = store
    }

    func cleanupSessionProcesses(_ sessionID: String) async {
        await processRegistry.cleanup(sessionID: sessionID)
        await browserService.cleanup(sessionID: sessionID)
    }

    func shutdown() async {
        await processRegistry.shutdown()
        await browserService.shutdown()
        await lspManager.shutdown()
    }

    func activeProcessCount(sessionID: String) async -> Int {
        await processRegistry.activeCount(sessionID: sessionID)
    }

    func invoke(
        agentID: String,
        sessionID: String,
        request: ToolInvocationRequest,
        policy: AgentToolsPolicy,
        currentDirectoryURL: URL? = nil
    ) async -> ToolInvocationResult {
        let context = makeContext(
            agentID: agentID,
            sessionID: sessionID,
            policy: policy,
            currentDirectoryURL: currentDirectoryURL
        )
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

    func makeContext(
        agentID: String,
        sessionID: String,
        policy: AgentToolsPolicy,
        currentDirectoryURL: URL? = nil
    ) -> ToolContext {
        let boundApply = applyAgentMarkdown.map { handler in
            { (field: AgentMarkdownDocumentField, markdown: String) async throws in
                try await handler(agentID, field, markdown)
            }
        }
        return ToolContext(
            agentID: agentID,
            sessionID: sessionID,
            policy: policy,
            workspaceRootURL: workspaceRootURL,
            currentDirectoryURL: currentDirectoryURL,
            runtime: runtime,
            memoryStore: memoryStore,
            sessionStore: sessionStore,
            agentCatalogStore: agentCatalogStore,
            agentSkillsStore: agentSkillsStore,
            processRegistry: processRegistry,
            channelSessionStore: channelSessionStore,
            store: store,
            searchProviderService: searchProviderService,
            mcpRegistry: mcpRegistry,
            logger: logger,
            projectService: projectService,
            configService: configService,
            skillsService: skillsService,
            lspManager: lspManager,
            browserService: browserService,
            applyAgentMarkdown: boundApply,
            delegateSubagent: delegateSubagent
        )
    }
}
