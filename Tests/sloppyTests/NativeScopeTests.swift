import Foundation
import AnyLanguageModel
@testable import AgentRuntime
import PluginSDK
import Protocols
import SloppyRuntime
import Testing
@testable import sloppy

private struct ScopeDeclaration: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String
    let name = "files.read"
    let description = "Scoped read"
    var parameters: GenerationSchema { FilesReadTool().parameters }
    func call(arguments: GeneratedContent) async throws -> String { "Provider declarations cannot execute" }
}

private struct ScopeProvider: ModelProvider {
    let id = "scope-fixture"
    let supportedModels = ["mock:scope"]
    var tools: [any Tool] { [ScopeDeclaration()] }
    func createLanguageModel(for modelName: String) async throws -> any LanguageModel {
        throw ModelStepFailure(category: .unavailable, code: "not_used", message: "This fixture exercises tool authority.")
    }
}

extension CoreService {
    func installEmptyDelegatedScopeForTests(sessionID: String) { sessionSubagentToolAllowList[sessionID] = [] }
}

@Suite("Native delegated authority")
struct NativeScopeTests {
    @Test func emptyPeerScopeCannotAdvertiseOrInvokeTools() async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        await service.waitForStartup(dispatchReadyTasks: false)
        await service.setToolApprovalPresenter { _ in .approve(.once) }
        let agentID = "empty-scope-" + UUID().uuidString.lowercased()
        _ = try await service.createAgent(.init(id: agentID, displayName: agentID, role: "Scoped fixture"))
        let session = try await service.createAgentSession(agentID: agentID, request: .init())
        let detail = try await service.getAgentSession(agentID: agentID, sessionID: session.id)
        await service.installEmptyDelegatedScopeForTests(sessionID: session.id)
        try await service.preparePeerConversation(agentID: agentID, detail: detail)
        let runtime = await service.runtime
        let tools = await runtime.filteredModelTools(channelId: "agent:\(agentID):session:\(session.id)",
            modelProvider: ScopeProvider(), includeTools: true, activeModel: "mock:scope")
        #expect(tools.isEmpty)
        let file = await service.workspaceRootURL.appendingPathComponent("scope-read.txt")
        try "protected contents".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let request = ToolInvocationRequest(tool: "files.read", arguments: ["path": .string(file.path)])
        let legacy = await service.invokeToolFromRuntime(agentID: agentID, sessionID: session.id, request: request,
            recordSessionEvents: false)
        #expect(!legacy.ok)
        #expect(legacy.error?.code == "tool_forbidden")
        let definition = ModelStepToolDefinition(name: "files_read", toolId: "files.read", parameters: .object(["type": .string("object")]))
        let frame = ModelStepRequest(runId: "run", userTurnId: "turn", stepId: "step", attemptId: "attempt", model: "mock:scope",
            projectionRevision: "", cacheScope: session.id, messages: [], tools: [definition])
        let call = AgentLoopCall(sourceOrder: 0, call: .init(id: "read", name: definition.name,
            rawArguments: String(decoding: try JSONEncoder().encode(request.arguments), as: UTF8.self)))
        let journal = SessionLoopJournal(store: await service.sessionStore, agentID: agentID, sessionID: session.id, authorizeWriter: {})
        try await journal.appendResponse(.init(toolCalls: [call.call], stopReason: .toolCalls), request: frame)
        try await journal.appendRequested([call], request: frame)
        let context = NativeToolExecutionContext(metadata: .init(runId: "run", userTurnId: "turn", stepId: "step", attemptId: "attempt",
            sourceOrder: 0, providerCallId: "read", callEventId: call.eventID), definition: definition,
            beforeEffect: { Issue.record("An empty scope cannot authorize an effect start") },
            recordLateResult: { try await journal.appendResult($0, call: call, request: frame) })
        let native = await service.invokeNativeTool(agentID: agentID, sessionID: session.id, request: request, context: context)
        #expect(!native.result.ok)
        #expect(native.result.error?.code == "tool_forbidden")
    }
}
