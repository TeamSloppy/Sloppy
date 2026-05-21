import AnyLanguageModel
import Protocols
import Testing
@testable import PluginSDK

@Suite("SloppyToolExecutionDelegate")
struct SloppyToolExecutionDelegateTests {
    @Test("GeneratedContent structure converts to [String: JSONValue]")
    func structureConversion() async throws {
        let capture = RequestCapture()
        let delegate = SloppyToolExecutionDelegate(toolCallHandler: { request in
            await capture.store(request)
            return ToolInvocationResult(tool: request.tool, ok: true)
        })

        let toolCall = Transcript.ToolCall(
            id: "call-1",
            toolName: "web.search",
            arguments: GeneratedContent(properties: [
                "query": "swift concurrency",
                "count": 5
            ])
        )
        _ = await delegate.toolCallDecision(for: toolCall, in: makeFakeSession())

        let invoked = try #require(await capture.value)
        #expect(invoked.arguments["query"] == .string("swift concurrency"))
        #expect(invoked.arguments["count"] == .number(5))
        #expect(invoked.tool == "web.search")
    }

    @Test("Non-structure GeneratedContent produces empty arguments")
    func nonStructureConversion() async throws {
        let capture = RequestCapture()
        let diagnostics = ArgumentDiagnosticCapture()
        let delegate = SloppyToolExecutionDelegate(
            argumentDiagnosticsHandler: { diagnostic in
                await diagnostics.store(diagnostic)
            },
            toolCallHandler: { request in
                await capture.store(request)
                return ToolInvocationResult(tool: request.tool, ok: false)
            }
        )

        let toolCall = Transcript.ToolCall(
            id: "call-2",
            toolName: "nonexistent.tool",
            arguments: GeneratedContent("some string")
        )
        let decision = await delegate.toolCallDecision(for: toolCall, in: makeFakeSession())

        let invoked = try #require(await capture.value)
        #expect(invoked.arguments.isEmpty)
        let requestDiagnostics = try #require(invoked.argumentDiagnostics)
        #expect(requestDiagnostics.toolCallId == "call-2")
        #expect(requestDiagnostics.originalToolName == "nonexistent.tool")
        #expect(requestDiagnostics.rawArgumentKind == "string")
        #expect(requestDiagnostics.rawArguments == .string("some string"))
        #expect(requestDiagnostics.decodedArgumentCount == 0)
        #expect(requestDiagnostics.usedEmptyArgumentsFallback)
        let diagnostic = try #require(await diagnostics.value)
        #expect(diagnostic.toolCallId == "call-2")
        #expect(diagnostic.toolName == "nonexistent.tool")
        #expect(diagnostic.argumentKind == "string")
        #expect(diagnostic.rawArguments == .string("some string"))

        if case .provideOutput(let segments) = decision,
           let first = segments.first,
           case .text(let textSegment) = first {
            #expect(textSegment.content.contains("\"ok\""))
        } else {
            Issue.record("Expected provideOutput with text segment")
        }
    }

    @Test("Nested structure converts recursively")
    func nestedStructureConversion() async throws {
        let capture = RequestCapture()
        let delegate = SloppyToolExecutionDelegate(toolCallHandler: { request in
            await capture.store(request)
            return ToolInvocationResult(tool: request.tool, ok: true)
        })

        let toolCall = Transcript.ToolCall(
            id: "call-3",
            toolName: "files.write",
            arguments: GeneratedContent(properties: [
                "path": "/tmp/test.txt",
                "content": "hello"
            ])
        )
        _ = await delegate.toolCallDecision(for: toolCall, in: makeFakeSession())

        let invoked = try #require(await capture.value)
        #expect(invoked.arguments["path"] == .string("/tmp/test.txt"))
        #expect(invoked.arguments["content"] == .string("hello"))
    }

    @Test("Array arguments convert correctly")
    func arrayArgumentConversion() async throws {
        let capture = RequestCapture()
        let delegate = SloppyToolExecutionDelegate(toolCallHandler: { request in
            await capture.store(request)
            return ToolInvocationResult(tool: request.tool, ok: true)
        })

        let toolCall = Transcript.ToolCall(
            id: "call-4",
            toolName: "runtime.exec",
            arguments: GeneratedContent(properties: [
                "command": "ls",
                "arguments": GeneratedContent(elements: ["one", "two"] as [any ConvertibleToGeneratedContent])
            ])
        )
        _ = await delegate.toolCallDecision(for: toolCall, in: makeFakeSession())

        let invoked = try #require(await capture.value)
        guard case .array(let items) = invoked.arguments["arguments"] else {
            Issue.record("Expected array for 'arguments'")
            return
        }
        #expect(items.count == 2)
        #expect(items[0] == .string("one"))
        #expect(items[1] == .string("two"))
    }

