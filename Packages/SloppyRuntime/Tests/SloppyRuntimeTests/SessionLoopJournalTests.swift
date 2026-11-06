import Foundation
import AgentRuntime
import PluginSDK
import Protocols
import SloppyRuntime
import Testing

@Suite("Durable native loop journal")
struct SessionLoopJournalTests {
    @Test
    func oldSummaryCacheCannotRestoreHiddenAuxiliaryMessageCounts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("auxiliary-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentSessionFileStore(agentsRootURL: root)
        let session = try store.createSession(agentID: "agent", request: .init())
        _ = try store.appendEvents(agentID: "agent", sessionID: session.id, events: [
            .init(agentId: "agent", sessionId: session.id, type: .message,
                message: .init(role: .user, segments: [.init(kind: .text, text: "User task")]))
        ])
        let journal = SessionLoopJournal(store: store, agentID: "agent", sessionID: session.id, authorizeWriter: {})
        var request = ModelStepRequest(runId: "run", userTurnId: "turn", stepId: "summary", attemptId: "summary",
            model: "script:model", projectionRevision: "", cacheScope: "scope", messages: [], purpose: .compaction)
        try await journal.appendResponse(.init(text: "Internal summary", stopReason: .endTurn), request: request)
        request.purpose = .work
        request.stepId = "work"
        request.attemptId = "work"
        try await journal.appendResponse(.init(text: "Final answer", stopReason: .endTurn), request: request)
        let file = URL(fileURLWithPath: try store.sessionFilePath(agentID: "agent", sessionID: session.id))
        let canonical = try Data(contentsOf: file)
        let cache = file.deletingLastPathComponent().appendingPathComponent("summary.json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: cache)) as? [String: Any])
        var summary = try #require(object["summary"] as? [String: Any])
        // The previous disposable cache counted the hidden summary as another assistant message.
        object["schemaVersion"] = 4
        summary["messageCount"] = 3
        object["summary"] = summary
        try JSONSerialization.data(withJSONObject: object).write(to: cache)
        let fresh = AgentSessionFileStore(agentsRootURL: root)
        let loaded = try #require(fresh.listSessions(agentID: "agent").first)
        #expect(loaded.messageCount == 2)
        #expect(loaded.lastMessagePreview == "Final answer")
        #expect(try Data(contentsOf: file) == canonical)
    }

    @Test
    func aPresentationOnlyCheckpointDoesNotHideItsModelSummary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("checkpoint-summary-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentSessionFileStore(agentsRootURL: root)
        let session = try store.createSession(agentID: "agent", request: .init())
        _ = try store.appendEvents(agentID: "agent", sessionID: session.id, events: [
            .init(agentId: "agent", sessionId: session.id, type: .message,
                message: .init(role: .user, segments: [.init(kind: .text, text: "Original objective")])),
            .init(agentId: "agent", sessionId: session.id, type: .message,
                message: .init(role: .assistant, segments: [.init(kind: .text, text: "Old context")]))
        ])
        let original = try store.loadJournal(agentID: "agent", sessionID: session.id)
        let boundary = try #require(original.records.last)
        let checkpoint = SessionProjectionCheckpoint(coveredCursor: boundary.endCursor, coveredThroughEventId: boundary.event.id,
            summary: "Factual checkpoint summary.", retainedEventIds: [])
        _ = try store.appendEvents(agentID: "agent", sessionID: session.id, events: [
            .init(version: 2, agentId: "agent", sessionId: session.id, type: .runStatus,
                runtimeMetadata: .init(runId: "run", userTurnId: "turn", checkpoint: checkpoint, presentationOnly: true))
        ])
        let request = ModelStepRequest(runId: "run", userTurnId: "turn", stepId: "inspect", attemptId: "inspect",
            model: "script:model", projectionRevision: "", cacheScope: "scope", messages: [])
        let messages = try SessionProjection.load(store: AgentSessionFileStore(agentsRootURL: root),
            agentID: "agent", sessionID: session.id).modelMessages(for: request)
        #expect(messages.contains { $0.text.contains("Factual checkpoint summary.") })
    }

    @Test
    func derivedRunReadersKeepSourceBindingAndSeparateModelHistories() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("derived-reader-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentSessionFileStore(agentsRootURL: root)
        let session = try store.createSession(agentID: "agent", request: .init())
        _ = try store.appendEvents(agentID: "agent", sessionID: session.id, events: [
            .init(agentId: "agent", sessionId: session.id, type: .message,
                message: .init(role: .user, segments: [.init(kind: .text, text: "Foreground conversation")]))
        ])
        let source: JSONValue = .object(["schemaVersion": .number(1), "kind": .string("memory_checkpoint"),
            "agentId": .string("agent"), "sessionId": .string(session.id),
            "owner": .object(["runId": .string("source-run"), "userTurnId": .string("source-turn"), "generation": .number(0)]),
            "terminalEventId": .string("source-terminal"), "model": .string("script:model")])
        var config = try #require(JSONValueCoder.encode(NativeAgentLoopConfig(engine: .unified, requiresExplicitCompletion: false)).asObject)
        config["completionContract"] = .string("background")
        var settings = RunRequestSettings(retryDelays: [], reasoningEffort: nil)
        settings.toolScope = ["memory.save"]
        settings.delegatedAuthority = .init(policy: .init(), workingDirectory: root.path, extraRoots: [root.path])
        var rawSettings = try #require(JSONValueCoder.encode(settings).asObject)
        rawSettings["derivedSource"] = source
        var rawState = try #require(JSONValueCoder.encode(RunStateSnapshot(runID: "background-run", userTurnID: "background-turn")).asObject)
        rawState["schemaVersion"] = .number(2)
        rawState["loopConfig"] = .object(config)
        rawState["requestSettings"] = .object(rawSettings)
        rawState["model"] = .string("script:model")
        func metadata(_ base: AgentRunMetadata) throws -> AgentRunMetadata {
            var raw = try #require(JSONValueCoder.encode(base).asObject)
            raw["derivedSource"] = source
            return try JSONValueCoder.decode(AgentRunMetadata.self, from: .object(raw))
        }
        let admission = try metadata(.init(runId: "background-run", userTurnId: "background-turn", runState: .object(rawState),
            admissionInstructions: [.init(id: "background-context", kind: .turnContext, text: "Background task context")]))
        let response = try metadata(.init(runId: "background-run", userTurnId: "background-turn", stepId: "step", attemptId: "attempt",
            modelResponse: JSONValueCoder.encode(ModelStepResponse(text: "Internal background answer", stopReason: .endTurn))))
        var failure: Error?
        do {
            _ = try store.appendEvents(agentID: "agent", sessionID: session.id, events: [
                .init(version: 2, agentId: "agent", sessionId: session.id, type: .runStatus, runtimeMetadata: admission),
                .init(version: 2, agentId: "agent", sessionId: session.id, type: .runStatus, runtimeMetadata: response)
            ])
        } catch { failure = error }
        #expect(failure == nil)
        let fresh = try AgentSessionFileStore(agentsRootURL: root).loadJournal(agentID: "agent", sessionID: session.id)
        let saved = fresh.detail.events.compactMap(\.runtimeMetadata).first
        #expect(try saved.map { try JSONValueCoder.encode($0).asObject?["derivedSource"] } == source)
        let foreground = ModelStepRequest(runId: "foreground-run", userTurnId: "foreground-turn", stepId: "fg", attemptId: "fg-attempt",
            model: "script:model", projectionRevision: "", cacheScope: "foreground", messages: [])
        let background = ModelStepRequest(runId: "background-run", userTurnId: "background-turn", stepId: "bg", attemptId: "bg-attempt",
            model: "script:model", projectionRevision: "", cacheScope: "background", messages: [])
        let projection = SessionProjection.project(fresh)
        let visible = try projection.modelMessages(for: foreground)
        #expect(visible.contains { $0.text == "Foreground conversation" })
        #expect(!visible.contains { $0.text == "Internal background answer" })
        let internalMessages = try projection.modelMessages(for: background)
        #expect(!internalMessages.contains { $0.text == "Foreground conversation" })
        #expect(internalMessages.contains { $0.text == "Background task context" })
        #expect(internalMessages.contains { $0.text == "Internal background answer" })
    }

    @Test(arguments: [ModelStepPurpose.planning, .reportReview])
    func hiddenAuxiliaryResponsesRetainTheirDurableUsage(purpose: ModelStepPurpose) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("auxiliary-usage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentSessionFileStore(agentsRootURL: root)
        let session = try store.createSession(agentID: "agent", request: .init())
        let journal = SessionLoopJournal(store: store, agentID: "agent", sessionID: session.id, authorizeWriter: {})
        let request = ModelStepRequest(runId: "run", userTurnId: "turn", stepId: "auxiliary", attemptId: "attempt",
            model: "script:model", projectionRevision: "", cacheScope: "scope", messages: [], purpose: purpose)
        let usage = TokenUsage(prompt: 17, completion: 3)
        let response = ModelStepResponse(text: "Private auxiliary response", stopReason: .endTurn, usage: usage)
        let record = UsageRequestRecord(id: try UsageRequestRecord.nativeIdentifier(channelId: "scope", runId: "run",
                userTurnId: "turn", stepId: "auxiliary", attemptId: "attempt"),
            channelId: "scope", provider: "script", model: "script:model", createdAt: Date(timeIntervalSince1970: 1),
            usage: usage, complete: false, runId: "run", userTurnId: "turn")
        var failure: Error?
        do { try await journal.appendResponse(response, request: request, usageRequest: record) }
        catch { failure = error }
        #expect(failure == nil)
        let fresh = AgentSessionFileStore(agentsRootURL: root)
        let saved = try fresh.loadJournal(agentID: "agent", sessionID: session.id)
        let usageEvents = saved.detail.events.filter { $0.runtimeMetadata?.usageRequest != nil }
        #expect(usageEvents.count == 1)
        #expect(usageEvents.first?.runtimeMetadata?.usageRequest?.usage == usage)
        #expect(usageEvents.first?.runtimeMetadata?.presentationOnly == true)
        let projection = try SessionProjection.project(saved).modelMessages(for: request)
        #expect(!projection.contains { $0.role == .assistant && $0.text == response.text })
    }

    @Test
    func unavailableSummaryCacheCannotRejectADurableOutcomeOrHistoryPage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("loop-cache-fault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentSessionFileStore(agentsRootURL: root)
        let session = try store.createSession(agentID: "agent", request: .init())
        let journal = SessionLoopJournal(store: store, agentID: "agent", sessionID: session.id, authorizeWriter: {})
        let request = ModelStepRequest(runId: "run", userTurnId: "turn", stepId: "step", attemptId: "attempt",
            model: "script:model", projectionRevision: "", cacheScope: "scope", messages: [], tools: [
                .init(name: "files_write", toolId: "files.write", parameters: .object(["type": .string("object")]))
            ])
        _ = try store.appendEvents(agentID: "agent", sessionID: session.id, events: [
            .init(id: "working", agentId: "agent", sessionId: session.id, type: .runStatus,
                runStatus: .init(stage: .thinking, label: "Working"))
        ])
        let call = AgentLoopCall(eventID: "call", sourceOrder: 0,
            call: .init(id: "provider-call", name: "files_write", rawArguments: "{}"))
        try await journal.appendRequested([call], request: request)
        try await journal.appendStarted(call, request: request)
        let file = URL(fileURLWithPath: try store.sessionFilePath(agentID: "agent", sessionID: session.id))
        let cache = file.deletingLastPathComponent().appendingPathComponent("summary.json")
        try FileManager.default.removeItem(at: cache)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: false)
        var appendFailure: Error?
        do {
            try await journal.appendOutcome(.init(result: .init(tool: "files.write", ok: true,
                data: .string("known actual result"))), call: call, request: request)
        } catch { appendFailure = error }
        #expect(appendFailure == nil)
        let fresh = AgentSessionFileStore(agentsRootURL: root)
        let detail = try fresh.loadSession(agentID: "agent", sessionID: session.id)
        #expect(detail.events.last?.toolResult?.ok == true)
        #expect(detail.events.last?.toolResult?.data == .string("known actual result"))
        #expect(SessionToolRecovery.unresolvedCalls(in: detail.events).isEmpty)
        let beforePage = try Data(contentsOf: file)
        var page: AgentSessionDetail?
        var pageFailure: Error?
        do { page = try fresh.loadSessionPage(agentID: "agent", sessionID: session.id, limit: 1) }
        catch { pageFailure = error }
        #expect(pageFailure == nil)
        #expect(page?.events.count == 1)
        #expect(page?.events.first?.toolResult?.ok == true)
        #expect(page?.stateEvents?.contains { $0.id == "working" } == true)
        #expect(try Data(contentsOf: file) == beforePage)
    }

