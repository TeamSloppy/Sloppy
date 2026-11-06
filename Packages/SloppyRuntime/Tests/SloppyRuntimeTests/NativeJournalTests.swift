import Foundation
import AnyLanguageModel
import AgentRuntime
import PluginSDK
import Protocols
import SloppyRuntime
import Testing

private struct NativeJournalFixture {
    let root: URL
    let store: AgentSessionFileStore
    let sessionID: String
    let agentID = "journal-agent"

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("native-journal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent(agentID), withIntermediateDirectories: true)
        store = AgentSessionFileStore(agentsRootURL: root)
        sessionID = try store.createSession(agentID: agentID, request: .init(),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)).id
    }

    var file: URL {
        get throws { URL(fileURLWithPath: try store.sessionFilePath(agentID: agentID, sessionID: sessionID)) }
    }

    func message(_ id: String, version: Int = 1, seconds: TimeInterval = 1) -> AgentSessionEvent {
        AgentSessionEvent(id: id, version: version, agentId: agentID, sessionId: sessionID, type: .message,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000 + seconds),
            message: .init(role: .user, segments: [.init(kind: .text, text: id)]))
    }

    func appendRaw(_ events: [AgentSessionEvent]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        for event in events {
            var data = try encoder.encode(event)
            data.append(0x0A)
            try handle.write(contentsOf: data)
        }
        try handle.synchronize()
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}

private enum JournalAccess: CaseIterable {
    case full, page, append
}

