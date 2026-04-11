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
}