    @Test
    func restartProjectsRawContinuationAndResultsInModelOrder() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("loop-journal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentSessionFileStore(agentsRootURL: root)
        let session = try store.createSession(agentID: "agent", request: .init())
        _ = try store.appendEvents(agentID: "agent", sessionID: session.id, events: [
            .init(id: "original", agentId: "agent", sessionId: session.id, type: .message,
                message: .init(role: .user, segments: [.init(kind: .text, text: "Original task")]))
        ])
        let journal = SessionLoopJournal(store: store, agentID: "agent", sessionID: session.id, authorizeWriter: {})
        let request = ModelStepRequest(runId: "run", userTurnId: "turn", stepId: "step", attemptId: "attempt",
            model: "script:model", projectionRevision: "", cacheScope: "scope", messages: [])
        let response = ModelStepResponse(text: "Inspecting", toolCalls: [
            .init(id: "provider-1", name: "files_read", rawArguments: "{\"path\":\"first\"}"),
            .init(id: "provider-2", name: "files_read", rawArguments: "{\"path\":\"second\"}")
        ], stopReason: .toolCalls, continuation: .init(providerId: "script", modelId: "model", format: "signed-v1",
            content: .array([.object(["signature": .string("opaque"), "content": .string("ordered")])])))
        let calls = response.toolCalls.enumerated().map { AgentLoopCall(eventID: "event-\($0.offset)", sourceOrder: $0.offset, call: $0.element) }
        var prepared: ModelStepRequest?
        do {
            try await journal.appendResponse(response, request: request)
            try await journal.appendRequested(calls, request: request)
            for call in calls { try await journal.appendStarted(call, request: request) }
            for call in calls.reversed() {
                try await journal.appendResult(.init(tool: "files.read", ok: true, data: .string("full-\(call.sourceOrder)")), call: call, request: request)
            }
            // Fresh file store and journal: no in-memory transcript can supply the answer.
            let fresh = SessionLoopJournal(store: AgentSessionFileStore(agentsRootURL: root), agentID: "agent",
                sessionID: session.id, authorizeWriter: {})
            prepared = try await fresh.prepareRequest(request)
        } catch { /* The assertions identify the missing durable projection. */ }
        #expect(prepared?.messages.first?.text == "Original task")
        #expect(prepared?.messages.first(where: { $0.role == .assistant })?.continuation == response.continuation)
        #expect(prepared?.messages.first(where: { $0.role == .assistant })?.toolCalls == response.toolCalls)
        #expect(prepared?.messages.compactMap(\.toolOutput?.callId) == ["provider-1", "provider-2"])
        #expect(prepared?.messages.last?.toolOutput?.content.contains("full-1") == true)
        let snapshot = try store.loadJournal(agentID: "agent", sessionID: session.id)
        #expect(snapshot.records.compactMap(\.event.toolResult?.callEventId) == ["event-1", "event-0"])
        #expect(snapshot.records.filter { $0.event.runtimeMetadata?.executionPhase == .started }.count == 2)
        #expect(SessionToolRecovery.unresolvedCalls(in: snapshot.detail.events).isEmpty)
    }

