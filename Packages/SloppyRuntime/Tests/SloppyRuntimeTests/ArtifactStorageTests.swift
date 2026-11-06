import Foundation
import AgentRuntime
import PluginSDK
import Protocols
import Testing
@testable import SloppyRuntime

@Suite("Complete output storage")
struct ArtifactStorageTests {
    @Test
    func copiedHistoryOwnsItsAssetsAndCorrelationsWithoutSourceAuthority() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("history-copy-\(UUID())")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentSessionFileStore(agentsRootURL: root)
        let source = try store.createSession(agentID: "agent", request: .init())
        let target = try store.createSession(agentID: "agent", request: .init())
        let bytes = Data("original attachment".utf8)
        let asset = try #require(try store.persistAttachments(agentID: "agent", sessionID: source.id,
            uploads: [.init(name: "note.txt", mimeType: "text/plain", sizeBytes: bytes.count, contentBase64: bytes.base64EncodedString())]).first)
        let callID = UUID().uuidString
        let events: [AgentSessionEvent] = [
            .init(agentId: "agent", sessionId: source.id, type: .message,
                message: .init(role: .user, segments: [.init(kind: .text, text: "Keep this context"), .init(kind: .attachment, attachment: asset)])),
            .init(id: callID, agentId: "agent", sessionId: source.id, type: .toolCall,
                toolCall: .init(tool: "files.read", arguments: ["path": .string("note.txt")])),
            .init(version: 2, agentId: "agent", sessionId: source.id, type: .toolResult,
                runtimeMetadata: .init(runId: "source-run", userTurnId: "source-turn"),
                toolResult: .init(tool: "files.read", ok: true, data: .string("Observed result"), callEventId: callID))
        ]
        _ = try store.appendEvents(agentID: "agent", sessionID: source.id, events: events)
        let sourceFile = URL(fileURLWithPath: try store.sessionFilePath(agentID: "agent", sessionID: source.id))
        let original = try Data(contentsOf: sourceFile)
        do {
            _ = try store.makeHistoricalEvents([events[0], events[0]], agentID: "agent", sessionID: target.id)
            Issue.record("Duplicate history identities must be rejected")
        } catch AgentSessionFileStore.StoreError.invalidPayload { }
        let copies = try store.makeHistoricalEvents(events, agentID: "agent", sessionID: target.id)
        _ = try store.appendEvents(agentID: "agent", sessionID: target.id, events: copies)
        #expect(try Data(contentsOf: sourceFile) == original)
        #expect(copies.allSatisfy { $0.isHistorical && $0.runtimeMetadata == nil && $0.inputTransitions == nil })
        #expect(copies.last?.toolResult?.callEventId == copies.first(where: { $0.toolCall != nil })?.id)
        #expect(copies.last?.toolResult?.callEventId != callID)
        _ = try store.deleteSession(agentID: "agent", sessionID: source.id)
        let reopened = AgentSessionFileStore(agentsRootURL: root)
        let copied = try #require(try reopened.loadSession(agentID: "agent", sessionID: target.id).events
            .compactMap(\.message).flatMap(\.segments).compactMap(\.attachment).first)
        let file = try #require(try reopened.resolveAttachmentFileURL(agentID: "agent", attachment: copied))
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test(arguments: [20_000, 26 * 1_024 * 1_024])
    func largeVerifiedResultsAreArchivedWithoutDuplicatingTheCanonicalPayload(size: Int) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("artifact-storage-\(UUID())")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentSessionFileStore(agentsRootURL: root)
        let session = try store.createSession(agentID: "agent", request: .init())
        let journal = SessionLoopJournal(store: store, agentID: "agent", sessionID: session.id, authorizeWriter: {})
        let request = ModelStepRequest(runId: "run", userTurnId: "turn", stepId: "step", attemptId: "attempt",
            model: "fixture:model", projectionRevision: "", cacheScope: "scope", messages: [],
            tools: [.init(name: "exec", toolId: "runtime.exec", parameters: .object(["type": .string("object")]))])
        let call = AgentLoopCall(eventID: "call-event", sourceOrder: 0,
            call: .init(id: "call", name: "exec", rawArguments: "{}"))
        try await journal.appendResponse(.init(toolCalls: [call.call], stopReason: .toolCalls), request: request)
        try await journal.appendRequested([call], request: request)
        try await journal.appendStarted(call, request: request)
        let text = String(repeating: "x", count: size) + " complete ending"
        let result = ToolInvocationResult(tool: "runtime.exec", ok: true, data: .object(["stdout": .string(text)]))
        let evidence = VerificationEvidence(id: "verification", kind: .test, tool: "runtime.exec", command: "swift test", arguments: [],
            cwd: root.path, exitCode: 0, observedAt: Date())
        try await journal.appendOutcome(.init(result: result, verificationEvidence: [evidence]), call: call, request: request)
        let reopened = AgentSessionFileStore(agentsRootURL: root)
        let loaded = try reopened.loadSession(agentID: "agent", sessionID: session.id)
        let saved = try #require(loaded.events.last { $0.toolResult != nil })
        #expect(saved.runtimeMetadata?.toolOutputArtifact != nil)
        #expect(saved.toolResult?.data == result.data)
        #expect(saved.runtimeMetadata?.verificationEvidence?.count == 1)
        let path = URL(fileURLWithPath: try store.sessionFilePath(agentID: "agent", sessionID: session.id))
        #expect(try Data(contentsOf: path).count < 16_384)
    }
    @Test
    func chunksExportsAndCleanupPreserveRootsAndRejectCorruption() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("artifact-reader-\(UUID())")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentSessionFileStore(agentsRootURL: root)
        let session = try store.createSession(agentID: "agent", request: .init())
        let bytes = Data(repeating: 65, count: 150_003)
        let artifact = try store.persistToolOutputArtifact(agentID: "agent", sessionID: session.id, callEventID: "call", bytes: bytes)
        var assembled = Data()
        var offset = 0
        repeat {
            let chunk = try store.readToolOutputArtifactChunk(artifact, offset: offset, limit: 50_000)
            assembled.append(chunk.data)
            offset = chunk.nextOffset ?? bytes.count
        } while offset < bytes.count
        #expect(assembled == bytes)
        #expect(throws: (any Error).self) { try store.readToolOutputArtifactChunk(artifact, offset: -1) }
        #expect(throws: (any Error).self) { try store.readToolOutputArtifactChunk(artifact, offset: 0, limit: 1_048_577) }
        var foreign = artifact; foreign.sessionId = "../foreign"
        #expect(throws: (any Error).self) { try store.readToolOutputArtifactChunk(foreign, offset: 0) }
        let exported = root.appendingPathComponent("export.json")
        try store.exportToolOutputArtifact(artifact, to: exported)
        #expect(try Data(contentsOf: exported) == bytes)
        #expect(throws: (any Error).self) { try store.exportToolOutputArtifact(artifact, to: exported) }
        let file = try #require(try store.resolveAttachmentFileURL(agentID: "agent", attachment: artifact.attachment))
        try Data(repeating: 66, count: bytes.count).write(to: file)
        #expect(throws: (any Error).self) { try store.readToolOutputArtifactChunk(artifact, offset: 0) }
        #expect(throws: (any Error).self) { try store.exportToolOutputArtifact(artifact, to: root.appendingPathComponent("corrupt.json")) }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("corrupt.json").path))
        try bytes.write(to: file)
        _ = try store.appendEvents(agentID: "agent", sessionID: session.id, events: [
            .init(agentId: "agent", sessionId: session.id, type: .message,
                message: .init(role: .assistant, segments: [.init(kind: .attachment, attachment: artifact.attachment)]))
        ])
        let orphan = try store.persistToolOutputArtifact(agentID: "agent", sessionID: session.id, callEventID: "orphan", bytes: bytes)
        let orphanFile = try #require(try store.resolveAttachmentFileURL(agentID: "agent", attachment: orphan.attachment))
        for url in [file, orphanFile] { try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-10_800)], ofItemAtPath: url.path) }
        #expect(try store.cleanupToolOutputArtifacts(agentID: "agent", sessionID: session.id, olderThan: Date().addingTimeInterval(-7_200)) == 1)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(!FileManager.default.fileExists(atPath: orphanFile.path))
    }

    @Test
    func streamingSHA256MatchesIndependentVectorsAndChunkBoundaries() {
        #expect(ContentDigest.sha256(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        var digest = ContentDigest.SHA256()
        for byte in "abc".utf8 { digest.update(Data([byte])) }
        #expect(digest.finalize() == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let bytes = Data(repeating: 97, count: 1_000_000)
        var million = ContentDigest.SHA256()
        for offset in stride(from: 0, to: bytes.count, by: 73) { million.update(bytes[offset..<min(bytes.count, offset + 73)]) }
        #expect(million.finalize() == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }

    @Test
    func embeddedArtifactsPublishTranscriptReferencesAndStreamWithoutACoreServer() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("embedded-artifacts-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let host = SloppyRuntimeHost(nativeEngine: .unified)
        let (store, sessionID) = try await host.prepareSession(channelID: "fixture", workspaceURL: root,
            persistedSessionID: "session-" + UUID().uuidString.lowercased())
        let journal = SessionLoopJournal(store: store, agentID: "mobile", sessionID: sessionID, authorizeWriter: {})
        let request = ModelStepRequest(runId: "run", userTurnId: "turn", stepId: "step", attemptId: "attempt",
            model: "fixture", projectionRevision: "", cacheScope: "scope", messages: [],
            tools: [.init(name: "read", toolId: "files.read", parameters: .object(["type": .string("object")]))])
        let call = AgentLoopCall(eventID: "call-event", sourceOrder: 0, call: .init(id: "call", name: "read", rawArguments: "{}"))
        try await journal.appendRequested([call], request: request)
        try await journal.appendStarted(call, request: request)
        let result = ToolInvocationResult(tool: "files.read", ok: true, data: .string(String(repeating: "full output ", count: 20_000)))
        try await journal.appendOutcome(.init(result: result), call: call, request: request)
        let artifacts = try await host.toolOutputArtifacts(workspaceURL: root, persistedSessionID: sessionID)
        let artifact = try #require(artifacts.first)
        let messages = try await host.messages(workspaceURL: root, persistedSessionID: sessionID)
        #expect(messages.flatMap(\.artifacts) == [artifact])
        let preview = try await host.readToolOutput(workspaceURL: root, persistedSessionID: sessionID,
            artifactID: artifact.attachment.id, limit: 100)
        #expect(preview.data.count == 100)
        let stream = try await host.streamToolOutput(workspaceURL: root, persistedSessionID: sessionID, artifactID: artifact.attachment.id)
        var bytes = Data()
        for try await chunk in stream { #expect(chunk.count <= 65_536); bytes.append(chunk) }
        #expect(try JSONDecoder().decode(ToolInvocationResult.self, from: bytes).data == result.data)
        await #expect(throws: (any Error).self) {
            try await host.readToolOutput(workspaceURL: root, persistedSessionID: sessionID, artifactID: "foreign")
        }
        let cancelledStream = try await host.streamToolOutput(workspaceURL: root, persistedSessionID: sessionID, artifactID: artifact.attachment.id)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            var iterator = cancelledStream.makeAsyncIterator()
            return try await iterator.next()
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
    }

}

