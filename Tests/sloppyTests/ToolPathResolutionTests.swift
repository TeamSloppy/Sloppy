import Foundation
import Logging
import Testing
@testable import AgentRuntime
@testable import sloppy
@testable import Protocols

@Suite("ToolContext path resolution with extra roots")
struct ToolPathResolutionTests {

    // MARK: - Helpers

    private func makeContext(workspaceRootURL: URL, allowedExecRoots: [String] = [], allowedWriteRoots: [String] = []) -> ToolContext {
        let guardrails = AgentToolsGuardrails(
            allowedWriteRoots: allowedWriteRoots,
            allowedExecRoots: allowedExecRoots
        )
        let policy = AgentToolsPolicy(guardrails: guardrails)
        let tmp = FileManager.default.temporaryDirectory
        return ToolContext(
            agentID: "test-agent",
            sessionID: "session-test",
            policy: policy,
            workspaceRootURL: workspaceRootURL,
            runtime: RuntimeSystem(),
            memoryStore: InMemoryMemoryStore(),
            sessionStore: AgentSessionFileStore(agentsRootURL: tmp),
            agentCatalogStore: AgentCatalogFileStore(agentsRootURL: tmp),
            processRegistry: SessionProcessRegistry(),
            channelSessionStore: ChannelSessionFileStore(workspaceRootURL: tmp),
            store: InMemoryCorePersistenceBuilder().makeStore(config: CoreConfig.test),
            searchProviderService: SearchProviderService(config: CoreConfig.default.searchTools),
            mcpRegistry: MCPClientRegistry(config: CoreConfig.default.mcp),
            logger: Logger(label: "test"),
            projectService: nil,
            configService: nil,
            skillsService: nil,
            lspManager: nil,
            applyAgentMarkdown: nil,
            delegateSubagent: nil
        )
    }

    // MARK: - resolveExecCwd

    @Test("resolveExecCwd accepts absolute path under workspaceRootURL")
    func resolveCwdInsideWorkspace() throws {
        let tmp = FileManager.default.temporaryDirectory
        let workspace = tmp.appendingPathComponent("sloppy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let subdir = workspace.appendingPathComponent("subdir", isDirectory: true)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)

        let context = makeContext(workspaceRootURL: workspace)
        let resolved = context.resolveExecCwd(subdir.path)
        #expect(resolved != nil)
    }

    @Test("resolveExecCwd rejects absolute path outside workspaceRootURL when no extra roots")
    func resolveCwdOutsideWorkspaceNoRoots() throws {
        let tmp = FileManager.default.temporaryDirectory
        let workspace = tmp.appendingPathComponent("sloppy-ws-\(UUID().uuidString)", isDirectory: true)
        let outside = tmp.appendingPathComponent("sloppy-outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: workspace)
            try? FileManager.default.removeItem(at: outside)
        }

        let context = makeContext(workspaceRootURL: workspace)
        let resolved = context.resolveExecCwd(outside.path)
        #expect(resolved == nil)
    }

    @Test("resolveExecCwd accepts worktree path when added to allowedExecRoots")
    func resolveCwdWithWorktreeInExecRoots() throws {
        let tmp = FileManager.default.temporaryDirectory
        let workspace = tmp.appendingPathComponent("sloppy-ws-\(UUID().uuidString)", isDirectory: true)
        let worktree = tmp.appendingPathComponent("sloppy-worktrees-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: workspace)
            try? FileManager.default.removeItem(at: worktree)
        }

        let context = makeContext(workspaceRootURL: workspace, allowedExecRoots: [worktree.path])
        let resolved = context.resolveExecCwd(worktree.path)
        #expect(resolved != nil)
        #expect(resolved?.path == worktree.resolvingSymlinksInPath().path)
    }

    @Test("resolveExecCwd accepts subdirectory of allowedExecRoots path")
    func resolveCwdSubdirOfAllowedRoot() throws {
        let tmp = FileManager.default.temporaryDirectory
        let workspace = tmp.appendingPathComponent("sloppy-ws-\(UUID().uuidString)", isDirectory: true)
        let worktree = tmp.appendingPathComponent("sloppy-worktrees-\(UUID().uuidString)", isDirectory: true)
        let subdir = worktree.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: workspace)
            try? FileManager.default.removeItem(at: worktree)
        }

        let context = makeContext(workspaceRootURL: workspace, allowedExecRoots: [worktree.path])
        let resolved = context.resolveExecCwd(subdir.path)
        #expect(resolved != nil)
    }

    // MARK: - resolveReadablePath

    @Test("resolveReadablePath rejects file outside workspace when no extra roots")
    func resolveReadableOutsideNoRoots() throws {
        let tmp = FileManager.default.temporaryDirectory
        let workspace = tmp.appendingPathComponent("sloppy-ws-\(UUID().uuidString)", isDirectory: true)
        let outside = tmp.appendingPathComponent("sloppy-out-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: workspace)
            try? FileManager.default.removeItem(at: outside)
        }

        let context = makeContext(workspaceRootURL: workspace)
        let resolved = context.resolveReadablePath(outside.appendingPathComponent("file.txt").path)
        #expect(resolved == nil)
    }

    @Test("resolveReadablePath accepts file in allowedWriteRoots (repo root)")
    func resolveReadableInWriteRoots() throws {
        let tmp = FileManager.default.temporaryDirectory
        let workspace = tmp.appendingPathComponent("sloppy-ws-\(UUID().uuidString)", isDirectory: true)
        let repoRoot = tmp.appendingPathComponent("sloppy-repo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repoRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: workspace)
            try? FileManager.default.removeItem(at: repoRoot)
        }

        let filePath = repoRoot.appendingPathComponent("Package.swift").path
        let context = makeContext(workspaceRootURL: workspace, allowedWriteRoots: [repoRoot.path])
        let resolved = context.resolveReadablePath(filePath)
        #expect(resolved != nil)
    }

    // MARK: - sessionExtraRoots integration via CoreService

    @Test("invokeToolFromRuntime rejects cwd outside workspace when no extra roots registered")
    func invokeToolRejectsCwdWithoutExtraRoots() async throws {
        let config = CoreConfig.test
        let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let router = CoreRouter(service: service)

        let agentID = "test-extra-roots-agent"
        let agentBody = try JSONEncoder().encode(
            AgentCreateRequest(id: agentID, displayName: "Extra Roots Agent", role: "assistant")
        )
        let agentResp = await router.handle(method: "POST", path: "/v1/agents", body: agentBody)
        #expect(agentResp.status == 201)

        let sessionBody = try JSONEncoder().encode(AgentSessionCreateRequest(title: "test"))
        let sessionResp = await router.handle(method: "POST", path: "/v1/agents/\(agentID)/sessions", body: sessionBody)
        #expect(sessionResp.status == 201)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sessionSummary = try decoder.decode(AgentSessionSummary.self, from: sessionResp.body)
        let sessionID = sessionSummary.id

        let tmp = FileManager.default.temporaryDirectory
        let outsidePath = tmp.appendingPathComponent("outside-\(UUID().uuidString)").path

        let result = await service.invokeToolFromRuntime(
            agentID: agentID,
            sessionID: sessionID,
            request: ToolInvocationRequest(tool: "runtime.exec", arguments: [
                "command": .string("bash"),
                "arguments": .array([.string("-lc"), .string("pwd")]),
                "cwd": .string(outsidePath)
            ])
        )
        #expect(result.ok == false)
        #expect(result.error?.code == "cwd_not_allowed")
    }
}
