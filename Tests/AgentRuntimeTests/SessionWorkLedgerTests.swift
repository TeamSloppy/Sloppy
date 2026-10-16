import AnyLanguageModel
import Foundation
import Testing
@testable import AgentRuntime
@testable import PluginSDK
@testable import Protocols

private func request(_ tool: String, _ arguments: [String: Protocols.JSONValue] = [:]) -> ToolInvocationRequest {
    ToolInvocationRequest(tool: tool, arguments: arguments)
}

private func ok(_ tool: String, _ data: Protocols.JSONValue? = nil) -> ToolInvocationResult {
    ToolInvocationResult(tool: tool, ok: true, data: data)
}

@Suite("Session work ledger")
struct SessionWorkLedgerTests {
    @Test("An identical read is answered from the ledger once, then runs again for fresh data")
    func duplicateReadIsAnsweredOnce() {
        var ledger = SessionWorkLedger()
        let read = request("files.read", ["path": .string("/a.swift")])
        #expect(ledger.duplicateReadResult(for: read) == nil)
        ledger.observe(request: read, result: ok("files.read", .object(["content": .string("let answer = 42")])))

        let first = ledger.duplicateReadResult(for: read)
        #expect(first?.ok == true)
        #expect(first?.data?.asObject?["alreadyRead"] == .bool(true))
        #expect(first?.data?.asObject?["digest"]?.asString?.contains("answer = 42") == true)
        #expect(ledger.duplicateReadResult(for: read) == nil)
    }

    @Test("Editing files invalidates earlier file reads")
    func editInvalidatesFileReads() {
        var ledger = SessionWorkLedger()
        let read = request("files.read", ["path": .string("/a.swift")])
        ledger.observe(request: read, result: ok("files.read", .object(["content": .string("old")])))
        ledger.observe(request: request("files.edit", ["path": .string("/a.swift")]), result: ok("files.edit"))
        #expect(ledger.duplicateReadResult(for: read) == nil)
        #expect(ledger.changedFiles == ["/a.swift"])
    }

    @Test("MCP reads are tracked only when the server marks them read-only")
    func mcpReadsNeedReadOnlyMarker() {
        var ledger = SessionWorkLedger()
        let skill = request("mcp.call_tool", ["server": .string("acp.studio"), "tool": .string("editor.skills.read"), "arguments": .string("{\"name\":\"a\"}")])
        let build = request("mcp.call_tool", ["server": .string("acp.studio"), "tool": .string("editor.build.start")])
        ledger.observe(request: skill, result: ok("mcp.call_tool", .object(["readOnly": .bool(true), "content": .string("skill text")])))
        ledger.observe(request: build, result: ok("mcp.call_tool", .object(["content": .string("started")])))
        #expect(ledger.duplicateReadResult(for: skill) != nil)
        #expect(ledger.duplicateReadResult(for: build) == nil)
    }

    @Test("Rendered ledger carries goal, plan, changes, checks and reads")
    func renderContainsWorkingState() {
        var ledger = SessionWorkLedger()
        ledger.recordGoal("Make a flappy bird")
        ledger.recordGoal("ignored: the first goal wins")
        ledger.observe(request: request("planning.progress_update", ["goal": .string("step 1")]), result: ok("planning.progress_update"))
        ledger.observe(request: request("files.write", ["path": .string("/Bird.swift")]), result: ok("files.write"))
        ledger.observe(
            request: request("runtime.exec", ["command": .string("swift")]),
            result: ok("runtime.exec", .object(["verificationEvidence": .object(["id": .string("verification-1"), "kind": .string("build"), "command": .string("swift")])]))
        )
        ledger.observe(request: request("files.read", ["path": .string("/Doc.md")]), result: ok("files.read", .object(["content": .string("docs body")])))
        let text = ledger.render()
        #expect(text.contains("Make a flappy bird"))
        #expect(!text.contains("first goal wins"))
        #expect(text.contains("step 1"))
        #expect(text.contains("/Bird.swift"))
        #expect(text.contains("verification-1"))
        #expect(text.contains("files.read") && text.contains("docs body"))
    }

    @Test("Compaction always re-inserts the ledger into the summary")
    func compactionKeepsLedger() async throws {
        func prompt(_ text: String) -> Transcript.Entry { .prompt(.init(segments: [.text(.init(content: text))])) }
        func response(_ text: String) -> Transcript.Entry { .response(.init(assetIDs: [], segments: [.text(.init(content: text))])) }
        let full = Transcript(entries: [
            prompt("old objective"), response(String(repeating: "history ", count: 400)),
            prompt("recent"), response("recent answer"), prompt("latest"),
        ])
        let prepared = try await TranscriptContextManager.prepare(
            full, inputBudget: 4_000, protectRecentEntries: 2, forceSummary: true,
            ledger: "[Session work ledger]\nGoal: flappy",
            summarize: { _, _ in "short summary" }
        )
        let rendered = prepared.0.map(TranscriptContextManager.render).joined(separator: "\n")
        #expect(prepared.1.summarized)
        #expect(rendered.contains("short summary"))
        #expect(rendered.contains("Goal: flappy"))
    }

