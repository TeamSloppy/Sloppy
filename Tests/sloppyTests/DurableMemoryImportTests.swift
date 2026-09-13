import Foundation
import SloppyNodeCore
import Testing
@testable import AgentRuntime
@testable import Protocols
@testable import sloppy

private actor ImportFixtureProcessor: MemoryImportProcessing {
    var partialResponses: Int
    var rejectReviews: Bool
    var seen: [MemoryImportWorkUnit] = []
    var extractCalls = 0
    var reviewCalls = 0
    let duplicateID: String?

    init(partialResponses: Int = 0, rejectReviews: Bool = false, duplicateID: String? = nil) {
        self.partialResponses = partialResponses; self.rejectReviews = rejectReviews
        self.duplicateID = duplicateID
    }

    func extract(units: [MemoryImportWorkUnit], existing: [MemoryEntry], feedback: String) async throws -> MemoryImportExtraction {
        extractCalls += 1
        for unit in units where !seen.contains(where: { $0.id == unit.id }) { seen.append(unit) }
        var decisions = units.map { unit in
            MemoryImportDecision(unitID: unit.id, disposition: "retained", reason: "Technical knowledge",
                entries: [.init(note: duplicateID.flatMap { id in existing.first { $0.id == id }?.note } ?? "Fact for \(unit.id)", summary: "Technical fact", kind: "fact", evidenceQuote: String(unit.text.prefix(80)), duplicateID: duplicateID ?? "")])
        }
        if partialResponses > 0 { partialResponses -= 1; decisions.removeLast() }
        return .init(decisions: decisions)
    }

    func review(units: [MemoryImportWorkUnit], existing: [MemoryEntry], extraction: MemoryImportExtraction) async throws -> MemoryImportReview {
        reviewCalls += 1
        return .init(reviewedUnitIDs: units.map(\.id), accepted: !rejectReviews, feedback: rejectReviews ? "Missing technical details" : "Complete")
    }
}

/// Simulates a crash/failed acknowledgement after a write reached canonical storage.
private actor LostConfirmationMemoryStore: MemoryStore {
    let base = InMemoryMemoryStore()
    var hideNextRead = false
    func save(entry: MemoryWriteRequest) async -> MemoryRef {
        let ref = await base.save(entry: entry)
        hideNextRead = true
        return ref
    }
    func recall(request: MemoryRecallRequest) async -> [MemoryHit] { await base.recall(request: request) }
    func link(_ edge: MemoryEdgeWriteRequest) async -> Bool { await base.link(edge) }
    func entries(filter: MemoryEntryFilter) async -> [MemoryEntry] {
        if hideNextRead { hideNextRead = false; return [] }
        return await base.entries(filter: filter)
    }
}

private actor UnavailableRecallMemoryStore: MemoryStore {
    let base = InMemoryMemoryStore()
    func save(entry: MemoryWriteRequest) async -> MemoryRef { await base.save(entry: entry) }
    func recall(request: MemoryRecallRequest) async -> [MemoryHit] { [] }
    func entries(filter: MemoryEntryFilter) async -> [MemoryEntry] { await base.entries(filter: filter) }
    func link(_ edge: MemoryEdgeWriteRequest) async -> Bool { await base.link(edge) }
}

private actor PausedImportProcessor: MemoryImportProcessing {
    var started = false
    var ready: [CheckedContinuation<Void, Never>] = []
    var release: CheckedContinuation<Void, Never>?
    var reviewCalls = 0
    var released = false
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { ready.append($0) }
    }
    func unblock() { released = true; release?.resume(); release = nil }
    func extract(units: [MemoryImportWorkUnit], existing: [MemoryEntry], feedback: String) async throws -> MemoryImportExtraction {
        started = true
        if released { return .init(decisions: []) }
        await withCheckedContinuation { continuation in
            release = continuation
            ready.forEach { $0.resume() }; ready.removeAll()
        }
        return .init(decisions: [])
    }
    func review(units: [MemoryImportWorkUnit], existing: [MemoryEntry], extraction: MemoryImportExtraction) async throws -> MemoryImportReview {
        reviewCalls += 1
        return .init(reviewedUnitIDs: units.map(\.id), accepted: true, feedback: "")
    }
}

