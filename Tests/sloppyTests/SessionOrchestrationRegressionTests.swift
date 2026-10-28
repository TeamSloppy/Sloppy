import Foundation
import Protocols
import SloppyRuntime
import Testing
@testable import sloppy

@Suite("Session orchestration regressions")
struct SessionOrchestrationRegressionTests {
    @Test func stalledPresenterCannotExtendTheInvocationDeadline() async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let agent = try await service.createAgent(.init(id: "stalled-presenter", displayName: "Agent", role: "Test"))
        let session = try await service.createAgentSession(agentID: agent.id, request: .init(separateChat: true))
        let gate = AsyncStream<Void>.makeStream()
        await service.setToolApprovalPresenter { _ in
            for await _ in gate.stream { break }
            return .approve(.once)
        }
        let result = await service.requestToolApprovalIfNeeded(agentID: agent.id, sessionID: session.id,
            channelID: nil, topicID: nil, request: .init(tool: "agents.delegate_task"), requireApproval: true,
            timeoutSeconds: 0.03)
        gate.continuation.finish()
        guard case .timedOut = result else {
            Issue.record("A suspended presenter must not block the invocation past its deadline")
            return
        }
        #expect(await service.listPendingToolApprovals().isEmpty)
        await service.stop()
    }

    @Test func approvalExpiresBeforeReviewerStartsWaiting() async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let approvals = await service.toolApprovalService
        let record = await approvals.createPending(agentId: "agent", sessionId: "session",
            channelId: nil, topicId: nil, request: .init(tool: "agents.delegate_task"),
            timeoutSeconds: 0.01, publishRequest: false)
        try await Task.sleep(for: .milliseconds(30))
        #expect(await approvals.listPending(includeUnpublished: true).isEmpty)
        #expect(await approvals.approve(id: record.id, decidedBy: "late-reviewer") == nil)
        await approvals.publishPendingRequest(id: record.id)
        let result = await approvals.waitForDecision(id: record.id)
        guard case .timedOut(let expired) = result else {
            Issue.record("An expired call must never receive a new approval window")
            return
        }
        #expect(expired.agentId == record.agentId)
        #expect(expired.expiresAt == record.expiresAt)
        await service.stop()
    }

    @Test func listAcceptsEmptyFiltersAndExposesWorkerLifecycle() async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let agent = try await service.createAgent(.init(id: "list-worker", displayName: "Worker", role: "Test"))
        let session = try await service.createAgentSession(agentID: agent.id, request: .init(separateChat: true))
        _ = try await service.appendAgentSessionEvents(agentID: agent.id, sessionID: session.id,
            request: .init(events: [.init(agentId: agent.id, sessionId: session.id, type: .runStatus,
                runStatus: .init(stage: .paused, label: "Arbitrary display text", executionOutcome: .init(state: .waitingApproval))),
                .init(agentId: agent.id, sessionId: session.id, type: .message,
                    message: .init(role: .assistant, segments: [.init(kind: .text, text: "Latest message is not lifecycle state")]))]))
        let result = await service.invokeToolFromRuntime(agentID: agent.id, sessionID: session.id,
            request: .init(tool: "sessions.list", arguments: ["scope": .string("all"), "agentId": .string("  "),
                "projectId": .string(""), "query": .string("")]), recordSessionEvents: false)
        #expect(result.ok)
        let item = try #require(result.data?.asArray?.first { $0.asObject?["id"]?.asString == session.id }?.asObject)
        #expect(item["status"]?.asString == "paused")
        #expect(item["executionOutcome"]?.asObject?["state"]?.asString == "waiting_approval")
        #expect(item["activeProcessCount"]?.asInt == 0)
        #expect(item["hasActiveRun"]?.asBool == false)
        await service.holdRegressionInbox(session.id)
        #expect(await service.sessionHasActiveRun(agentID: agent.id, sessionID: session.id) == true)
        await service.releaseRegressionInbox(agentID: agent.id, sessionID: session.id)
        let missing = await service.invokeToolFromRuntime(agentID: agent.id, sessionID: session.id,
            request: .init(tool: "sessions.list", arguments: ["agentId": .string("missing-agent")]), recordSessionEvents: false)
        #expect(!missing.ok)
        #expect(missing.error?.code == "agent_not_found")
        #expect(missing.error?.retryable == false)
        await service.stop()
    }

    @Test func lateWorkerEvidenceDoesNotStartAnotherTurnAndSurvivesRetry() async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let agent = try await service.createAgent(.init(id: "late-worker", displayName: "Worker", role: "Test"))
        let parent = try await service.createAgentSession(agentID: agent.id, request: .init(separateChat: true))
        let child = try await service.createAgentSession(agentID: agent.id,
            request: .init(parentSessionId: parent.id, separateChat: true))
        _ = try await service.appendAgentSessionEvents(agentID: agent.id, sessionID: parent.id,
            request: .init(events: [.init(agentId: agent.id, sessionId: parent.id, type: .runStatus,
                runStatus: .init(stage: .done, label: "Done", executionOutcome: .completed))]))
        let id = UUID().uuidString
        for _ in 0..<2 {
            let receipt = try await service.sendPeerSessionMessage(senderAgentID: agent.id, senderSessionID: child.id,
                targetAgentID: agent.id, targetSessionID: parent.id, content: "Evidence, including a late failure", messageID: id)
            #expect(receipt.asObject?["state"]?.asString == "recorded")
        }
        let detail = try await service.getAgentSession(agentID: agent.id, sessionID: parent.id)
        #expect(detail.events.compactMap(\.message).filter { $0.id == id }.count == 1)
        #expect(detail.events.compactMap(\.message).first?.peerOrigin?.sessionId == child.id)
        #expect(!detail.events.compactMap(\.message).contains { $0.role == .assistant })
        let storage = try SessionMessageInboxFileStore(root: await service.workspaceRootURL)
        #expect(storage.entries.first { $0.id == id }?.state == .delivered)
        #expect(storage.entries.first { $0.id == id }?.recordedOnly == true)
        await service.stop()
    }

    @Test func onlySupersededChildReportsAreRecorded() throws {
        let base = Date(timeIntervalSince1970: 100)
        let parent = AgentSessionSummary(id: "parent", agentId: "agent", title: "Parent", createdAt: base, updatedAt: base, messageCount: 0)
        let child = AgentSessionSummary(id: "child", agentId: "agent", title: "Child", parentSessionId: parent.id, createdAt: base, updatedAt: base, messageCount: 0)
        let working = AgentSessionEvent(agentId: "agent", sessionId: parent.id, type: .runStatus, createdAt: base,
            runStatus: .init(stage: .searching, label: "Done is just display text"))
        #expect(!SessionWorkerReportPolicy.shouldRecord(sender: child, target: .init(summary: parent, events: [working])))
        let nextTask = AgentSessionEvent(agentId: "agent", sessionId: parent.id, type: .message, createdAt: base.addingTimeInterval(1),
            message: .init(role: .user, segments: [.init(kind: .text, text: "Next task")]))
        #expect(!SessionWorkerReportPolicy.shouldRecord(sender: child, target: .init(summary: parent, events: [nextTask, working])))
        let finished = AgentSessionEvent(agentId: "agent", sessionId: parent.id, type: .runStatus,
            createdAt: base.addingTimeInterval(0.5), runStatus: .init(stage: .done, label: "Done"))
        #expect(SessionWorkerReportPolicy.shouldRecord(sender: child, target: .init(summary: parent, events: [finished, nextTask, working])))
        var unrelated = child
        unrelated.parentSessionId = nil
        #expect(!SessionWorkerReportPolicy.shouldRecord(sender: unrelated, target: .init(summary: parent, events: [nextTask])))
    }

    @Test func parentInboxWaitsForChildApprovalAndResumesAfterDecision() async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let agent = try await service.createAgent(.init(id: "approval-inbox", displayName: "Agent", role: "Test"))
        let parent = try await service.createAgentSession(agentID: agent.id, request: .init(separateChat: true))
        let sender = try await service.createAgentSession(agentID: agent.id, request: .init(separateChat: true))
        let approval = await service.toolApprovalService.createPending(agentId: agent.id, sessionId: "child",
            displaySessionId: parent.id, channelId: nil, topicId: nil, request: .init(tool: "runtime.exec"))
        let receipt = try await service.sendPeerSessionMessage(senderAgentID: agent.id, senderSessionID: sender.id,
            targetAgentID: agent.id, targetSessionID: parent.id, content: "Peer cannot approve the pending call", messageID: nil)
        let id = try #require(receipt.asObject?["messageId"]?.asString)
        await service.waitForRegressionInbox(parent.id)
        #expect(try await service.regressionInboxState(id) == "queued")
        _ = await service.approveToolApproval(id: approval.id, decidedBy: "test")
        await service.waitForRegressionInbox(parent.id)
        #expect(try await service.regressionInboxState(id) == "delivered")
        await service.stop()
    }

    @Test func tuiDoesNotOfferAnExpiredApproval() {
        let now = Date()
        let expired = ToolApprovalRecord(agentId: "agent", sessionId: "session", tool: "agents.delegate_task", expiresAt: now)
        #expect(SloppyTUIToolApprovalState.pendingApproval(in: [expired], agentID: "agent", sessionID: "session", now: now) == nil)
    }

    @Test func queuedWorkerReportIsRecheckedAfterParentFinishes() async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let agent = try await service.createAgent(.init(id: "queued-worker", displayName: "Worker", role: "Test"))
        let parent = try await service.createAgentSession(agentID: agent.id, request: .init(separateChat: true))
        let child = try await service.createAgentSession(agentID: agent.id,
            request: .init(parentSessionId: parent.id, separateChat: true))
        await service.holdRegressionInbox(parent.id)
        let receipt = try await service.sendPeerSessionMessage(senderAgentID: agent.id, senderSessionID: child.id,
            targetAgentID: agent.id, targetSessionID: parent.id, content: "Report queued while parent was busy", messageID: nil)
        let id = try #require(receipt.asObject?["messageId"]?.asString)
        #expect(receipt.asObject?["state"]?.asString == "queued")
        _ = try await service.appendAgentSessionEvents(agentID: agent.id, sessionID: parent.id,
            request: .init(events: [.init(agentId: agent.id, sessionId: parent.id, type: .runStatus,
                runStatus: .init(stage: .done, label: "Done", executionOutcome: .completed))]))
        await service.releaseRegressionInbox(agentID: agent.id, sessionID: parent.id)
        await service.waitForRegressionInbox(parent.id)
        #expect(try await service.regressionInboxState(id) == "recorded")
        let detail = try await service.getAgentSession(agentID: agent.id, sessionID: parent.id)
        #expect(!detail.events.compactMap(\.message).contains { $0.role == .assistant })
        await service.stop()
    }
}

private extension CoreService {
    func holdRegressionInbox(_ id: String) { activeSessionMessageRuns.insert(id) }
    func releaseRegressionInbox(agentID: String, sessionID: String) {
        activeSessionMessageRuns.remove(sessionID)
        scheduleSessionInbox(agentID: agentID, sessionID: sessionID)
    }
    func waitForRegressionInbox(_ id: String) async { await sessionMessageRunners[id]?.value }
    func regressionInboxState(_ id: String) throws -> String? {
        try sessionMessageInbox().entries.first { $0.id == id }?.receiptState
    }
}