    @Test
    func writerGuardFailureLeavesJournalUntouched() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("loop-guard-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentSessionFileStore(agentsRootURL: root)
        let session = try store.createSession(agentID: "agent", request: .init())
        let path = try store.sessionFilePath(agentID: "agent", sessionID: session.id)
        let before = try Data(contentsOf: URL(fileURLWithPath: path))
        let journal = SessionLoopJournal(store: store, agentID: "agent", sessionID: session.id,
            authorizeWriter: { throw CocoaError(.fileWriteNoPermission) })
        let request = ModelStepRequest(runId: "r", userTurnId: "t", stepId: "s", attemptId: "a", model: "m",
            projectionRevision: "", cacheScope: "", messages: [])
        await #expect(throws: (any Error).self) { try await journal.appendResponse(.init(text: "No write", stopReason: .endTurn), request: request) }
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == before)
    }
    @Test
    func projectedToolErrorRemainsTypedAfterStoreReopen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("typed-tool-error-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentSessionFileStore(agentsRootURL: root)
        let session = try store.createSession(agentID: "agent", request: .init())
        let journal = SessionLoopJournal(store: store, agentID: "agent", sessionID: session.id, authorizeWriter: {})
        let request = ModelStepRequest(runId: "run", userTurnId: "turn", stepId: "step", attemptId: "attempt", model: "fixture",
            projectionRevision: "", cacheScope: "", messages: [], tools: [.init(name: "files_read", toolId: "files.read", parameters: .object([:]))])
        let call = AgentLoopCall(eventID: "event-call", sourceOrder: 0, call: .init(id: "provider-call", name: "files_read", rawArguments: "{}"))
        try await journal.appendResponse(.init(toolCalls: [call.call], stopReason: .toolCalls), request: request)
        try await journal.appendRequested([call], request: request)
        try await journal.appendOutcome(.init(result: .init(tool: "files.read", ok: false, data: .string("An ordinary payload can say success."),
            error: .init(code: "tool_forbidden", message: "Denied by current policy.", retryable: false))), call: call, request: request)
        let fresh = SessionLoopJournal(store: AgentSessionFileStore(agentsRootURL: root), agentID: "agent", sessionID: session.id, authorizeWriter: {})
        let projection = try await fresh.prepareRequest(request)
        #expect(projection.messages.last?.toolOutput?.isError == true)
        #expect(projection.messages.last?.toolOutput?.content.contains("An ordinary payload can say success.") == true)
    }

}
