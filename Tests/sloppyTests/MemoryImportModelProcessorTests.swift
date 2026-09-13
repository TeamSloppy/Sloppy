import Foundation
import AnyLanguageModel
import Testing
@testable import AgentRuntime
@testable import PluginSDK
@testable import Protocols
@testable import sloppy

@Generable
private struct OAuthExtractionFixture {
    var decisions: [String]
}

@Generable
private struct OAuthReviewFixture {
    var reviewedUnitIDs: [String]
    var accepted: Bool
    var feedback: String
}

private actor ImportModelReplies {
    var replies: [String]
    var calls = 0

    init(_ replies: [String]) { self.replies = replies }

    func next() -> String {
        calls += 1
        return replies.count > 1 ? replies.removeFirst() : replies[0]
    }
}

private struct TextOnlyImportProvider: ModelProvider {
    let id = "text-only"
    let supportedModels = ["text-only:test"]
    let replies: ImportModelReplies

    func createLanguageModel(for modelName: String) async throws -> any LanguageModel {
        TextOnlyImportModel(replies: replies)
    }
}

private struct TextOnlyImportModel: LanguageModel {
    typealias UnavailableReason = Never
    let replies: ImportModelReplies

    func respond<Content: Generable>(
        within session: LanguageModelSession, to prompt: Prompt, generating type: Content.Type,
        includeSchemaInPrompt: Bool, options: GenerationOptions
    ) async throws -> LanguageModelSession.Response<Content> {
        #expect(type == String.self, "Import must work with text-only providers, including OpenAI OAuth")
        #expect(session.tools.isEmpty)
        let instructions = session.instructions?.description ?? ""
        #expect(instructions.contains("JSON object"))
        #expect(instructions.contains("properties"))
        let raw = GeneratedContent(await replies.next())
        return .init(content: try type.init(raw), rawContent: raw, transcriptEntries: [])
    }

    func streamResponse<Content: Generable>(
        within session: LanguageModelSession, to prompt: Prompt, generating type: Content.Type,
        includeSchemaInPrompt: Bool, options: GenerationOptions
    ) -> sending LanguageModelSession.ResponseStream<Content> {
        .init(stream: AsyncThrowingStream { $0.finish(throwing: CancellationError()) })
    }
}

@Suite
struct MemoryImportModelProcessorTests {
    @Test
    func modelJSONDoesNotRequireMacroPrivateState() throws {
        // Literal external JSON, deliberately not produced by JSONEncoder on
        // the same DTO (which previously hid @Generable's extra stored field).
        let json = #"{"decisions":[{"unitID":"unit","disposition":"retained","reason":"","entries":[{"note":"Swift 6.2","summary":"Version","kind":"fact","evidenceQuote":"Swift 6.2","duplicateID":""}]}]}"#
        let extraction = try JSONDecoder().decode(MemoryImportExtraction.self, from: Data(json.utf8))
        #expect(extraction.decisions.first?.entries.first?.note == "Swift 6.2")
        let encoded = String(decoding: try JSONEncoder().encode(extraction), as: UTF8.self)
        #expect(!encoded.contains("_rawGeneratedContent"))
        let review = try JSONDecoder().decode(MemoryImportReview.self, from: Data(#"{"reviewedUnitIDs":["unit"],"accepted":true,"feedback":"ok"}"#.utf8))
        #expect(review.accepted)
    }

    @Test(arguments: [false, true])
    func actualProcessorCompletesWithTextOnlyProvider(retryMalformed: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = InMemoryMemoryStore()
        let service = MemoryImportService(root: root, memoryStore: store)
        let text = "The project uses Swift 6.2."
        let job = try await service.create(agentID: "helper", sessionID: "test", files: [
            .init(name: "memory.md", mimeType: "text/markdown", sizeBytes: text.utf8.count, contentBase64: Data(text.utf8).base64EncodedString())
        ])
        let unitID = try #require(job.parts.first?.id)
        let extraction = MemoryImportExtraction(decisions: [.init(unitID: unitID, disposition: "retained", reason: "Technical constraint", entries: [
            .init(note: text, summary: "Swift version", kind: "fact", evidenceQuote: text, duplicateID: "")
        ])])
        let review = MemoryImportReview(reviewedUnitIDs: [unitID], accepted: true, feedback: "Complete")
        let replies = ImportModelReplies((retryMalformed ? ["Invalid JSON"] : []) + [
            String(decoding: try JSONEncoder().encode(extraction), as: UTF8.self),
            String(decoding: try JSONEncoder().encode(review), as: UTF8.self)
        ])
        let processor = MemoryImportModelProcessor(provider: TextOnlyImportProvider(replies: replies), model: "text-only:test")
        _ = try await service.launch(agentID: "helper", id: job.id, processor: processor, observer: { _ in })
        await service.waitForIdle(id: job.id)
        let finished = try await service.get(agentID: "helper", id: job.id)
        #expect(finished.status == .completed)
        #expect(finished.savedCount == 1)
        #expect(finished.completedUnits == finished.totalUnits)
        #expect(await replies.calls == (retryMalformed ? 3 : 2))
        #expect(await store.entries(filter: .init(scope: .agent("helper"))).first?.note == text)
    }

    @Test
    func invalidProviderOutputFailsJobWithoutRestartLoop() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = InMemoryMemoryStore()
        let service = MemoryImportService(root: root, memoryStore: store)
        let job = try await service.create(agentID: "helper", sessionID: "test", files: [
            .init(name: "memory.md", mimeType: "text/markdown", sizeBytes: 10, contentBase64: Data("Swift fact".utf8).base64EncodedString())
        ])
        let replies = ImportModelReplies(["Not JSON"])
        let processor = MemoryImportModelProcessor(provider: TextOnlyImportProvider(replies: replies), model: "text-only:test")
        _ = try await service.launch(agentID: "helper", id: job.id, processor: processor, observer: { _ in })
        await service.waitForIdle(id: job.id)
        let failed = try await service.get(agentID: "helper", id: job.id)
        #expect(failed.status == .failed)
        #expect(failed.savedCount == 0)
        #expect(await replies.calls == 3)
        let reopened = MemoryImportService(root: root, memoryStore: store)
        #expect(try await reopened.pending().isEmpty)
    }

    @Test
    func oauthStructuredResponseDecodesOrThrowsInsteadOfAborting() throws {
        let model = OpenAIOAuthModel(bearerToken: "test", model: "test")
        let extraction = try model.decodeResponseText(#"{"decisions":[]}"#, generating: OAuthExtractionFixture.self)
        #expect(extraction.content.decisions.isEmpty)
        let review = try model.decodeResponseText(#"{"reviewedUnitIDs":["unit"],"accepted":true,"feedback":"ok"}"#, generating: OAuthReviewFixture.self)
        #expect(review.content.accepted)
        #expect(review.content.reviewedUnitIDs == ["unit"])
        #expect(throws: (any Error).self) {
            try model.decodeResponseText("I will inspect the files", generating: OAuthExtractionFixture.self)
        }
        #expect(throws: (any Error).self) {
            try model.decodeResponseText(#"{"decisions":"wrong type"}"#, generating: OAuthExtractionFixture.self)
        }
        let plain = try model.decodeResponseText("Plain text", generating: String.self)
        #expect(plain.content == "Plain text")
    }
}
