import Foundation
import Testing
@testable import ChannelPluginTelegram
@testable import Protocols
@testable import sloppy

@Test
func riskyToolWaitsForApprovalBeforeExecution() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let session = try await makeApprovalSession(service: service, agentID: "approval-waits")

    let invocation = Task {
        await service.invokeToolFromRuntime(
            agentID: "approval-waits",
            sessionID: session.id,
            request: ToolInvocationRequest(
                tool: "runtime.exec",
                arguments: [
                    "command": .string("/bin/echo"),
                    "arguments": .array([.string("approved")])
                ],
                reason: "Need to run a command"
            ),
            recordSessionEvents: false,
            requireApproval: true
        )
    }

    let pending = try await waitForPendingToolApproval(service)
    #expect(pending.tool == "runtime.exec")
    #expect(pending.agentId == "approval-waits")

    let approved = await service.approveToolApproval(id: pending.id, decidedBy: "test")
    #expect(approved?.status == .approved)

    let result = await invocation.value
    #expect(result.ok == true)
}

@Test
func rejectedRiskyToolDoesNotExecute() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let session = try await makeApprovalSession(service: service, agentID: "approval-rejects")
    let target = FileManager.default.temporaryDirectory
        .appendingPathComponent("should-not-exist-\(UUID().uuidString).txt")

    let invocation = Task {
        await service.invokeToolFromRuntime(
            agentID: "approval-rejects",
            sessionID: session.id,
            request: ToolInvocationRequest(
                tool: "files.write",
                arguments: [
                    "path": .string(target.path),
                    "content": .string("nope")
                ],
                reason: "Need to write a file"
            ),
            recordSessionEvents: false,
            requireApproval: true
        )
    }

    let pending = try await waitForPendingToolApproval(service)
    _ = await service.rejectToolApproval(id: pending.id, decidedBy: "test")

    let result = await invocation.value
    #expect(result.ok == false)
    #expect(result.error?.code == "tool_approval_rejected")
    #expect(FileManager.default.fileExists(atPath: target.path) == false)
}

@Test
func readOnlyToolBypassesApproval() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let session = try await makeApprovalSession(service: service, agentID: "approval-bypass")

    let result = await service.invokeToolFromRuntime(
        agentID: "approval-bypass",
        sessionID: session.id,
        request: ToolInvocationRequest(tool: "agents.list"),
        recordSessionEvents: false,
        requireApproval: true
    )

    #expect(result.ok == true)
    #expect(await service.listPendingToolApprovals().isEmpty)
}

@Test
func toolApprovalTimeoutReturnsTimedOut() async {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let record = await service.toolApprovalService.createPending(
        agentId: "approval-timeout",
        sessionId: "session-timeout",
        channelId: nil,
        topicId: nil,
        request: ToolInvocationRequest(tool: "runtime.exec"),
        timeoutSeconds: 0.05
    )

    let result = await service.toolApprovalService.waitForDecision(id: record.id, timeoutSeconds: 0.05)
    if case .timedOut(let timedOut) = result {
        #expect(timedOut.status == .timedOut)
    } else {
        Issue.record("Expected timedOut result")
    }
}

@Test
func toolApprovalRoutesListAndResolvePendingApprovals() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let record = await service.toolApprovalService.createPending(
        agentId: "approval-router",
        sessionId: "session-router",
        channelId: nil,
        topicId: nil,
        request: ToolInvocationRequest(tool: "files.write", reason: "router test")
    )

    let listResponse = await router.handle(method: "GET", path: "/v1/tool-approvals/pending", body: nil)
    #expect(listResponse.status == 200)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let listed = try decoder.decode([ToolApprovalRecord].self, from: listResponse.body)
    #expect(listed.contains(where: { $0.id == record.id }))

    let body = try JSONEncoder().encode(ToolApprovalDecisionRequest(decidedBy: "router"))
    let approveResponse = await router.handle(
        method: "POST",
        path: "/v1/tool-approvals/\(record.id)/approve",
        body: body
    )
    #expect(approveResponse.status == 200)
    let approved = try decoder.decode(ToolApprovalRecord.self, from: approveResponse.body)
    #expect(approved.status == .approved)
}

@Test
func toolApprovalNotificationContainsRoutingMetadata() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let stream = await service.notificationService.subscribe()
    let waiter = Task<DashboardNotification?, Never> {
        for await notification in stream {
            if notification.type == .toolApproval {
                return notification
            }
        }
        return nil
    }

    let record = await service.toolApprovalService.createPending(
        agentId: "approval-notification",
        sessionId: "session-notification",
        channelId: "channel:telegram",
        topicId: "10",
        request: ToolInvocationRequest(tool: "runtime.exec", reason: "notify")
    )

    let notification = try #require(await waiter.value)
    #expect(notification.metadata["approvalId"] == record.id)
    #expect(notification.metadata["agentId"] == "approval-notification")
    #expect(notification.metadata["sessionId"] == "session-notification")
    #expect(notification.metadata["channelId"] == "channel:telegram")
    #expect(notification.metadata["topicId"] == "10")
    #expect(notification.metadata["tool"] == "runtime.exec")
}

@Test
func telegramToolApprovalCallbackParsing() {
    #expect(TelegramToolApproval.parseCallback("TA|A|abc") == .approve("abc"))
    #expect(TelegramToolApproval.parseCallback("TA|R|abc") == .reject("abc"))
    #expect(TelegramToolApproval.parseCallback("M|1|S|0") == .unknown)
}

private func makeApprovalSession(service: CoreService, agentID: String) async throws -> AgentSessionSummary {
    _ = try await service.createAgent(AgentCreateRequest(
        id: agentID,
        displayName: agentID,
        role: "Tests tool approvals"
    ))
    return try await service.createAgentSession(
        agentID: agentID,
        request: AgentSessionCreateRequest(title: "Approval Session")
    )
}

private func waitForPendingToolApproval(_ service: CoreService) async throws -> ToolApprovalRecord {
    for _ in 0..<100 {
        if let pending = await service.listPendingToolApprovals().first {
            return pending
        }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    throw ToolApprovalTestError.timeout
}

private enum ToolApprovalTestError: Error {
    case timeout
}
