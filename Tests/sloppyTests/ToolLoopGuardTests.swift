import Foundation
import Testing
@testable import sloppy
@testable import Protocols

@Suite("Tool loop guard")
struct ToolLoopGuardTests {
    private func makeService() -> CoreService {
        CoreService(config: CoreConfig.test)
    }

    private func makeAgentSession(service: CoreService, agentID: String) async throws -> String {
        _ = try await service.createAgent(
            AgentCreateRequest(id: agentID, displayName: "Loop Guard Agent", role: "Testing loop protection")
        )
        let session = try await service.createAgentSession(
            agentID: agentID,
            request: AgentSessionCreateRequest(title: "Loop Guard Session")
        )
        return session.id
    }

    @Test("third identical runtime.exec call is blocked and unrelated commands still work")
    func repeatedRuntimeExecIsBlocked() async throws {
        let service = makeService()
        let agentID = "loop-exec-\(UUID().uuidString)"
        let sessionID = try await makeAgentSession(service: service, agentID: agentID)

        let request = ToolInvocationRequest(
            tool: "runtime.exec",
            arguments: ["command": .string("/usr/bin/true")]
        )

        let first = await service.invokeToolFromRuntime(agentID: agentID, sessionID: sessionID, request: request, recordSessionEvents: false)
        let second = await service.invokeToolFromRuntime(agentID: agentID, sessionID: sessionID, request: request, recordSessionEvents: false)
        let third = await service.invokeToolFromRuntime(agentID: agentID, sessionID: sessionID, request: request, recordSessionEvents: false)

        #expect(first.ok == true)
        #expect(second.ok == true)
        #expect(third.ok == false)
        #expect(third.error?.code == "tool_loop_detected")

        let unrelated = await service.invokeToolFromRuntime(
            agentID: agentID,
            sessionID: sessionID,
            request: ToolInvocationRequest(
                tool: "runtime.exec",
                arguments: ["command": .string("/bin/echo"), "arguments": .array([.string("hello")])]
            ),
            recordSessionEvents: false
        )
        #expect(unrelated.ok == true)
    }

    @Test("third identical runtime.process start call is blocked")
    func repeatedRuntimeProcessStartIsBlocked() async throws {
        let service = makeService()
        let agentID = "loop-process-\(UUID().uuidString)"
        let sessionID = try await makeAgentSession(service: service, agentID: agentID)

        let request = ToolInvocationRequest(
            tool: "runtime.process",
            arguments: [
                "action": .string("start"),
                "command": .string("/usr/bin/true")
            ]
        )

        let first = await service.invokeToolFromRuntime(agentID: agentID, sessionID: sessionID, request: request, recordSessionEvents: false)
        let second = await service.invokeToolFromRuntime(agentID: agentID, sessionID: sessionID, request: request, recordSessionEvents: false)
        let third = await service.invokeToolFromRuntime(agentID: agentID, sessionID: sessionID, request: request, recordSessionEvents: false)

        #expect(first.ok == true)
        #expect(second.ok == true)
        #expect(third.error?.code == "tool_loop_detected")
    }

    @Test("second repeated non-retryable invalid request is blocked")
    func repeatedNonRetryableFailureIsBlocked() async throws {
        let service = makeService()
        let agentID = "loop-invalid-\(UUID().uuidString)"
        let sessionID = try await makeAgentSession(service: service, agentID: agentID)

        let request = ToolInvocationRequest(
            tool: "runtime.process",
            arguments: ["action": .string("read")]
        )

        let first = await service.invokeToolFromRuntime(agentID: agentID, sessionID: sessionID, request: request, recordSessionEvents: false)
        let second = await service.invokeToolFromRuntime(agentID: agentID, sessionID: sessionID, request: request, recordSessionEvents: false)

        #expect(first.ok == false)
        #expect(first.error?.code == "invalid_arguments")
        #expect(second.ok == false)
        #expect(second.error?.code == "tool_loop_detected")
    }

    @Test("mixed one-shot commands do not trip the guard")
    func mixedExecCommandsRemainAllowed() async throws {
        let service = makeService()
        let agentID = "loop-mixed-\(UUID().uuidString)"
        let sessionID = try await makeAgentSession(service: service, agentID: agentID)

        let requests = [
            ToolInvocationRequest(tool: "runtime.exec", arguments: ["command": .string("/bin/pwd")]),
            ToolInvocationRequest(tool: "runtime.exec", arguments: ["command": .string("/bin/echo"), "arguments": .array([.string("alpha")])]),
            ToolInvocationRequest(tool: "runtime.exec", arguments: ["command": .string("/bin/echo"), "arguments": .array([.string("beta")])]),
            ToolInvocationRequest(tool: "runtime.exec", arguments: ["command": .string("/usr/bin/true")])
        ]

        for request in requests {
            let result = await service.invokeToolFromRuntime(agentID: agentID, sessionID: sessionID, request: request, recordSessionEvents: false)
            #expect(result.ok == true)
        }
    }

