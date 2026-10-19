import Foundation
import Protocols
import Testing
@testable import sloppy

@Suite("Chat approval modes")
struct SessionApprovalPolicyTests {
    @Test("JEV resolves an exact call without invoking Visor", arguments: ["approve", "reject"])
    func jevDecision(choice: String) async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        defer { Task { await service.stop() } }
        let session = try await service.approvalPolicyFixture()
        let jev = ChatApprovalDecisionProvider(choice: choice)
        await service.semanticModelRouter.setProviderFactory { _ in jev }
        let counter = await service.setVisorApprovalTestDecision(.approve)
        let result = try #require(await service.requestToolApprovalIfNeeded(agentID: "policy-test", sessionID: session.id,
            channelID: nil, topicID: nil, request: request, requireApproval: true))
        switch result {
        case .approved(let record):
            #expect(choice == "approve")
            #expect(record.decidedBy == "jev")
        case .rejected(let record):
            #expect(choice == "reject")
            #expect(record.decidedBy == "jev")
        case .timedOut: Issue.record("Review unexpectedly timed out")
        }
        #expect(await counter.calls == 0)
        let calls = await jev.calls
        #expect(calls.count == 1)
        let state = try #require(calls.first?.state)
        let context = try #require(JSONSerialization.jsonObject(with: Data(state.utf8)) as? [String: Any])
        #expect((context["arguments"] as? [String: Any])?["command"] as? String == "/bin/echo")
        #expect(await service.listPendingToolApprovals().isEmpty)
    }

    @Test("Visor reviews only when JEV is unavailable", arguments: [true, false])
    func visorFallback(throwing: Bool) async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        defer { Task { await service.stop() } }
        let session = try await service.approvalPolicyFixture()
        await service.semanticModelRouter.setProviderFactory { _ in
            throwing ? ChatApprovalDecisionProvider(choice: "approve", unavailable: true) : nil
        }
        let counter = await service.setVisorApprovalTestDecision(.approve)
        let result = try #require(await service.requestToolApprovalIfNeeded(agentID: "policy-test", sessionID: session.id,
            channelID: nil, topicID: nil, request: request, requireApproval: true))
        guard case .approved(let record) = result else { Issue.record("Visor should approve"); return }
        #expect(record.decidedBy == "visor")
        #expect(await counter.calls == 1)
    }

    @Test("uncertainty, unavailable reviewers and manual mode ask the user", arguments: ["ask_user", "low_confidence", "unavailable", "manual"])
    func humanFallback(scenario: String) async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        defer { Task { await service.stop() } }
        let session = try await service.approvalPolicyFixture(mode: scenario == "manual" ? .askForApproval : .approveForMe)
        let jev = ChatApprovalDecisionProvider(choice: scenario == "ask_user" ? "ask_user" : "approve",
            confidence: scenario == "low_confidence" ? 0.01 : 1, unavailable: scenario == "unavailable")
        await service.semanticModelRouter.setProviderFactory { _ in jev }
        let counter = await service.setVisorApprovalTestDecision(nil)
        let task = Task {
            await service.requestToolApprovalIfNeeded(agentID: "policy-test", sessionID: session.id,
                channelID: nil, topicID: nil, request: request, requireApproval: true)
        }
        let pending = try await pending(service)
        #expect(await counter.calls == (scenario == "unavailable" ? 1 : 0))
        if scenario == "manual" { #expect(await jev.calls.isEmpty) }
        _ = await service.rejectToolApproval(id: pending.id, decidedBy: "human")
        guard case .rejected(let record) = await task.value else { Issue.record("Expected human decision"); return }
        #expect(record.decidedBy == "human")
    }

    @Test("manual chat mode requires approval even when the runtime session bypass is enabled")
    func manualModeOverridesRuntimeBypass() async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        defer { Task { await service.stop() } }
        let session = try await service.approvalPolicyFixture(mode: .askForApproval)
        await service.setSessionToolApprovalBypass(sessionID: session.id, enabled: true)
        let jev = ChatApprovalDecisionProvider(choice: "approve")
        await service.semanticModelRouter.setProviderFactory { _ in jev }
        let invocation = Task {
            await service.invokeToolFromRuntime(agentID: "policy-test", sessionID: session.id,
                request: request, recordSessionEvents: false)
        }
        let record = try await pending(service)
        #expect(await jev.calls.isEmpty)
        _ = await service.rejectToolApproval(id: record.id, decidedBy: "human")
        #expect((await invocation.value).error?.code == "tool_approval_rejected")
    }

    @Test("switching to Approve for me reviews an already pending request")
    func reviewExistingPendingCall() async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        defer { Task { await service.stop() } }
        let session = try await service.approvalPolicyFixture(mode: .askForApproval)
        let jev = ChatApprovalDecisionProvider(choice: "approve")
        await service.semanticModelRouter.setProviderFactory { _ in jev }
        let invocation = Task {
            await service.requestToolApprovalIfNeeded(agentID: "policy-test", sessionID: session.id,
                channelID: nil, topicID: nil, request: request, requireApproval: true)
        }
        let record = try await pending(service)
        _ = try await service.setSessionApprovalPolicy(agentID: "policy-test", sessionID: session.id,
            policy: .init(mode: .approveForMe))
        for _ in 0..<200 {
            if await service.listPendingToolApprovals().isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        _ = await service.rejectToolApproval(id: record.id, decidedBy: "test-timeout")
        guard case .approved(let approved) = await invocation.value else { Issue.record("Pending call was not reviewed"); return }
        #expect(approved.decidedBy == "jev")
    }

    @Test("policy persists, is inherited by workers and remains scoped to the chat")
    func persistenceAndInheritance() async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        defer { Task { await service.stop() } }
        let parent = try await service.approvalPolicyFixture()
        let child = try await service.createAgentSession(agentID: "policy-test", request: .init(parentSessionId: parent.id))
        let other = try await service.createAgentSession(agentID: "policy-test", request: .init())
        #expect(await service.sessionApprovalMode(agentID: "policy-test", sessionID: child.id) == .approveForMe)
        #expect(await service.sessionApprovalMode(agentID: "policy-test", sessionID: other.id) == nil)
        _ = try await service.setSessionApprovalPolicy(agentID: "policy-test", sessionID: child.id, policy: .init(mode: .askForApproval))
        #expect(try await service.getSessionApprovalPolicy(agentID: "policy-test", sessionID: child.id).mode == .askForApproval)
        #expect(try await service.getSessionApprovalPolicy(agentID: "policy-test", sessionID: parent.id).mode == .approveForMe)
        let router = CoreRouter(service: service)
        let path = "/v1/agents/policy-test/sessions/\(parent.id)/approval-policy"
        let response = await router.handle(method: "PUT", path: path, body: Data(#"{"mode":"ask_for_approval"}"#.utf8))
        #expect(response.status == 200)
        #expect(try await service.getSessionApprovalPolicy(agentID: "policy-test", sessionID: parent.id).mode == .askForApproval)
        #expect(await router.handle(method: "PUT", path: path, body: Data(#"{"mode":"full_access"}"#.utf8)).status == 400)
    }

    private var request: ToolInvocationRequest {
        .init(tool: "runtime.exec", arguments: ["command": .string("/bin/echo"), "arguments": .array([.string("verified")])])
    }

    private func pending(_ service: CoreService) async throws -> ToolApprovalRecord {
        for _ in 0..<200 {
            if let record = await service.listPendingToolApprovals().first { return record }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw ChatApprovalTestError.noPending
    }
}

private enum ChatApprovalTestError: Error { case unavailable, noPending }
private actor ChatApprovalDecisionProvider: SemanticDecisionProvider {
    let choice: String
    let confidence: Double
    let unavailable: Bool
    var calls: [SemanticChoiceRequest] = []
    init(choice: String, confidence: Double = 1, unavailable: Bool = false) {
        self.choice = choice; self.confidence = confidence; self.unavailable = unavailable
    }
    func choose(_ request: SemanticChoiceRequest) async throws -> SemanticChoiceResponse {
        calls.append(request)
        if unavailable { throw ChatApprovalTestError.unavailable }
        return .init(choice: choice, confidence: confidence, probabilities: [:],
                     usage: .init(inputTokens: 10, outputTokens: 0, costUSD: 0, costIsEstimated: false))
    }
}

private actor VisorApprovalCounter {
    var calls = 0
    func increment() { calls += 1 }
}

private extension CoreService {
    func approvalPolicyFixture(mode: SessionApprovalMode = .approveForMe) async throws -> AgentSessionSummary {
        _ = try await createAgent(.init(id: "policy-test", displayName: "Policy", role: "Test"))
        let session = try await createAgentSession(agentID: "policy-test", request: .init())
        _ = try sessionStore.appendEvents(agentID: "policy-test", sessionID: session.id, events: [
            .init(agentId: "policy-test", sessionId: session.id, type: .message,
                  message: .init(role: .user, segments: [.init(kind: .text, text: "Run echo to verify the workspace.")]))
        ])
        _ = try await setSessionApprovalPolicy(agentID: "policy-test", sessionID: session.id, policy: .init(mode: mode))
        return session
    }
    func setVisorApprovalTestDecision(_ decision: SemanticToolApprovalDecision?) -> VisorApprovalCounter {
        let counter = VisorApprovalCounter()
        visorToolApprovalReviewOverride = { _ in await counter.increment(); return decision }
        return counter
    }
}
