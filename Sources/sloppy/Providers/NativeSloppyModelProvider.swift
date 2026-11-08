import AnyLanguageModel
import PluginSDK
import Protocols

/// Legacy models keep their existing witnesses; the companion capability is prepared separately.
struct NativeSloppyModelProvider: ModelProvider, ModelStepProviderFactory {
    let base: any ModelProvider
    let prepareStep: @Sendable (String) async throws -> any ModelStepProvider
    var id: String { base.id }
    var supportedModels: [String] { base.supportedModels }
    var systemInstructions: String? { base.systemInstructions }
    var tools: [any Tool] { base.tools }
    func supports(modelName: String) -> Bool { base.supports(modelName: modelName) }
    func contextLimits(for modelName: String) -> ModelContextLimits? { base.contextLimits(for: modelName) }
    func generationOptions(for modelName: String, maxTokens: Int, reasoningEffort: ReasoningEffort?) -> GenerationOptions {
        base.generationOptions(for: modelName, maxTokens: maxTokens, reasoningEffort: reasoningEffort)
    }
    func createLanguageModel(for modelName: String) async throws -> any LanguageModel { try await base.createLanguageModel(for: modelName) }
    func createLanguageModel(for modelName: String, usageContext: ModelUsageContext) async throws -> any LanguageModel {
        try await base.createLanguageModel(for: modelName, usageContext: usageContext)
    }
    func reasoningCapture(for modelName: String) -> ReasoningContentCapture? { base.reasoningCapture(for: modelName) }
    func tokenUsageCapture(for modelName: String) -> TokenUsageCapture? { base.tokenUsageCapture(for: modelName) }
    func supportsModelSteps(for modelName: String) -> Bool { supports(modelName: modelName) }
    func createModelStepProvider(for modelName: String, usageContext: ModelUsageContext?) async throws -> (any ModelStepProvider)? {
        guard supportsModelSteps(for: modelName) else { return nil }
        return try await prepareStep(modelName)
    }
}
