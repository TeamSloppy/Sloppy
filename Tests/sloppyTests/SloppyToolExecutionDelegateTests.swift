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
        let delegate = SloppyToolExecutionDelegate(toolCallHandler: { request in
            await capture.store(request)
            return ToolInvocationResult(tool: request.tool, ok: false)
        })

        let toolCall = Transcript.ToolCall(
            id: "call-2",
            toolName: "nonexistent.tool",
            arguments: GeneratedContent("some string")
        )
        let decision = await delegate.toolCallDecision(for: toolCall, in: makeFakeSession())

        let invoked = try #require(await capture.value)
        #expect(invoked.arguments.isEmpty)

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

    private func makeFakeSession() -> LanguageModelSession {
        LanguageModelSession(model: StubLanguageModel(), instructions: "test")
    }
}

// MARK: - Helpers

private actor RequestCapture {
    private var stored: ToolInvocationRequest?
    var value: ToolInvocationRequest? { stored }
    func store(_ request: ToolInvocationRequest) { stored = request }
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
