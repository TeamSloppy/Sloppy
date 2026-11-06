import Foundation
import AgentRuntime
import PluginSDK
import Protocols
import Testing
@testable import SloppyRuntime

@Suite("Typed history compaction")
struct TypedHistoryCompactionTests {
    @Test(arguments: [false, true])
    func compactsSettledTypedTransactionsWithoutDiscardingActiveOrUnknownCalls(unknown: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("typed-compaction-\(UUID())")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentSessionFileStore(agentsRootURL: root)
        let session = try store.createSession(agentID: "agent", request: .init())
        let journal = SessionLoopJournal(store: store, agentID: "agent", sessionID: session.id, authorizeWriter: {})
        var request = ModelStepRequest(runId: "active", userTurnId: "active", stepId: "active", attemptId: "active",
            model: "script:model", projectionRevision: "", cacheScope: "scope", messages: [])
        for index in 0..<14 {
            var old = request
            old.runId = "old-\(index)"; old.userTurnId = old.runId; old.stepId = old.runId
            let user = AgentSessionEvent(id: "user-\(index)", agentId: "agent", sessionId: session.id, type: .message,
                runtimeMetadata: .init(runId: old.runId, userTurnId: old.userTurnId),
                message: .init(role: .user, segments: [.init(kind: .text, text: "Task \(index)")]))
            _ = try store.appendEvents(agentID: "agent", sessionID: session.id, events: [user])
            let call = AgentLoopCall(eventID: "event-\(index)", sourceOrder: 0,
                call: .init(id: "call-\(index)", name: "inspect", rawArguments: "{}"))
            try await journal.appendResponse(.init(text: String(repeating: "historical context ", count: 60),
                toolCalls: [call.call], stopReason: .toolCalls), request: old)
            try await journal.appendRequested([call], request: old)
            try await journal.appendStarted(call, request: old)
            if !(unknown && index == 2) {
                try await journal.appendResult(.init(tool: "inspect", ok: true, data: .string("observed-\(index)")), call: call, request: old)
            }
            try await journal.appendRunState(.init(runID: old.runId, userTurnID: old.userTurnId,
                phase: .settled, model: old.model), request: old)
        }
        _ = try store.appendEvents(agentID: "agent", sessionID: session.id, events: [
            .init(agentId: "agent", sessionId: session.id, type: .message,
                runtimeMetadata: .init(runId: "active", userTurnId: "active"),
                message: .init(role: .user, segments: [.init(kind: .text, text: "Current protected task")]))
        ])
        request = try await journal.prepareRequest(request)
        let originalCount = try store.loadSession(agentID: "agent", sessionID: session.id).events.count
        let plan = try #require(try await journal.makeCompactionPlan(for: request, inputBudget: 30_000))
        #expect(plan.history.contains("observed-0"))
        #expect(!plan.history.contains("Current protected task"))
        let compacted = try await journal.commitCompaction(plan, summary: "Completed historical inspections; original outputs remain in canonical history.", request: request)
        #expect(compacted.messages.count < request.messages.count)
        #expect(compacted.messages.contains { $0.text.contains("Current protected task") })
        #expect(!compacted.messages.contains { $0.toolOutput?.content.contains("observed-1") == true })
        if unknown {
            #expect(compacted.messages.contains { $0.toolCalls.contains { $0.id == "call-2" } })
        }
        let reopened = SessionLoopJournal(store: AgentSessionFileStore(agentsRootURL: root), agentID: "agent", sessionID: session.id, authorizeWriter: {})
        #expect(try await reopened.prepareRequest(request).messages == compacted.messages)
        #expect(try store.loadSession(agentID: "agent", sessionID: session.id).events.count > originalCount)
    }
}