@Suite("Native journal compatibility and order")
struct NativeJournalTests {
    @Test(arguments: ["live", "historical", "wrong_run", "wrong_usage", "wrong_scope", "wrong_id"])
    func fallbackUsageMetadataRoundTripsAndBindsToItsOwner(claim: String) throws {
        let fixture = try NativeJournalFixture()
        defer { fixture.cleanUp() }
        let historical = claim == "historical"
        let agent = historical ? "source-agent" : fixture.agentID
        let session = historical ? "source-session" : fixture.sessionID
        let channel = "agent:\(agent):session:\(session)"
        let usage = Protocols.TokenUsage(prompt: 17, completion: 5)
        let identity = "native:" + ContentDigest.sha256(try JSONEncoder().encode([channel, "run", "turn", "step", "attempt"]))
        var record = UsageRequestRecord(id: identity, channelId: channel, sessionId: session, agentId: agent,
            provider: "fixture", model: "fixture:model", createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            usage: usage, complete: false, runId: "run", userTurnId: "turn")
        if claim == "wrong_run" { record.runId = "other" }
        if claim == "wrong_usage" { record.usage = .init(prompt: 18, completion: 5) }
        if claim == "wrong_scope" { record.agentId = "other" }
        if claim == "wrong_id" { record.id = "other" }
        let response = ModelStepResponse(text: "Done", stopReason: .endTurn, usage: usage)
        var raw = try #require(JSONValueCoder.encode(AgentRunMetadata(schemaVersion: 2,
            runId: "run", userTurnId: "turn", stepId: "step", attemptId: "attempt",
            modelResponse: try JSONValueCoder.encode(response))).asObject)
        raw["usageRequest"] = try JSONValueCoder.encode(record)
        var event = AgentSessionEvent(id: "response", version: 2, agentId: fixture.agentID, sessionId: fixture.sessionID,
            type: .runStatus, runtimeMetadata: try JSONValueCoder.decode(AgentRunMetadata.self, from: .object(raw)))
        if historical { event.forkOrigin = .init(sourceAgentId: agent, sourceSessionId: session, sourceEventId: "source-event") }
        let before = try Data(contentsOf: fixture.file)
        var failure: Error?
        do { _ = try fixture.store.appendEvents(agentID: fixture.agentID, sessionID: fixture.sessionID, events: [event]) }
        catch { failure = error }
        if claim == "live" || historical {
            #expect(failure == nil)
            guard failure == nil else { return }
            let fresh = AgentSessionFileStore(agentsRootURL: fixture.root)
            let loaded = try #require(try fresh.loadSession(agentID: fixture.agentID, sessionID: fixture.sessionID).events.first { $0.id == event.id })
            #expect(try JSONValueCoder.encode(loaded.runtimeMetadata).asObject?["usageRequest"] == JSONValueCoder.encode(record))
            #expect(loaded.isHistorical == historical)
        } else {
            #expect(failure != nil)
            #expect(try Data(contentsOf: fixture.file) == before)
        }
        #expect(AgentRunMetadata(runId: "legacy", userTurnId: "legacy").schemaVersion == 1)
    }

    @Test
    func attachmentPersistenceDistinguishesAbsentAndEmptyInlineData() throws {
        let fixture = try NativeJournalFixture()
        defer { fixture.cleanUp() }
        let attachments = try fixture.store.persistAttachments(agentID: fixture.agentID, sessionID: fixture.sessionID, uploads: [
            .init(name: "absent.txt", mimeType: "text/plain", sizeBytes: 0),
            .init(name: "empty.txt", mimeType: "text/plain", sizeBytes: 0, contentBase64: ""),
            .init(name: "data.txt", mimeType: "text/plain", sizeBytes: 3, contentBase64: Data("abc".utf8).base64EncodedString())
        ])
        #expect(attachments.count == 3)
        #expect(attachments[0].relativePath == nil)
        #expect(attachments[1].relativePath != nil)
        let reopened = AgentSessionFileStore(agentsRootURL: fixture.root)
        let empty = try #require(try reopened.resolveAttachmentFileURL(agentID: fixture.agentID, attachment: attachments[1]))
        let data = try #require(try reopened.resolveAttachmentFileURL(agentID: fixture.agentID, attachment: attachments[2]))
        #expect(try Data(contentsOf: empty).isEmpty)
        #expect(try Data(contentsOf: data) == Data("abc".utf8))
    }

    @Test
    func excludedReceiptImagesCannotConsumeTheRecoveryImageBudget() throws {
        let fixture = try NativeJournalFixture()
        defer { fixture.cleanUp() }
        var eligible = fixture.message("eligible-image")
        let admittedImage = AgentAttachment(id: "eligible", name: "eligible.png", mimeType: "image/png", sizeBytes: 1)
        eligible.message?.segments.append(.init(kind: .attachment, attachment: admittedImage))
        var events = [eligible]
        for index in 0..<8 {
            let id = UUID().uuidString
            let attachment = AgentAttachment(id: "excluded-\(index)", name: "queued.png", mimeType: "image/png", sizeBytes: 1)
            var event = fixture.message(id, version: 3)
            event.message?.id = id
            event.message?.segments.append(.init(kind: .attachment, attachment: attachment))
            event.inputTransitions = [.init(messageId: id, fingerprint: "v2:" + String(repeating: "a", count: 64),
                disposition: .queued, context: .init(request: .init(userId: "fixture", content: id,
                    attachments: [.init(name: "queued.png", mimeType: "image/png", sizeBytes: 1)], clientMessageId: id),
                    attachments: [.init(attachment: attachment, hadInlineData: false)]))]
            events.append(event)
        }
        _ = try fixture.store.appendEvents(agentID: fixture.agentID, sessionID: fixture.sessionID, events: events)
        let detail = try fixture.store.loadSession(agentID: fixture.agentID, sessionID: fixture.sessionID)
        var loaded: [String] = []
        let transcript = AgentSessionTranscriptBuilder.buildRecoveryTranscript(current: detail, imageLoader: { attachment in
            loaded.append(attachment.id)
            return .init(id: attachment.id, source: .data(Data([1]), mimeType: "image/png"))
        })
        #expect(loaded == ["eligible"])
        let imageIDs = transcript.flatMap { entry -> [String] in
            guard case .prompt(let prompt) = entry else { return [] }
            return prompt.segments.compactMap { segment in
                guard case .image(let image) = segment else { return nil }
                return image.id
            }
        }
        #expect(imageIDs == ["eligible"])
    }

    @Test(arguments: ["user", "text", "attachments", "origin", "ui_support"])
    func firstInputContextMustMatchThePersistedPresentation(field: String) throws {
        let fixture = try NativeJournalFixture()
        defer { fixture.cleanUp() }
        let id = UUID().uuidString
        let attachment = AgentAttachment(id: "asset", name: "input.txt", mimeType: "text/plain", sizeBytes: 1)
        let request = AgentSessionPostMessageRequest(userId: "fixture", content: "Original task",
            attachments: [.init(name: "input.txt", mimeType: "text/plain", sizeBytes: 1)], clientMessageId: id)
        var event = AgentSessionEvent(version: 3, agentId: fixture.agentID, sessionId: fixture.sessionID, type: .message,
            message: .init(id: id, role: .user, segments: [.init(kind: .text, text: request.content),
                .init(kind: .attachment, attachment: attachment)], userId: request.userId))
        var context = AgentInputContext(request: request, attachments: [.init(attachment: attachment, hadInlineData: false)])
        switch field {
        case "user": context.request.userId = "another-user"
        case "text": context.request.content = "Different task"
        case "attachments": context.attachments[0].attachment.id = "different-asset"
        case "origin": context.peerOrigin = .init(agentId: "peer", sessionId: "peer-session", chainId: "chain", depth: 1)
        default: context.request.supportsA2UI = true
        }
        event.inputTransitions = [.init(messageId: id, fingerprint: "v2:" + String(repeating: "a", count: 64), disposition: .queued, context: context)]
        let before = try Data(contentsOf: fixture.file)
        #expect(throws: AgentSessionFileStore.StoreError.self) {
            _ = try fixture.store.appendEvents(agentID: fixture.agentID, sessionID: fixture.sessionID, events: [event])
        }
        #expect(try Data(contentsOf: fixture.file) == before)
    }

    @Test
    func firstAdmissionCannotClaimAnEarlierGeneration() throws {
        let fixture = try NativeJournalFixture()
        defer { fixture.cleanUp() }
        let id = UUID().uuidString
        let fingerprint = "v2:" + String(repeating: "a", count: 64)
        var event = fixture.message(id, version: 3)
        event.message?.id = id
        event.inputTransitions = [.init(messageId: id, fingerprint: fingerprint, disposition: .admitted,
            owner: .init(runId: "run", userTurnId: id, generation: 4),
            context: .init(request: .init(userId: "fixture", content: id, clientMessageId: id)))]
        event.runtimeMetadata = .init(runId: "run", userTurnId: id, generation: 5,
            inputMessageId: id, requestFingerprint: fingerprint)
        let before = try Data(contentsOf: fixture.file)
        #expect(throws: AgentSessionFileStore.StoreError.self) {
            _ = try fixture.store.appendEvents(agentID: fixture.agentID, sessionID: fixture.sessionID, events: [event])
        }
        #expect(try Data(contentsOf: fixture.file) == before)
    }

    @Test(arguments: [1, 2], JournalAccess.allCases)
    fileprivate func inputLifecycleCannotBeSilentlyDiscardedWithoutRuntimeMetadata(version: Int, access: JournalAccess) throws {
        let fixture = try NativeJournalFixture()
        defer { fixture.cleanUp() }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try #require(JSONSerialization.jsonObject(with: encoder.encode(fixture.message("tagged", version: version))) as? [String: Any])
        object["inputTransitions"] = [["schemaVersion": 999, "messageId": UUID().uuidString]]
        var row = try JSONSerialization.data(withJSONObject: object)
        row.append(0x0A)
        let handle = try FileHandle(forWritingTo: fixture.file)
        try handle.seekToEnd()
        try handle.write(contentsOf: row)
        try handle.synchronize()
        try handle.close()
        let before = try Data(contentsOf: fixture.file)
        #expect(throws: AgentSessionFileStore.StoreError.self) {
            switch access {
            case .full: _ = try fixture.store.loadSession(agentID: fixture.agentID, sessionID: fixture.sessionID)
            case .page: _ = try fixture.store.loadSessionPage(agentID: fixture.agentID, sessionID: fixture.sessionID, limit: 1)
            case .append: _ = try fixture.store.appendEvents(agentID: fixture.agentID, sessionID: fixture.sessionID, events: [fixture.message("tail")])
            }
        }
        #expect(try Data(contentsOf: fixture.file) == before)
    }

    @Test
    func neverAdmittedInputsRemainOutsideModelAndMemoryHistoryAfterReopen() throws {
        let fixture = try NativeJournalFixture()
        defer { fixture.cleanUp() }
        let queuedID = UUID().uuidString
        let cancelledID = UUID().uuidString
        let fingerprint = "v2:" + String(repeating: "a", count: 64)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var rows: [[String: Any]] = []
        for id in [queuedID, cancelledID] {
            var event = fixture.message(id, version: 3)
            event.message?.id = id
            var object = try #require(JSONSerialization.jsonObject(with: encoder.encode(event)) as? [String: Any])
            let request = AgentSessionPostMessageRequest(userId: "fixture", content: id, clientMessageId: id)
            object["inputTransitions"] = [["schemaVersion": 1, "messageId": id,
                "fingerprint": fingerprint, "disposition": "queued", "delivery": "pending",
                "context": ["request": try JSONSerialization.jsonObject(with: encoder.encode(request)), "attachments": []]]]
            rows.append(object)
        }
        var control = try #require(JSONSerialization.jsonObject(with: encoder.encode(
            AgentSessionEvent(version: 3, agentId: fixture.agentID, sessionId: fixture.sessionID, type: .runControl,
                runControl: .init(action: .interrupt, requestedBy: "fixture")))) as? [String: Any])
        control["inputTransitions"] = [["schemaVersion": 1, "messageId": cancelledID,
            "fingerprint": fingerprint, "disposition": "cancelled", "delivery": "delivered"]]
        rows.append(control)
        _ = try fixture.store.appendEvents(agentID: fixture.agentID, sessionID: fixture.sessionID, events: [fixture.message("legacy-task")])
        let handle = try FileHandle(forWritingTo: fixture.file)
        try handle.seekToEnd()
        for object in rows {
            var row = try JSONSerialization.data(withJSONObject: object)
            row.append(0x0A)
            try handle.write(contentsOf: row)
        }
        try handle.synchronize()
        try handle.close()
        let reopened = AgentSessionFileStore(agentsRootURL: fixture.root)
        var detail: AgentSessionDetail?
        var failure: Error?
        do { detail = try reopened.loadSession(agentID: fixture.agentID, sessionID: fixture.sessionID) }
        catch { failure = error }
        #expect(failure == nil)
        guard let detail else { return }
        #expect(detail.events.compactMap(\.message).count == 3)
        let messages = try SessionProjection.load(store: reopened, agentID: fixture.agentID, sessionID: fixture.sessionID).modelMessages()
        #expect(messages.map(\.text) == ["legacy-task"])
        let memory = AgentSessionTranscriptBuilder.buildRecoveryTranscript(current: detail)
        #expect(memory.count == 1)
        let roundTrip = try #require(JSONSerialization.jsonObject(with: encoder.encode(detail.events.first { $0.message?.id == queuedID })) as? [String: Any])
        #expect((roundTrip["inputTransitions"] as? [[String: Any]])?.first?["messageId"] as? String == queuedID)
    }

    @Test(arguments: [false, true], JournalAccess.allCases)
    fileprivate func futureRunSnapshotCannotBeReadOrExtended(warmCache: Bool, access: JournalAccess) throws {
        let fixture = try NativeJournalFixture()
        defer { fixture.cleanUp() }
        if warmCache { _ = try fixture.store.loadSession(agentID: fixture.agentID, sessionID: fixture.sessionID) }
        let snapshot = RunStateSnapshot(schemaVersion: 999, runID: "run", userTurnID: "turn")
        let future = AgentSessionEvent(version: 2, agentId: fixture.agentID, sessionId: fixture.sessionID, type: .runStatus,
            runtimeMetadata: .init(runId: "run", userTurnId: "turn", runState: try JSONValueCoder.encode(snapshot)))
        try fixture.appendRaw([future, fixture.message("tail")])
        let before = try Data(contentsOf: fixture.file)
        #expect(throws: AgentSessionFileStore.StoreError.self) {
            switch access {
            case .full: _ = try fixture.store.loadSession(agentID: fixture.agentID, sessionID: fixture.sessionID)
            case .page: _ = try fixture.store.loadSessionPage(agentID: fixture.agentID, sessionID: fixture.sessionID, limit: 1)
            case .append: _ = try fixture.store.appendEvents(agentID: fixture.agentID, sessionID: fixture.sessionID, events: [fixture.message("must-not-write")])
            }
        }
        #expect(try Data(contentsOf: fixture.file) == before)
    }

    @Test
    func appendPreservesAValidLegacyFinalLineWithoutNewline() throws {
        let fixture = try NativeJournalFixture()
        defer { fixture.cleanUp() }
        _ = try fixture.store.appendEvents(agentID: fixture.agentID, sessionID: fixture.sessionID,
            events: [fixture.message("first")])
        var data = try Data(contentsOf: fixture.file)
        #expect(data.last == 0x0A)
        data.removeLast()
        try data.write(to: fixture.file)
        _ = try fixture.store.appendEvents(agentID: fixture.agentID, sessionID: fixture.sessionID,
            events: [fixture.message("second")])
        let detail = try AgentSessionFileStore(agentsRootURL: fixture.root).loadSession(agentID: fixture.agentID, sessionID: fixture.sessionID)
        #expect(detail.events.suffix(2).map(\.id) == ["first", "second"])
    }

    @Test(arguments: [false, true])
    func requestedAndStartedCallsHaveDifferentCrashOutcomes(started: Bool) throws {
        let fixture = try NativeJournalFixture()
        defer { fixture.cleanUp() }
        let call = AgentSessionEvent(id: "requested", version: 2, agentId: fixture.agentID, sessionId: fixture.sessionID,
            type: .toolCall, runtimeMetadata: .init(runId: "run", userTurnId: "turn", callEventId: "requested", executionPhase: .requested),
            toolCall: .init(tool: "files.write", arguments: ["path": .string("a.txt")]))
        var events = [call]
        if started {
            events.append(.init(version: 2, agentId: fixture.agentID, sessionId: fixture.sessionID, type: .runStatus,
                runtimeMetadata: .init(runId: "run", userTurnId: "turn", callEventId: call.id, executionPhase: .started)))
        }
        _ = try fixture.store.appendEvents(agentID: fixture.agentID, sessionID: fixture.sessionID, events: events)
        let detail = try fixture.store.loadSession(agentID: fixture.agentID, sessionID: fixture.sessionID)
        let recovered = SessionToolRecovery.interruptionEvents(for: detail)
        let result = try #require(recovered.first?.toolResult)
        #expect(result.callEventId == call.id)
        #expect(result.executionOutcome?.requiresReconciliation == started)
        #expect(result.error?.code == (started ? "tool_execution_interrupted" : "tool_not_started"))
        #expect(SessionToolRecovery.requiresReconciliation(tool: "files.write", arguments: ["path": .string("a.txt")], events: detail.events + recovered) == started)
    }

    @Test
    func compatibleCheckpointKeepsOriginalTaskAndProjectsJournalTail() throws {
        let fixture = try NativeJournalFixture()
        defer { fixture.cleanUp() }
        var old = fixture.message("old-details")
        old.message?.role = .assistant
        _ = try fixture.store.appendEvents(agentID: fixture.agentID, sessionID: fixture.sessionID,
            events: [fixture.message("original-task"), old])
        let coveredCursor = try Data(contentsOf: fixture.file).count
        let checkpoint = AgentSessionEvent(id: "checkpoint", version: 2, agentId: fixture.agentID,
            sessionId: fixture.sessionID, type: .memoryCheckpoint,
            runtimeMetadata: .init(runId: "run", userTurnId: "turn"))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try #require(JSONSerialization.jsonObject(with: encoder.encode(checkpoint)) as? [String: Any])
        var metadata = try #require(object["runtimeMetadata"] as? [String: Any])
        metadata["checkpoint"] = [
            "projectionVersion": 1, "coveredCursor": coveredCursor, "coveredThroughEventId": old.id,
            "summary": "condensed earlier work", "retainedEventIds": ["original-task"], "artifactRefs": [],
        ] as [String: Any]
        object["runtimeMetadata"] = metadata
        let handle = try FileHandle(forWritingTo: fixture.file)
        try handle.seekToEnd()
        var payload = try JSONSerialization.data(withJSONObject: object)
        payload.append(0x0A)
        try handle.write(contentsOf: payload)
        try handle.synchronize()
        try handle.close()
        _ = try fixture.store.appendEvents(agentID: fixture.agentID, sessionID: fixture.sessionID,
            events: [fixture.message("latest-request")])
        let projection = try SessionProjection.load(store: fixture.store, agentID: fixture.agentID, sessionID: fixture.sessionID)
        let text = projection.transcript.map { entry -> String in
            switch entry {
            case .prompt(let prompt): return prompt.segments.compactMap { if case .text(let text) = $0 { return text.content }; return nil }.joined()
            case .response(let response): return response.segments.compactMap { if case .text(let text) = $0 { return text.content }; return nil }.joined()
            default: return ""
            }
        }.joined(separator: "\n")
        #expect(text.contains("condensed earlier work"))
        #expect(text.contains("original-task"))
        #expect(text.contains("latest-request"))
        #expect(!text.contains("old-details"))
        #expect(projection.journal.cursor == UInt64(try Data(contentsOf: fixture.file).count))
    }

    @Test(arguments: [false, true], JournalAccess.allCases)
    fileprivate func futureJournalCannotBeReadOrExtended(warmCache: Bool, access: JournalAccess) throws {
        let fixture = try NativeJournalFixture()
        defer { fixture.cleanUp() }
        if warmCache { _ = try fixture.store.loadSession(agentID: fixture.agentID, sessionID: fixture.sessionID) }
        // The incompatible entry is outside the selected page, so tail decoding alone is insufficient.
        try fixture.appendRaw([fixture.message("future", version: 999), fixture.message("tail")])
        let before = try Data(contentsOf: fixture.file)
        #expect(throws: AgentSessionFileStore.StoreError.self) {
            switch access {
            case .full:
                _ = try fixture.store.loadSession(agentID: fixture.agentID, sessionID: fixture.sessionID)
            case .page:
                _ = try fixture.store.loadSessionPage(agentID: fixture.agentID, sessionID: fixture.sessionID, limit: 1)
            case .append:
                _ = try fixture.store.appendEvents(agentID: fixture.agentID, sessionID: fixture.sessionID,
                    events: [fixture.message("must-not-write")])
            }
        }
        #expect(try Data(contentsOf: fixture.file) == before)
    }

    @Test
    func futureEventIsRejectedBeforeWriting() throws {
        let fixture = try NativeJournalFixture()
        defer { fixture.cleanUp() }
        let before = try Data(contentsOf: fixture.file)
        #expect(throws: AgentSessionFileStore.StoreError.self) {
            _ = try fixture.store.appendEvents(agentID: fixture.agentID, sessionID: fixture.sessionID,
                events: [fixture.message("future", version: 999)])
        }
        #expect(try Data(contentsOf: fixture.file) == before)
    }

    @Test
    func physicalOrderSurvivesClockSkewAndCaches() throws {
        let fixture = try NativeJournalFixture()
        defer { fixture.cleanUp() }
        let events = [fixture.message("first", seconds: 20), fixture.message("second", seconds: 10)]
        _ = try fixture.store.appendEvents(agentID: fixture.agentID, sessionID: fixture.sessionID, events: events)
        let cached = try fixture.store.loadSession(agentID: fixture.agentID, sessionID: fixture.sessionID)
        #expect(cached.events.suffix(2).map(\.id) == ["first", "second"])
        let reopened = AgentSessionFileStore(agentsRootURL: fixture.root)
        #expect(try reopened.loadSession(agentID: fixture.agentID, sessionID: fixture.sessionID).events.suffix(2).map(\.id) == ["first", "second"])
        #expect(try reopened.loadSessionPage(agentID: fixture.agentID, sessionID: fixture.sessionID, limit: 2).events.map(\.id) == ["first", "second"])
    }

    @Test
    func runtimeMetadataRoundTripsAndLegacyEventsRemainReadable() throws {
        let fixture = try NativeJournalFixture()
        defer { fixture.cleanUp() }
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let original = fixture.message("metadata")
        #expect(try decoder.decode(AgentSessionEvent.self, from: encoder.encode(original)) == original)
        var raw = try #require(JSONSerialization.jsonObject(with: encoder.encode(original)) as? [String: Any])
        let metadata: [String: Any] = [
            "schemaVersion": 1, "runId": "run-1", "userTurnId": "turn-1", "stepId": "step-1",
            "attemptId": "attempt-1", "generation": 3, "sourceOrder": 2, "providerCallId": "call-1",
            "callEventId": "event-1", "executionPhase": "started", "engineVersion": 1,
            "completionPolicyVersion": 1,
        ]
        raw["runtimeMetadata"] = metadata
        let decoded = try decoder.decode(AgentSessionEvent.self, from: JSONSerialization.data(withJSONObject: raw))
        let encoded = try #require(JSONSerialization.jsonObject(with: encoder.encode(decoded)) as? [String: Any])
        let actual = encoded["runtimeMetadata"] as? NSDictionary
        #expect(actual == metadata as NSDictionary)
        #expect(decoded.metadata == original.metadata)
    }
}