    @Test("runtime.exec timeout returns promptly with timedOut payload")
    func runtimeExecTimeoutReturnsPromptly() async throws {
        let service = makeService()
        let agentID = "exec-timeout-\(UUID().uuidString)"
        let sessionID = try await makeAgentSession(service: service, agentID: agentID)
        let startedAt = Date()

        let result = await service.invokeToolFromRuntime(
            agentID: agentID,
            sessionID: sessionID,
            request: ToolInvocationRequest(
                tool: "runtime.exec",
                arguments: [
                    "command": .string("/bin/sleep"),
                    "arguments": .array([.string("10")]),
                    "timeoutMs": .number(250)
                ]
            ),
            recordSessionEvents: false
        )

        #expect(result.ok == true)
        #expect(result.data?.asObject?["timedOut"]?.asBool == true)
        #expect(Date().timeIntervalSince(startedAt) < 3)
    }

    @Test("runtime.exec drains large output without blocking on pipe buffers")
    func runtimeExecLargeOutputDoesNotBlock() async throws {
        let service = makeService()
        let agentID = "exec-output-\(UUID().uuidString)"
        let sessionID = try await makeAgentSession(service: service, agentID: agentID)

        let result = await service.invokeToolFromRuntime(
            agentID: agentID,
            sessionID: sessionID,
            request: ToolInvocationRequest(
                tool: "runtime.exec",
                arguments: [
                    "command": .string("/bin/bash"),
                    "arguments": .array([
                        .string("-lc"),
                        .string("for i in $(seq 1 50000); do printf 'line%05d\\n' \"$i\"; done")
                    ]),
                    "timeoutMs": .number(5_000)
                ]
            ),
            recordSessionEvents: false
        )

        #expect(result.ok == true)
        #expect(result.data?.asObject?["timedOut"]?.asBool == false)
        #expect((result.data?.asObject?["stdout"]?.asString ?? "").contains("line") == true)
    }

    @Test("runtime.exec does not wait for background children holding output pipes")
    func runtimeExecDoesNotWaitForInheritedPipes() async throws {
        let service = makeService()
        let agentID = "exec-inherited-pipe-\(UUID().uuidString)"
        let sessionID = try await makeAgentSession(service: service, agentID: agentID)
        let startedAt = Date()

        let result = await service.invokeToolFromRuntime(
            agentID: agentID,
            sessionID: sessionID,
            request: ToolInvocationRequest(
                tool: "runtime.exec",
                arguments: [
                    "command": .string("/bin/bash"),
                    "arguments": .array([
                        .string("-lc"),
                        .string("sleep 1 & echo done")
                    ]),
                    "timeoutMs": .number(5_000)
                ]
            ),
            recordSessionEvents: false
        )

        #expect(result.ok == true)
        #expect((result.data?.asObject?["stdout"]?.asString ?? "").contains("done") == true)
        #expect(Date().timeIntervalSince(startedAt) < 2)
    }

    @Test("persisted runtime.exec timeout still records matching tool result")
    func runtimeExecTimeoutPersistsToolResult() async throws {
        let service = makeService()
        let agentID = "exec-persist-\(UUID().uuidString)"
        let sessionID = try await makeAgentSession(service: service, agentID: agentID)

        let result = await service.invokeToolFromRuntime(
            agentID: agentID,
            sessionID: sessionID,
            request: ToolInvocationRequest(
                tool: "runtime.exec",
                arguments: [
                    "command": .string("/bin/sleep"),
                    "arguments": .array([.string("10")]),
                    "timeoutMs": .number(250)
                ]
            )
        )
        let detail = try await service.getAgentSession(agentID: agentID, sessionID: sessionID)
        let toolCalls = detail.events.filter { $0.type == .toolCall }
        let toolResults = detail.events.filter { $0.type == .toolResult }

        #expect(result.data?.asObject?["timedOut"]?.asBool == true)
        #expect(toolCalls.count == 1)
        #expect(toolResults.count == 1)
        #expect(toolResults.first?.toolResult?.tool == "runtime.exec")
    }

    @Test("repeated runtime.exec timeouts block further diagnostic commands")
    func repeatedRuntimeExecTimeoutsBlockFurtherExec() async throws {
        let service = makeService()
        let agentID = "exec-timeout-loop-\(UUID().uuidString)"
        let sessionID = try await makeAgentSession(service: service, agentID: agentID)

        for seconds in ["10", "11"] {
            let result = await service.invokeToolFromRuntime(
                agentID: agentID,
                sessionID: sessionID,
                request: ToolInvocationRequest(
                    tool: "runtime.exec",
                    arguments: [
                        "command": .string("/bin/sleep"),
                        "arguments": .array([.string(seconds)]),
                        "timeoutMs": .number(250)
                    ]
                ),
                recordSessionEvents: false
            )
            #expect(result.data?.asObject?["timedOut"]?.asBool == true)
        }

        let blocked = await service.invokeToolFromRuntime(
            agentID: agentID,
            sessionID: sessionID,
            request: ToolInvocationRequest(
                tool: "runtime.exec",
                arguments: ["command": .string("/bin/echo"), "arguments": .array([.string("still probing")])]
            ),
            recordSessionEvents: false
        )

        #expect(blocked.ok == false)
        #expect(blocked.error?.code == "tool_loop_detected")
    }
}
