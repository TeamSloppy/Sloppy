import AnyLanguageModel
import Foundation
import Protocols
import Testing
@testable import PluginSDK

@Suite("Nested model provider routing")
struct NestedCompositeModelProviderTests {
    @Test("Dynamic OAuth model IDs pass through a grouped OpenAI provider")
    func dynamicOAuthModel() async throws {
        let model = "openai-oauth:dynamic-model"
        let oauth = OpenAIModelProvider(
            id: "openai-oauth", supportedModels: ["openai-oauth:configured-model"],
            settings: .init(apiKey: { "test-token" }, modelIdentifierPrefix: "openai-oauth:")
        )
        let limited = ContextLimitedModelProvider(wrapping: oauth, limits: [model: .init(contextWindowTokens: 64_000)])
        let api = OpenAIModelProvider(supportedModels: ["openai-api:configured-model"], settings: .init(apiKey: { "test-token" }))
        let grouped = CompositeModelProvider(id: "openai", providers: [api, limited])
        let outer = CompositeModelProvider(providers: [grouped])
        #expect(outer.supports(modelName: model))
        #expect(outer.contextLimits(for: model)?.contextWindowTokens == 64_000)
        _ = try await outer.createLanguageModel(for: model)
        #expect(!outer.supports(modelName: "unconfigured:unknown"))
    }
}