@Suite
struct DurableMemoryImportTests {
    @Test
    func toolResultKeepsCompletionAndJobIDVisibleWithoutDumpingAllParts() throws {
        let parts = (0..<1000).map { MemoryImportPart(id: "part-\($0)", sourceId: "source", startUTF8: $0, endUTF8: $0 + 1, completed: false, disposition: nil, reason: nil, memoryIds: []) }
        let job = MemoryImportJob(id: "job", agentId: "helper", sessionId: "session", status: .running,
            sources: [], totalUnits: 1000, completedUnits: 6, savedCount: 6, duplicateCount: 0, ignoredCount: 0,
            error: nil, createdAt: Date(), updatedAt: Date(), parts: parts)
        let data = MemoryImportTool.resultData(job)
        #expect(data.asObject?["job_id"]?.asString == "job")
        #expect(data.asObject?["status"]?.asString == "running")
        #expect(data.asObject?["parts"] == nil)
        #expect(try JSONEncoder().encode(data).count < 2000)
    }

    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("durable-import-\(UUID())", isDirectory: true) }
    private func upload(_ text: String, name: String = "export.md") -> AgentAttachmentUpload {
        let data = Data(text.utf8)
        return .init(name: name, mimeType: "text/markdown", sizeBytes: data.count, contentBase64: data.base64EncodedString())
    }

    @Test
    func allPartsAreVerifiedAndSourcesSurviveOriginalAndSessionDeletion() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = root.appendingPathComponent("session")
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        let original = session.appendingPathComponent("export.md")
        let text = String(repeating: "Техническая деталь Swift 🧠 и ограничения сборки.\n", count: 260)
        try Data(text.utf8).write(to: original)
        let store = InMemoryMemoryStore()
        let service = MemoryImportService(root: root.appendingPathComponent("archive"), memoryStore: store)
        let job = try await service.create(agentID: "helper", sessionID: "chat", files: [upload(text)])
        #expect(job.totalUnits > 4)
        try FileManager.default.removeItem(at: session)
        let processor = ImportFixtureProcessor(partialResponses: 1)
        _ = try await service.launch(agentID: "helper", id: job.id, processor: processor, observer: { _ in })
        await service.waitForIdle(id: job.id)
        let completed = try await service.get(agentID: "helper", id: job.id)
        #expect(completed.status == .completed)
        #expect(completed.completedUnits == completed.totalUnits)
        #expect(completed.savedCount == completed.totalUnits)
        #expect(await processor.extractCalls > processor.reviewCalls)
        #expect(await processor.seen.map(\.text).joined() == text)
        let records = await store.entries(filter: .init(scope: .agent("helper")))
        #expect(records.count == completed.totalUnits)
        #expect(records.allSatisfy { !$0.note.contains("export.md") && !$0.note.contains(session.path) })
        #expect(records.allSatisfy { $0.source?.id?.hasPrefix("v1/helper/\(job.id)/") == true && $0.metadata["source_sha256"] != nil })
        let reopened = MemoryImportService(root: root.appendingPathComponent("archive"), memoryStore: store)
        let sourceID = try #require(completed.sources.first?.id)
        let source = try await reopened.source(agentID: "helper", id: job.id, sourceID: sourceID)
        #expect(source.content == text)
        #expect(source.sha256 == TaskSyncCrypto.sha256Hex(Data(text.utf8)))
    }

    @Test
    func missingCoverageAndRejectedReviewCannotCompleteAJob() async throws {
        for processor in [ImportFixtureProcessor(partialResponses: 100), ImportFixtureProcessor(rejectReviews: true)] {
            let root = root()
            defer { try? FileManager.default.removeItem(at: root) }
            let store = InMemoryMemoryStore()
            let service = MemoryImportService(root: root, memoryStore: store)
            let job = try await service.create(agentID: "helper", sessionID: "chat", files: [upload("# Important\nKeep all technical details.")])
            _ = try await service.launch(agentID: "helper", id: job.id, processor: processor, observer: { _ in })
            await service.waitForIdle(id: job.id)
            let failed = try await service.get(agentID: "helper", id: job.id)
            #expect(failed.status == .failed)
            #expect(failed.completedUnits == 0)
            #expect(await store.entries(filter: .default).isEmpty)
            #expect(await processor.extractCalls == 3)
            _ = try await service.launch(agentID: "helper", id: job.id, processor: ImportFixtureProcessor(), observer: { _ in })
            await service.waitForIdle(id: job.id)
            #expect(try await service.get(agentID: "helper", id: job.id).status == .completed)
        }
    }

    @Test
    func restartReusesPreparedDecisionsAndDoesNotRepeatAcknowledgedOrLostWrites() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let faulty = LostConfirmationMemoryStore()
        let service = MemoryImportService(root: root, memoryStore: faulty)
        let job = try await service.create(agentID: "helper", sessionID: "chat", files: [upload(String(repeating: "Detail\n", count: 1300))])
        let initial = ImportFixtureProcessor()
        _ = try await service.launch(agentID: "helper", id: job.id, processor: initial, observer: { _ in })
        await service.waitForIdle(id: job.id)
        #expect(try await service.get(agentID: "helper", id: job.id).status == .failed)
        #expect(await faulty.base.entries(filter: .default).count == 1)
        let preparedIDs = Set(await initial.seen.map(\.id))
        let reopened = MemoryImportService(root: root, memoryStore: faulty.base)
        let resumed = ImportFixtureProcessor()
        _ = try await reopened.launch(agentID: "helper", id: job.id, processor: resumed, observer: { _ in })
        await reopened.waitForIdle(id: job.id)
        let completed = try await reopened.get(agentID: "helper", id: job.id)
        #expect(completed.status == .completed)
        #expect(await faulty.base.entries(filter: .default).count == completed.totalUnits)
        #expect(Set(await resumed.seen.map(\.id)).isDisjoint(with: preparedIDs))
        // Repeating a completed launch does not execute another extraction or write.
        let before = await resumed.extractCalls
        _ = try await reopened.launch(agentID: "helper", id: job.id, processor: resumed, observer: { _ in })
        #expect(await resumed.extractCalls == before)
    }

    @Test
    func sourceIntegrityAndRequestIdempotenceAreEnforced() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = MemoryImportService(root: root, memoryStore: InMemoryMemoryStore())
        let filename = String(repeating: "п", count: 160) + ".md"
        let files = [upload("# Known source", name: filename)]
        let first = try await service.create(agentID: "helper", sessionID: "chat", files: files)
        let second = try await service.create(agentID: "helper", sessionID: "chat", files: files)
        #expect(first.id == second.id)
        #expect(first.sources.first?.name == filename)
        let sourceID = try #require(first.sources.first?.id)
        let snapshot = root.appendingPathComponent("helper/\(first.id)/sources/\(sourceID).md")
        try Data("tampered".utf8).write(to: snapshot)
        await #expect(throws: MemoryImportError.self) { try await service.source(agentID: "helper", id: first.id, sourceID: sourceID) }
        await #expect(throws: MemoryImportError.self) { try await service.get(agentID: "another", id: first.id) }
        #expect(TaskSyncCrypto.sha256Hex(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test
    func savedButUnretrievableMemoryIsNotReportedAsComplete() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = UnavailableRecallMemoryStore()
        let service = MemoryImportService(root: root, memoryStore: store)
        let job = try await service.create(agentID: "helper", sessionID: "chat", files: [upload("A durable technical fact.")])
        _ = try await service.launch(agentID: "helper", id: job.id, processor: ImportFixtureProcessor(), observer: { _ in })
        await service.waitForIdle(id: job.id)
        let failed = try await service.get(agentID: "helper", id: job.id)
        #expect(failed.status == .failed)
        #expect(failed.savedCount == 1)
        #expect(failed.completedUnits == 0)
        let recovered = MemoryImportService(root: root, memoryStore: store.base)
        let processor = ImportFixtureProcessor()
        _ = try await recovered.launch(agentID: "helper", id: job.id, processor: processor, observer: { _ in })
        await recovered.waitForIdle(id: job.id)
        #expect(try await recovered.get(agentID: "helper", id: job.id).status == .completed)
        #expect(await processor.extractCalls == 0)
        #expect(await store.base.entries(filter: .default).count == 1)
    }

    @Test
    func archivedSourceAPIRemainsReadableAfterChatDeletionAndChecksOwnership() async throws {
        let config = CoreConfig.test
        let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder(),
            nodeConfigStore: NodeConfigStore(configURL: root().appendingPathComponent("node.json")), sharedSkillsRootURLs: [])
        _ = try await service.createAgent(.init(id: "archive-owner", displayName: "Archive owner", role: "Test"))
        _ = try await service.createAgent(.init(id: "other-owner", displayName: "Other", role: "Test"))
        let session = try await service.createAgentSession(agentID: "archive-owner", request: .init(title: "Memory import"))
        let files = [upload("# Original evidence\nStable fact.")]
        let sessionStore = await service.sessionStore
        _ = try sessionStore.persistAttachments(agentID: "archive-owner", sessionID: session.id, uploads: files)
        let archive = await service.memoryImports
        let legacy = await service.memoryStore.save(entry: .init(note: "# Original evidence\nStable fact.", kind: .fact,
            scope: .agent("archive-owner"), source: .init(type: "memory_import", id: session.id)))
        let job = try await archive.create(agentID: "archive-owner", sessionID: session.id, files: files)
        _ = try await archive.launch(agentID: "archive-owner", id: job.id, processor: ImportFixtureProcessor(duplicateID: legacy.id), observer: { _ in })
        await archive.waitForIdle(id: job.id)
        let records = await service.memoryStore.entries(filter: .init(scope: .agent("archive-owner")))
        let memoryID = try #require(records.first?.id)
        #expect(records.count == 1)
        #expect(try await archive.get(agentID: "archive-owner", id: job.id).duplicateCount == 1)
        #expect(try await archive.sourceLocations(agentID: "archive-owner", memoryID: memoryID).count == 1)
        try await service.deleteAgentSession(agentID: "archive-owner", sessionID: session.id)
        let sourceID = try #require(job.sources.first?.id)
        let router = CoreRouter(service: service)
        let response = await router.handle(method: "GET", path: "/v1/agents/archive-owner/memory-imports/\(job.id)/sources/\(sourceID)", body: nil)
        #expect(response.status == 200)
        let source = try JSONDecoder().decode(MemoryImportSourceContent.self, from: response.body)
        #expect(source.content == "# Original evidence\nStable fact.")
        let wrongOwner = await router.handle(method: "GET", path: "/v1/agents/other-owner/memory-imports/\(job.id)/sources/\(sourceID)", body: nil)
        #expect(wrongOwner.status == 404)
        let later = try await service.createAgentSession(agentID: "archive-owner", request: .init(title: "Later conversation"))
        let evidence = await service.invokeToolFromRuntime(agentID: "archive-owner", sessionID: later.id,
            request: .init(tool: "memory.source", arguments: ["memory_id": .string(memoryID)]))
        #expect(evidence.ok)
        #expect(evidence.data?.asObject?["content"]?.asString == source.content)
    }

    @Test
    func cancellingStopsNewWorkAndResumingUsesTheSameArchive() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = InMemoryMemoryStore()
        let service = MemoryImportService(root: root, memoryStore: store)
        let job = try await service.create(agentID: "helper", sessionID: "chat", files: [upload("A fact to import.")])
        let blocked = PausedImportProcessor()
        _ = try await service.launch(agentID: "helper", id: job.id, processor: blocked, observer: { _ in })
        await blocked.waitUntilStarted()
        let sameJob = try await service.launch(agentID: "helper", id: job.id.uppercased(), processor: ImportFixtureProcessor(), observer: { _ in })
        #expect(sameJob.status == .running)
        #expect(try await service.cancel(agentID: "helper", id: job.id.uppercased()).status == .cancelling)
        await blocked.unblock()
        await service.waitForIdle(id: job.id)
        #expect(await blocked.reviewCalls == 0)
        #expect(try await service.get(agentID: "helper", id: job.id).status == .cancelled)
        #expect(await store.entries(filter: .default).isEmpty)
        _ = try await service.launch(agentID: "helper", id: job.id, processor: ImportFixtureProcessor(), observer: { _ in })
        await service.waitForIdle(id: job.id)
        #expect(try await service.get(agentID: "helper", id: job.id).status == .completed)
    }

    @Test
    func persistenceFailureDoesNotLeaveAPhantomRunningJob() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = MemoryImportService(root: root, memoryStore: InMemoryMemoryStore())
        let job = try await service.create(agentID: "helper", sessionID: "chat", files: [upload("A source fact.")])
        let manifest = root.appendingPathComponent("helper/\(job.id)/job.json")
        _ = try await service.launch(agentID: "helper", id: job.id, processor: ImportFixtureProcessor(), observer: { progress in
            if progress.status == .running {
                try? FileManager.default.removeItem(at: manifest)
                try? FileManager.default.createDirectory(at: manifest, withIntermediateDirectories: true)
            }
        })
        await service.waitForIdle(id: job.id)
        let failed = try await service.get(agentID: "helper", id: job.id)
        #expect(failed.status == .failed)
        #expect(failed.error?.contains("persist import progress") == true)
        #expect(try await service.list(agentID: "helper").first?.status == .failed)
    }

    @Test
    func restartRecoveryDiscoversQueuedJobsButDoesNotRestartCancelledJobs() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = InMemoryMemoryStore()
        let original = MemoryImportService(root: root, memoryStore: store)
        let queued = try await original.create(agentID: "helper", sessionID: "first", files: [upload("Queued fact.")])
        let cancelled = try await original.create(agentID: "helper", sessionID: "second", files: [upload("Cancelled fact.")])
        _ = try await original.cancel(agentID: "helper", id: cancelled.id)
        let reopened = MemoryImportService(root: root, memoryStore: store)
        #expect(try await reopened.pending().map(\.id) == [queued.id])
        _ = try await reopened.launch(agentID: "helper", id: queued.id, processor: ImportFixtureProcessor(), observer: { _ in })
        await reopened.waitForIdle(id: queued.id)
        #expect(try await reopened.get(agentID: "helper", id: queued.id).status == .completed)
        #expect(try await reopened.pending().isEmpty)
        #expect(try await reopened.get(agentID: "helper", id: cancelled.id).status == .cancelled)
    }
}
