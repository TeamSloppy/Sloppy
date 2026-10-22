import AnyLanguageModel
import Foundation
import Protocols
import SloppyRuntime
import Testing
@testable import sloppy

@Suite("Session reliability")
struct SessionReliabilityTests {
    private func events(ok: Bool = false, linked: Bool = true) -> [AgentSessionEvent] {
        [
            .init(id: "attempt", agentId: "agent", sessionId: "session", type: .toolCall,
                toolCall: .init(tool: "long_chat.delegate", arguments: ["assignment": .string("{}")])),
            .init(id: "result", agentId: "agent", sessionId: "session", type: .toolResult,
                toolResult: .init(tool: "long_chat.delegate", ok: ok,
                    data: ok ? .object(["id": .string("assignment-1")]) : nil,
                    error: ok ? nil : .init(code: "invalid_arguments", message: "acceptanceCriteria must be a string", retryable: false,
                        hint: "Correct acceptanceCriteria and call again.", argumentRecovery: .init(invalidFields: ["assignment"])),
                    callEventId: linked ? "attempt" : nil)),
        ]
    }

    @Test func typedDelegationAcceptsObjectsAndLegacyStringsButRejectsWrongFieldTypes() throws {
        let raw = #"{"requestKey":"import","title":"Import","acceptanceCriteria":"Visible and readable","tasks":[{"key":"import","title":"Import","objective":"Import authorized skills","resourceKeys":["agent:skills"],"dependsOn":[],"readOnly":false}]}"#
        let object = try JSONDecoder().decode(Protocols.JSONValue.self, from: Data(raw.utf8))
        #expect(try LongChatDelegationDecoder.decode(object).tasks[0].readOnly == false)
        #expect(try LongChatDelegationDecoder.decode(.string(raw)).requestKey == "import")
        var invalid = try #require(object.asObject)
        invalid["acceptanceCriteria"] = .array([.string("Visible")])
        #expect(throws: DecodingError.self) { try LongChatDelegationDecoder.decode(.object(invalid)) }
    }

    @Test func recordedFailedAttemptSurvivesRecoveryAndIsNotAnAbsentAssignment() throws {
        let ledger = SessionActionLedger(events: events(linked: false))
        #expect(ledger.totalCalls == 1)
        #expect(ledger.callsByTool["long_chat.delegate"] == 1)
        #expect(ledger.actions[0].resultEventId == "result")
        #expect(ledger.actions[0].ok == false)
        #expect(ledger.actions[0].assignmentId == nil)
        #expect(ledger.repairableFailure?.callEventId == "attempt")
        let detail = AgentSessionDetail(summary: .init(id: "session", agentId: "agent", title: "Test", messageCount: 0), events: events())
        let restored = AgentSessionTranscriptBuilder.buildRecoveryTranscript(current: detail)
        #expect(restored.contains { if case .toolOutput(let output) = $0 { return output.segments.description.contains("acceptanceCriteria") }; return false })
        #expect(SessionActionLedger(events: events(ok: true)).repairableFailure == nil)
    }

    @Test func ledgerCountsIncludeOmittedCallsAndSuccessfulCorrectionsResolveFailure() {
        var records = events()
        records.append(contentsOf: events(ok: true).map { event in
            var changed = event
            changed.id += "-corrected"
            changed.toolResult?.callEventId = "attempt-corrected"
            return changed
        })
        let ledger = SessionActionLedger(events: records, limit: 1)
        #expect(ledger.totalCalls == 2 && ledger.omittedCalls == 1)
        #expect(ledger.callsByTool["long_chat.delegate"] == 2)
        #expect(ledger.repairableFailure == nil)
        #expect(ledger.actions[0].assignmentId == "assignment-1")
    }