    @Test("Tool name map restores provider-safe aliases before invocation")
    func toolNameMapRestoresOriginalName() async throws {
        let capture = RequestCapture()
        let delegate = SloppyToolExecutionDelegate(
            toolNameMap: ["files_read": "files.read"],
            toolCallHandler: { request in
                await capture.store(request)
                return ToolInvocationResult(tool: request.tool, ok: true)
            }
        )

        let toolCall = Transcript.ToolCall(
            id: "call-5",
            toolName: "files_read",
            arguments: GeneratedContent(properties: [:])
        )
        _ = await delegate.toolCallDecision(for: toolCall, in: makeFakeSession())

        let invoked = try #require(await capture.value)
        #expect(invoked.tool == "files.read")
        let diagnostics = try #require(invoked.argumentDiagnostics)
        #expect(diagnostics.providerToolName == "files_read")
        #expect(diagnostics.originalToolName == "files.read")
        #expect(diagnostics.rawArgumentKind == "structure")
        #expect(diagnostics.decodedArgumentCount == 0)
        #expect(diagnostics.usedEmptyArgumentsFallback == false)
    }

    @Test("Generated tool calls handler receives provider batches")
    func generatedToolCallsHandlerReceivesBatches() async throws {
        let capture = ToolCallBatchCapture()
        let delegate = SloppyToolExecutionDelegate(
            generatedToolCallsHandler: { calls in
                await capture.store(calls.map(\.toolName))
            },
            toolCallHandler: { request in
                ToolInvocationResult(tool: request.tool, ok: true)
            }
        )

        await delegate.didGenerateToolCalls(
            [
                Transcript.ToolCall(id: "call-1", toolName: "files.read", arguments: GeneratedContent(properties: [:])),
                Transcript.ToolCall(id: "call-2", toolName: "files.write", arguments: GeneratedContent(properties: [:])),
            ],
            in: makeFakeSession()
        )

        #expect(try #require(await capture.value) == ["files.read", "files.write"])
    }

    @Test("Tool decision override can stop before invocation")
    func toolDecisionOverrideCanStopBeforeInvocation() async throws {
        let capture = RequestCapture()
        let delegate = SloppyToolExecutionDelegate(
            toolCallDecisionOverride: { _ in .stop },
            toolCallHandler: { request in
                await capture.store(request)
                return ToolInvocationResult(tool: request.tool, ok: true)
            }
        )

        let decision = await delegate.toolCallDecision(
            for: Transcript.ToolCall(id: "call-6", toolName: "files.read", arguments: GeneratedContent(properties: [:])),
            in: makeFakeSession()
        )

        if case .stop = decision {
            #expect(await capture.value == nil)
        } else {
            Issue.record("Expected stop decision")
        }
    }

    @Test("Model tool sanitizer emits OpenAI-compatible unique names")
    func modelToolNameSanitizerEmitsProviderSafeNames() {
        let tools: [any Tool] = [
            NamedTool(name: "files.read"),
            NamedTool(name: "files_read"),
            NamedTool(name: "mcp.fs/read-file"),
            NamedTool(name: "..."),
        ]

        let result = ModelToolNameSanitizer.sanitizeTools(tools)
        let names = result.tools.map(\.name)

        #expect(names.count == Set(names).count)
        #expect(names.allSatisfy(isProviderSafeToolName))
        #expect(result.nameMap["files_read"] == "files.read")
        #expect(result.nameMap[names[1]] == "files_read")
        #expect(result.nameMap["mcp_fs_read-file"] == "mcp.fs/read-file")
        #expect(result.nameMap["tool"] == "...")
    }

    private func makeFakeSession() -> LanguageModelSession {
        LanguageModelSession(model: StubLanguageModel(), instructions: "test")
    }

    private func isProviderSafeToolName(_ name: String) -> Bool {
        !name.isEmpty
            && name.count <= ModelToolNameSanitizer.maximumNameLength
            && name.unicodeScalars.allSatisfy { scalar in
                switch scalar.value {
                case 48...57, 65...90, 97...122, 45, 95:
                    return true
                default:
                    return false
                }
            }
    }
}

// MARK: - Helpers

private actor RequestCapture {
    private var stored: ToolInvocationRequest?
    var value: ToolInvocationRequest? { stored }
    func store(_ request: ToolInvocationRequest) { stored = request }
}

private actor ToolCallBatchCapture {
    private var stored: [String]?
    var value: [String]? { stored }
    func store(_ names: [String]) { stored = names }
}

private actor ArgumentDiagnosticCapture {
    private var stored: SloppyToolExecutionDelegate.ArgumentDiagnostic?
    var value: SloppyToolExecutionDelegate.ArgumentDiagnostic? { stored }
    func store(_ diagnostic: SloppyToolExecutionDelegate.ArgumentDiagnostic) { stored = diagnostic }
}

private struct NamedTool: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String

    let name: String
    let description = "Test tool"
    let parameters: GenerationSchema = String.generationSchema

    func call(arguments: GeneratedContent) async throws -> String {
        ""
    }
}

private struct StubLanguageModel: LanguageModel {
    typealias UnavailableReason = Never

    func respond<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        throw StubError.notImplemented
    }

    func streamResponse<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable {
        LanguageModelSession.ResponseStream(stream: AsyncThrowingStream { $0.finish(throwing: StubError.notImplemented) })
    }

    private enum StubError: Error { case notImplemented }
}
