import Foundation
import AnyLanguageModel
import Testing
@testable import PluginSDK
@testable import AgentRuntime
@testable import Protocols
@testable import sloppy

private struct LiveImportOAuthProvider: ModelProvider {
    let id = "live-import-oauth"
    let supportedModels: [String]
    let auth: OpenAIOAuthService

    func createLanguageModel(for modelName: String) async throws -> any LanguageModel {
        let token = try #require(auth.currentAccessToken(), "A configured OAuth session is required")
        return LiveImportRecordingModel(model: OpenAIOAuthModel(bearerToken: token, model: modelName, accountId: auth.currentAccountId()))
    }
}

private struct LiveImportRecordingModel: LanguageModel {
    typealias UnavailableReason = Never
    let model: OpenAIOAuthModel

    func respond<Content: Generable>(within session: LanguageModelSession, to prompt: Prompt, generating type: Content.Type,
        includeSchemaInPrompt: Bool, options: GenerationOptions) async throws -> LanguageModelSession.Response<Content> {
        let response = try await model.respond(within: session, to: prompt, generating: type, includeSchemaInPrompt: includeSchemaInPrompt, options: options)
        // This opt-in fixture contains only the synthetic sentence above.
        print("Synthetic import response:", response.content as? String ?? "non-text")
        return response
    }

    func streamResponse<Content: Generable>(within session: LanguageModelSession, to prompt: Prompt, generating type: Content.Type,
        includeSchemaInPrompt: Bool, options: GenerationOptions) -> sending LanguageModelSession.ResponseStream<Content> {
        .init(stream: AsyncThrowingStream { $0.finish(throwing: CancellationError()) })
    }
}

// Opt-in integration check: sends synthetic source text through the configured
// OAuth adapter. It neither imports user documents nor writes production memory.
@Test(.enabled(if: ProcessInfo.processInfo.environment["SLOPPY_LIVE_IMPORT_OAUTH_WORKSPACE"] != nil))
func memoryImportLiveOAuthExtractsAndReviewsSyntheticSource() async throws {
    let environment = ProcessInfo.processInfo.environment
    let workspace = try #require(environment["SLOPPY_LIVE_IMPORT_OAUTH_WORKSPACE"])
    let model = try #require(environment["SLOPPY_LIVE_IMPORT_OAUTH_MODEL"])
    let provider = LiveImportOAuthProvider(
        supportedModels: [model],
        auth: OpenAIOAuthService(workspaceRootURL: URL(fileURLWithPath: workspace))
    )
    let processor = MemoryImportModelProcessor(provider: provider, model: model)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = InMemoryMemoryStore()
    let service = MemoryImportService(root: root, memoryStore: store)
    let text = "The synthetic ExampleProject requires Swift 6.2 to build."
    let job = try await service.create(agentID: "synthetic", sessionID: "test", files: [
        .init(name: "synthetic.md", mimeType: "text/markdown", sizeBytes: text.utf8.count, contentBase64: Data(text.utf8).base64EncodedString())
    ])
    _ = try await service.launch(agentID: "synthetic", id: job.id, processor: processor, observer: { _ in })
    await service.waitForIdle(id: job.id)
    let finished = try await service.get(agentID: "synthetic", id: job.id)
    #expect(finished.status == .completed, "Live import failure: \(finished.error ?? "none")")
    #expect(finished.completedUnits == finished.totalUnits)
    #expect(finished.savedCount > 0)
}