    @Test("Pressure uses the active model window, not the global default")
    func channelPressureUsesModelWindow() async {
        let channels = ChannelRuntime(eventBus: EventBus())
        await channels.recordTokenUsage(channelId: "c", usage: TokenUsage(prompt: 100_000, completion: 100))
        let withDefault = await channels.snapshot(channelId: "c")?.contextUtilization ?? 0
        await channels.setContextWindow(channelId: "c", tokens: 500_000)
        let withModelWindow = await channels.snapshot(channelId: "c")?.contextUtilization ?? 1
        #expect(withDefault > 0.8)
        #expect(withModelWindow < 0.3)
    }
}

// MARK: - Model routing, fallback and tool history

private struct RoutedModel: LanguageModel {
    typealias UnavailableReason = Never
    let name: String
    let log: RoutedLog

    func respond<Content>(
        within session: LanguageModelSession, to prompt: Prompt, generating type: Content.Type,
        includeSchemaInPrompt: Bool, options: GenerationOptions
    ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        log.record(name)
        if name == "bad" { throw ProviderModelNotSupportedError(detail: "The 'bad' model is not supported when using Codex with a ChatGPT account.") }
        return LanguageModelSession.Response(content: "ok" as! Content, rawContent: GeneratedContent("ok"), transcriptEntries: [])
    }

    func streamResponse<Content>(
        within session: LanguageModelSession, to prompt: Prompt, generating type: Content.Type,
        includeSchemaInPrompt: Bool, options: GenerationOptions
    ) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable {
        let stream = AsyncThrowingStream<LanguageModelSession.ResponseStream<Content>.Snapshot, any Error> { continuation in
            Task {
                do {
                    let response = try await respond(within: session, to: prompt, generating: type, includeSchemaInPrompt: includeSchemaInPrompt, options: options)
                    continuation.yield(.init(content: response.content.asPartiallyGenerated(), rawContent: response.rawContent))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
        return LanguageModelSession.ResponseStream(stream: stream)
    }
}

private final class RoutedLog: @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []
    func record(_ name: String) { lock.lock(); names.append(name); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return names }
}

private struct RoutedProvider: ModelProvider {
    let id = "routed"
    var supportedModels: [String] { ["bad", "good"] }
    let log = RoutedLog()
    func createLanguageModel(for modelName: String) async throws -> any LanguageModel { RoutedModel(name: modelName, log: log) }
    func generationOptions(for modelName: String, maxTokens: Int, reasoningEffort: ReasoningEffort?) -> GenerationOptions {
        GenerationOptions(maximumResponseTokens: maxTokens)
    }
}

@Test
func rejectedModelFallsBackToAnotherAndFinishesTheTurn() async {
    let provider = RoutedProvider()
    let system = RuntimeSystem(modelProvider: provider, defaultModel: "bad")
    await system.setUnsupportedModelFallback { rejected, tried in
        #expect(rejected == "bad")
        return tried.contains("good") ? nil : "good"
    }
    _ = await system.postMessage(channelId: "fallback", request: ChannelMessageRequest(userId: "u", content: "hi"))
    let final = await system.channelState(channelId: "fallback")?.messages.last(where: { $0.userId == "system" })?.content
    #expect(final == "ok")
    #expect(provider.log.all == ["bad", "good"])
}

@Test
func backgroundChannelRunsOnTheSessionModelNotTheProviderDefault() async {
    let provider = RoutedProvider()
    let system = RuntimeSystem(modelProvider: provider, defaultModel: "bad")
    let parent = "agent:a:session:s"
    _ = await system.postMessage(channelId: parent, request: ChannelMessageRequest(userId: "u", content: "work", model: "good"))
    _ = await system.postMessage(
        channelId: parent + ":memory-checkpoint:abc",
        request: ChannelMessageRequest(userId: "memory_checkpoint", content: "checkpoint")
    )
    #expect(provider.log.all == ["good", "good"])
}

@Test
func toolHistoryOfAStreamedTurnIsMergedBeforeTheNextTurn() async throws {
    let provider = RoutedProvider()
    let system = RuntimeSystem(modelProvider: provider, defaultModel: "good")
    let model = RoutedModel(name: "good", log: provider.log)
    let transcript = Transcript(entries: [
        .prompt(.init(segments: [.text(.init(content: "task"))])),
        .response(.init(assetIDs: [], segments: [.text(.init(content: "done"))])),
    ])
    let session = LanguageModelSession(model: model, tools: [], transcript: transcript)
    await system.cacheSessionForTesting(channelId: "c", model: "good", session: session)
    let call = Transcript.ToolCall(id: "call-1", toolName: "files.read", arguments: GeneratedContent(properties: ["path": "/a"]))
    let output = Transcript.ToolOutput(id: "call-1", toolName: "files.read", segments: [.text(.init(content: "file body"))])
    await system.setPendingToolTranscriptForTesting(channelId: "c", session: session, entries: [.toolCalls(Transcript.ToolCalls([call])), .toolOutput(output)])

    let merged = try await system.mergePendingToolTranscript(channelId: "c", session: session, activeModel: "good", provider: provider)
    let kinds = merged.transcript.map { entry -> String in
        switch entry {
        case .prompt: return "prompt"
        case .toolCalls: return "calls"
        case .toolOutput: return "output"
        case .response: return "response"
        case .instructions: return "instructions"
        }
    }
    #expect(kinds == ["prompt", "calls", "output", "response"])
}
