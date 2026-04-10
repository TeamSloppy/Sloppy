import Foundation
import Logging
import Testing
@testable import AgentRuntime
@testable import sloppy
@testable import Protocols

@Suite("files.read and filesystem error mapping")
struct FilesReadToolTests {

    private func makeContext(workspaceRootURL: URL) -> ToolContext {
        let guardrails = AgentToolsGuardrails()
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

    @Test("files.read returns not_found for missing file")
    func readMissingFile() async throws {
        let tmp = FileManager.default.temporaryDirectory
        let workspace = tmp.appendingPathComponent("sloppy-files-read-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let context = makeContext(workspaceRootURL: workspace)
        let tool = FilesReadTool()
        let result = await tool.invoke(arguments: ["path": .string("does-not-exist.txt")], context: context)

        #expect(result.ok == false)
        #expect(result.error?.code == "not_found")
        #expect(result.error?.retryable == false)
        #expect(result.error?.message.contains("does-not-exist.txt") == true || result.error?.message.contains(workspace.path) == true)
        #expect(result.error?.hint?.isEmpty == false)
    }

    @Test("files.read succeeds for UTF-8 file")
    func readExistingFile() async throws {
        let tmp = FileManager.default.temporaryDirectory
        let workspace = tmp.appendingPathComponent("sloppy-files-read-ok-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let fileURL = workspace.appendingPathComponent("note.txt")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let context = makeContext(workspaceRootURL: workspace)
        let tool = FilesReadTool()
        let result = await tool.invoke(arguments: ["path": .string("note.txt")], context: context)

        #expect(result.ok == true)
        #expect(result.data?.asObject?["content"]?.asString == "hello")
    }

    @Test("files.read returns is_directory when path is a directory")
    func readDirectory() async throws {
        let tmp = FileManager.default.temporaryDirectory
        let workspace = tmp.appendingPathComponent("sloppy-files-read-dir-\(UUID().uuidString)", isDirectory: true)
        let subdir = workspace.appendingPathComponent("adir", isDirectory: true)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let context = makeContext(workspaceRootURL: workspace)
        let tool = FilesReadTool()
        let result = await tool.invoke(arguments: ["path": .string("adir")], context: context)

        #expect(result.ok == false)
        #expect(result.error?.code == "is_directory")
        #expect(result.error?.retryable == false)
        #expect(result.error?.hint?.isEmpty == false)
    }

    @Test("FileSystemToolErrorMapping maps Cocoa read not found")
    func mapsCocoaReadNotFound() {
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError, userInfo: [:])
        let d = FileSystemToolErrorMapping.describe(error: error, operation: .read, path: "/tmp/missing.md")
        #expect(d.code == "not_found")
        #expect(d.retryable == false)
        #expect(d.hint?.isEmpty == false)
    }

    @Test("FileSystemToolErrorMapping maps POSIX EACCES for read")
    func mapsPOSIXPermissionRead() {
        let error = NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES), userInfo: [:])
        let d = FileSystemToolErrorMapping.describe(error: error, operation: .read, path: "/tmp/x")
        #expect(d.code == "permission_denied")
        #expect(d.retryable == false)
    }
}