    @Test func falseDenialIsCorrectedInOneReviewWithoutExposingInternalIDs() async {
        let ledger = SessionActionLedger(events: events())
        let corrected = "The task could not be assigned because its completion requirements were malformed. No worker started."
        let replies = ReviewReplies([#"{"supported":false,"correctedResponse":"\#(corrected)"}"#])
        let answer = await CoordinatorResponseReview.verifiedResponse(
            candidate: "There was no delegation call. I invented the attempt.", userRequest: "What error?", ledger: ledger,
            review: { prompt in
                #expect(prompt.contains("attempt") && prompt.contains("invalid_arguments"))
                return await replies.next()
            })
        #expect(answer == corrected)
        #expect(await replies.count == 1)
    }

    @Test func invalidReviewCannotPublishUnsupportedExplanation() async {
        let ledger = SessionActionLedger(events: events())
        let answer = await CoordinatorResponseReview.verifiedResponse(candidate: "Permission was denied.", userRequest: "Why?", ledger: ledger, review: { _ in "not JSON" })
        #expect(answer == ledger.factualFallback)
        #expect(!answer.contains("invalid_arguments") && !answer.contains("callEventId"))
        #expect(!answer.contains("Permission was denied"))
    }

    @Test func successfulToolTransportDoesNotHideFailedCommand() {
        let ledger = SessionActionLedger(events: [
            .init(id: "ocr", agentId: "agent", sessionId: "session", type: .toolCall, toolCall: .init(tool: "runtime.exec", arguments: [:])),
            .init(agentId: "agent", sessionId: "session", type: .toolResult,
                toolResult: .init(tool: "runtime.exec", ok: true, data: .object(["exitCode": .number(255), "timedOut": .bool(false)]), callEventId: "ocr")),
        ])
        #expect(ledger.actions[0].ok == true && ledger.actions[0].exitCode == 255)
        #expect(ledger.context.contains("255"))
    }

    @Test func delegationReviewRetainsObjectiveTaskIdentityAndLatestQueueState() throws {
        let raw = #"{"id":"assignment-1","title":"Chat navigation","tasks":[{"id":"task-92226","title":"Scroll to latest","objective":"Add the down button in ClientNative"}]}"#
        var records = events(ok: true)
        let assignment = try JSONDecoder().decode(Protocols.JSONValue.self, from: Data(raw.utf8))
        records[0].toolCall?.arguments = ["assignment": assignment]
        records[1].toolResult?.data = assignment
        let queued = taskEvent(id: "task-92226", status: .queued)
        let running = taskEvent(id: "task-92226", status: .running)
        let ledger = SessionActionLedger(events: records, detailsLimit: 6, taskEvents: [queued, running])
        #expect(ledger.actions[0].assignmentId == "assignment-1")
        #expect(ledger.actions[0].details?.arguments != nil)
        #expect(ledger.context.contains("Add the down button in ClientNative"))
        #expect(ledger.context.contains("task-92226"))
        #expect(ledger.tasks.count == 1 && ledger.tasks[0].status == .running)
    }

    @Test func reportReadPreservesItsContentAndCompleteness() {
        let report = "Delivered new chat and annotation zoom. 29 tests passed. Physical pinch remains unverified."
        let ledger = SessionActionLedger(events: [
            .init(id: "read-report", agentId: "a", sessionId: "s", type: .toolCall,
                toolCall: .init(tool: "files.read", arguments: ["path": .string("/workspace/REPORT.md")])),
            .init(agentId: "a", sessionId: "s", type: .toolResult,
                toolResult: .init(tool: "files.read", ok: true,
                    data: .object(["content": .string(report), "truncated": .bool(false)]), callEventId: "read-report")),
        ], detailsLimit: 6)
        #expect(ledger.actions[0].details?.result?.asObject?["content"] == .string(report))
        #expect(ledger.actions[0].details?.result?.asObject?["truncated"] == .bool(false))
        #expect(ledger.actions[0].details?.truncated == false)
    }

    @Test func workerNotificationIsReviewedWithResultsEvenWithoutCoordinatorToolCalls() async {
        var completed = taskEvent(id: "scroll", status: .failed)
        completed.task.attempts[0].summary = "Scrolling implemented; final live app verification is blocked."
        completed.task.attempts[0].evidence = ["7 pagination tests passed", "21 native layout tests passed"]
        completed.task.attempts[0].artifacts = ["/workspace/scroll-tests.log"]
        let next = taskEvent(id: "annotations", status: .running)
        let ledger = SessionActionLedger(events: [], taskEvents: [completed, next])
        let replies = ReviewReplies([#"{"supported":true,"correctedResponse":null}"#])
        let answer = await CoordinatorResponseReview.verifiedResponse(
            candidate: "Scrolling is implemented and tests passed; live app verification remains. Annotation work has started.",
            userRequest: "Worker update", ledger: ledger, isWorkerNotification: true,
            review: { prompt in
                #expect(prompt.contains("21 native layout tests passed"))
                #expect(prompt.contains("/workspace/scroll-tests.log"))
                #expect(prompt.contains("annotations") && prompt.contains("running"))
                #expect(prompt.contains("live app verification is blocked"))
                return await replies.next()
            })
        #expect(answer.contains("Annotation work has started"))
        #expect(await replies.count == 1)
    }

    @Test func ordinaryConversationDoesNotReviewOldTaskActivity() async {
        let ledger = SessionActionLedger(events: [], taskEvents: [taskEvent(id: "old-task", status: .completed)])
        let replies = ReviewReplies([])
        let answer = await CoordinatorResponseReview.verifiedResponse(candidate: "You're welcome!", userRequest: "Thanks!",
            ledger: ledger, review: { _ in await replies.next() })
        #expect(answer == "You're welcome!")
        #expect(await replies.count == 0)
    }

    @Test func workerEvidenceIsBoundedWithoutLosingTrailingLimitations() throws {
        let updates = (0..<20).map { index in
            var update = taskEvent(id: "task-\(index)", status: .failed)
            update.task.attempts[0].summary = "Implemented. " + String(repeating: "details ", count: 5_000) + "Physical pinch remains unverified."
            update.task.attempts[0].evidence = Array(repeating: String(repeating: "check ", count: 1_000), count: 20)
            return update
        }
        let ledger = SessionActionLedger(events: [], taskEvents: updates)
        #expect(ledger.tasks.count == 12)
        #expect(ledger.tasks.first?.taskId == "task-19")
        #expect(ledger.tasks.first?.summary?.contains("Physical pinch remains unverified.") == true)
        #expect(ledger.tasks.first?.truncated == true)
        #expect(try JSONEncoder().encode(ledger).count < 40_000)
        let historical = SessionActionLedger(events: updates.map {
            .init(agentId: "a", sessionId: "s", type: .longChatTask, longChatTask: $0)
        })
        #expect(historical.tasks.isEmpty)
    }

    @Test func reviewDetailsAreBoundedAndDoNotIncludeBinaryOrCredentialFields() throws {
        let ledger = SessionActionLedger(events: [
            .init(id: "check", agentId: "a", sessionId: "s", type: .toolCall,
                toolCall: .init(tool: "runtime.exec", arguments: ["command": .string("swift"), "env": .object(["TOKEN": .string("secret-token")])])),
            .init(agentId: "a", sessionId: "s", type: .toolResult,
                toolResult: .init(tool: "runtime.exec", ok: true, data: .object([
                    "exitCode": .number(1), "stdout": .string(String(repeating: "x", count: 100_000) + "Test run failed"),
                    "imageBase64": .string("private-image"), "accessToken": .string("secret-token"),
                ]), callEventId: "check")),
        ], detailsLimit: 6)
        let encoded = String(decoding: try JSONEncoder().encode(ledger), as: UTF8.self)
        #expect(encoded.count < 12_000)
        #expect(!encoded.contains("private-image") && !encoded.contains("secret-token"))
        #expect(encoded.contains("Test run failed"))
        #expect(ledger.actions[0].details?.truncated == true)
        #expect(ledger.actions[0].exitCode == 1)
    }

    private func taskEvent(id: String, status: LongChatTaskStatus) -> LongChatTaskEvent {
        var attempt = LongChatAttempt(number: 1)
        attempt.status = status
        return .init(assignmentId: "assignment-1", task: .init(
            id: id, key: id, title: id, objective: "Implement requested ClientNative changes", projectId: "sloppy",
            resourceKeys: ["project:sloppy"], dependsOn: [], attempts: [attempt]), reason: status.rawValue)
    }

    @Test func missingOrInvalidImageKeepsMetadataWithoutInventingPixels() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bad = root.appendingPathComponent("bad.png")
        try Data("not an image".utf8).write(to: bad)
        #expect(throws: SessionImageLoader.LoadError.self) { try SessionImageLoader.load(url: bad, mimeType: "image/png") }
    }

    @Test func restoredImageBudgetUsesActualBytesInsteadOfDeclaredSize() {
        let data = Data(repeating: 0, count: 8 * 1024 * 1024)
        let events = (0..<4).map { index in
            AgentSessionEvent(agentId: "agent", sessionId: "session", type: .message,
                message: .init(role: .user, segments: [.init(kind: .attachment, attachment: .init(
                    id: "image-\(index)", name: "image.png", mimeType: "image/png", sizeBytes: 0))]))
        }
        let detail = AgentSessionDetail(summary: .init(id: "session", agentId: "agent", title: "Images", messageCount: 4), events: events)
        let transcript = AgentSessionTranscriptBuilder.buildRecoveryTranscript(current: detail, imageLoader: { _ in .init(source: .data(data, mimeType: "image/png")) })
        let count = transcript.reduce(0) { count, entry in
            guard case .prompt(let prompt) = entry else { return count }
            return count + prompt.segments.filter { if case .image = $0 { return true }; return false }.count
        }
        #expect(count == 3)
    }
}

private actor ReviewReplies {
    private let replies: [String]
    private(set) var count = 0
    init(_ replies: [String]) { self.replies = replies }
    func next() -> String? {
        defer { count += 1 }
        return count < replies.count ? replies[count] : nil
    }
}

extension CoreService {
    fileprivate func reserveReliabilityTurn(sessionID: String) { longChatCurrentTurns[sessionID] = UUID().uuidString }
}

@Test func malformedLongChatDelegationExplainsCorrectionWithoutCreatingWork() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    _ = try await service.createAgent(.init(id: "reliable", displayName: "Reliable", role: "Test"))
    let session = try await service.openLongChat(agentID: "reliable", userID: "local")
    await service.reserveReliabilityTurn(sessionID: session.id)
    let invalid: Protocols.JSONValue = .object(["requestKey": .string("import"), "title": .string("Import"), "acceptanceCriteria": .array([.string("Visible")]), "tasks": .array([])])
    let result = await service.invokeLongChatTool(agentID: "reliable", sessionID: session.id, request: .init(tool: "long_chat.delegate", arguments: ["assignment": invalid]))
    #expect(!result.ok)
    #expect(result.error?.code == "invalid_arguments")
    #expect(result.error?.hint?.contains("acceptanceCriteria must be a string") == true)
    #expect(result.error?.argumentRecovery?.invalidFields == ["assignment"])
    #expect(try await service.getLongChat(agentID: "reliable", sessionID: session.id).assignments.isEmpty)
    await service.stop()
}
