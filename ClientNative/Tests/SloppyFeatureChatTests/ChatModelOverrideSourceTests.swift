import Foundation
import Testing

@Suite("Chat model override source")
struct ChatModelOverrideSourceTests {
    private func source(_ path: String...) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = path.reduce(packageRoot) { $0.appendingPathComponent($1) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("session message payload includes dashboard-compatible model and reasoning override fields")
    func sessionMessagePayloadIncludesDashboardCompatibleOverrideFields() throws {
        let source = try source("Sources", "SloppyClientCore", "BackendServices.swift")

        #expect(source.contains("selectedModel: String? = nil"))
        #expect(source.contains("reasoningEffort: String? = nil"))
        #expect(source.contains("var selectedModel: String?"))
        #expect(source.contains("var reasoningEffort: String?"))
        #expect(source.contains("selectedModel: normalizedSelectedModel"))
        #expect(source.contains("reasoningEffort: normalizedReasoningEffort"))
    }

    @Test("chat view model loads model options and forwards selected overrides when sending")
    func chatViewModelLoadsModelOptionsAndForwardsSelectedOverridesWhenSending() throws {
        let source = try source("Sources", "SloppyFeatureChat", "Screens", "Chat", "ChatScreenViewModel.swift")

        #expect(source.contains("public private(set) var availableModels: [ChatModelOption] = []"))
        #expect(source.contains("public private(set) var selectedModelId: String = \"\""))
        #expect(source.contains("public private(set) var selectedReasoningEffort: ChatReasoningEffort = .default"))
        #expect(source.contains("apiClient.fetchAvailableModels()"))
        #expect(source.contains("public func pickModel(_ model: ChatModelOption)"))
        #expect(source.contains("public func pickReasoningEffort(_ effort: ChatReasoningEffort)"))
        #expect(source.contains("selectedModel: selectedModelId"))
        #expect(source.contains("selectedModelSupportsReasoningEffort ? selectedReasoningEffort.payloadValue : nil"))
        #expect(source.contains("private var selectedModelSupportsReasoningEffort: Bool"))
    }
}
