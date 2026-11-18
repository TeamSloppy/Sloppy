import Foundation
import Protocols
import Testing
@testable import sloppy

#if os(macOS) || os(Linux)
@Suite("Code Mode")
struct CodeModeTests {
    @Test("A process wait can time out or be cancelled, and later waits see final output")
    func waitForProcess() async throws {
        let registry = SessionProcessRegistry()
        let start = try await registry.start(sessionID: "owner", command: "/bin/sh",
            arguments: ["-c", "sleep 0.3; printf finished; exit 7"], cwd: nil, maxProcesses: 1, captureOutput: true)
        let id = try #require(start.asObject?["processId"]?.asString)
        await #expect(throws: SessionProcessRegistry.RegistryError.waitTimedOut) {
            try await registry.wait(sessionID: "owner", processID: id, timeoutMs: 1)
        }
        await #expect(throws: SessionProcessRegistry.RegistryError.processNotFound) {
            try await registry.wait(sessionID: "other", processID: id, timeoutMs: 1000)
        }

        let cancelled = Task { try await registry.wait(sessionID: "owner", processID: id, timeoutMs: 1000) }
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        async let first = registry.wait(sessionID: "owner", processID: id, timeoutMs: 5000)
        async let second = registry.wait(sessionID: "owner", processID: id, timeoutMs: 5000)
        let (a, b) = try await (first, second)
        let cached = try await registry.wait(sessionID: "owner", processID: id, timeoutMs: 1)
        #expect(a == b)
        #expect(a == cached)
        #expect(a.asObject?["exitCode"]?.asInt == 7)
        #expect(a.asObject?["outputTail"]?.asString == "finished")
        await registry.shutdown()
    }

    @Test("Disabled Code Mode is hidden and cannot invoke JavaScript or wait")
    func flagOff() async throws {
        let config = CoreConfig.test
        let root = config.resolvedWorkspaceRootURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let catalog = await service.toolCatalog()
        #expect(!catalog.contains { $0.id == CodeMode.toolID })
        let result = await service.invokeToolFromRuntime(agentID: "agent", sessionID: "session",
            request: .init(tool: CodeMode.toolID, arguments: ["code": .string("return 1;")]))
        #expect(result.error?.code == "code_mode_unavailable")
        let wait = await service.invokeToolFromRuntime(agentID: "agent", sessionID: "session",
            request: .init(tool: "runtime.process", arguments: ["action": .string("wait")]))
        #expect(wait.error?.code == "code_mode_unavailable")
        await service.shutdownChannelPlugins()
    }

    @Test("Nested calls still pass through the configured Core pre-tool hook")
    func nestedAuthorization() async throws {
        var config = CoreConfig.test
        let root = config.resolvedWorkspaceRootURL()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "SLOPPY_CODEMODE_ENABLED=1\n".write(to: root.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        config.toolHooks.preTools = .init(enabled: true, command: "/bin/sh", arguments: ["-c", """
            case "$(cat)" in
              *'"tool":"files.read"'*) printf '%s' '{"action":"block","message":"blocked in test"}' ;;
              *) printf '%s' '{"action":"allow"}' ;;
            esac
            """])
        let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        _ = try await service.createAgent(.init(id: "codemode-hooks", displayName: "Hooks", role: "Test"))
        let session = try await service.createAgentSession(agentID: "codemode-hooks", request: .init(title: "Nested"))
        let result = await service.invokeToolFromRuntime(agentID: "codemode-hooks", sessionID: session.id,
            request: .init(tool: CodeMode.toolID, arguments: ["code": .string("""
                if (!describeTool("files.read")) throw new Error("missing catalog entry");
                const result = await tools.files_read({path: "blocked.txt"});
                store("lastToolError", result.error?.code);
                return result.error?.code;
                """)]))
        #expect(result.ok)
        #expect(result.data?.asObject?["output"]?.asString == "tool_pre_hook_blocked")

        let stored = await service.invokeToolFromRuntime(agentID: "codemode-hooks", sessionID: session.id,
            request: .init(tool: CodeMode.toolID, arguments: ["code": .string("""
                // @options: {"max_output_tokens": 6, "timeout_ms": 60000}
                text(load("lastToolError"));
                console.log("long output");
                exit();
                """)]))
        #expect(stored.ok)
        #expect(stored.data?.asObject?["output"]?.asString == "tool_pre_hook_blocked")
        #expect(stored.data?.asObject?["truncated"]?.asBool == true)
        await service.shutdownChannelPlugins()
    }

    @Test("QuickJS caps execution time and has no runtime I/O globals")
    func vmIsBounded() async throws {
        let source = "return [typeof fetch, typeof require, typeof std, typeof os, typeof setTimeout];"
        let result = try await CodeMode.run(source: source, options: CodeMode.Options.parse(source), catalog: [], stored: [:]) { _ in
            fatalError("No tool calls should be made")
        }
        #expect(result.snapshot.output?.head == #"["undefined","undefined","undefined","undefined","undefined"]"#)

        let loop = """
            // @options: {"timeout_ms": 20}
            while (true) {}
            """
        await #expect(throws: CodeMode.Failure.self) {
            try await CodeMode.run(source: loop, options: CodeMode.Options.parse(loop), catalog: [], stored: [:]) { _ in
                fatalError("No tool calls should be made")
            }
        }
    }

    @Test("Code Mode preserves late output at both truncation limits", arguments: [9_000, 45_000])
    func outputKeepsLastResult(length: Int) async throws {
        let lastMatch = String(repeating: "error: missing symbol\n", count: 270)
        let source = """
            text("a".repeat(\(length == 45_000 ? 19_999 : length)) + "😀" + "я".repeat(\(length)));
            console.log("debug".repeat(45_000));
            return { matches: ["error: missing symbol\\n".repeat(270)] };
            """
        let result = try await CodeMode.run(source: source, options: CodeMode.Options.parse(source), catalog: [], stored: [:]) { _ in
            Issue.record("Unexpected tool call")
            return .init(tool: "unexpected", ok: false)
        }
        let output = try #require(result.snapshot.output)
        let preview = output.preview(maxBytes: 8_000)
        #expect((output.tail != nil) == (length == 45_000))
        #expect(preview.truncated)
        #expect(preview.text.hasPrefix("aaaa"))
        let lastLine = try #require(preview.text.split(separator: "\n").last)
        let decoded = try JSONDecoder().decode([String: [String]].self, from: Data(lastLine.utf8))
        #expect(decoded["matches"] == [lastMatch])
        #expect(preview.text.utf8.count <= 8_000)
    }
}
#endif
