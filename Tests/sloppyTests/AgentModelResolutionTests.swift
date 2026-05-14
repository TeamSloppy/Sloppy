import Foundation
import Testing
import Protocols
@testable import sloppy

@Test
func resolveCanonicalAgentModelIDAcceptsPrefixedAndOpenRouterSlug() {
    let available = [
        ProviderModelOption(
            id: "openrouter:google/gemma-4-2-26b-a4b-it:free",
            title: "Gemma",
            capabilities: ["tools"]
        )
    ]
    #expect(
        CoreService.resolveCanonicalAgentModelID(
            "openrouter:google/gemma-4-2-26b-a4b-it:free",
            availableModels: available
        ) == "openrouter:google/gemma-4-2-26b-a4b-it:free"
    )
    #expect(
        CoreService.resolveCanonicalAgentModelID(
            "google/gemma-4-2-26b-a4b-it:free",
            availableModels: available
        ) == "openrouter:google/gemma-4-2-26b-a4b-it:free"
    )
}

@Test
func resolveCanonicalAgentModelIDRejectsAmbiguousSuffix() {
    let available = [
        ProviderModelOption(id: "openrouter:acme/foo", title: "A", capabilities: []),
        ProviderModelOption(id: "openai:acme/foo", title: "B", capabilities: [])
    ]
    #expect(CoreService.resolveCanonicalAgentModelID("acme/foo", availableModels: available) == nil)
}

@Test
func readingAgentConfigPreservesTemporarilyUnavailableSelectedModel() async throws {
    let agentsRootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-model-preserve-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("agents", isDirectory: true)
    let store = AgentCatalogFileStore(agentsRootURL: agentsRootURL)
    defer {
        try? FileManager.default.removeItem(at: agentsRootURL.deletingLastPathComponent())
    }

    let installedModel = ProviderModelOption(id: "openai:temporary-model", title: "Temporary", capabilities: ["tools"])
    let fallbackModel = ProviderModelOption(id: "openai:fallback-model", title: "Fallback", capabilities: ["tools"])
    let agent = try store.createAgent(
        AgentCreateRequest(id: "model-agent", displayName: "Model Agent", role: "Developer"),
        availableModels: [installedModel]
    )
    let initial = try store.getAgentConfig(agentID: agent.id, availableModels: [installedModel])
    let configured = try store.updateAgentConfig(
        agentID: agent.id,
        request: AgentConfigUpdateRequest(
            role: initial.role,
            selectedModel: installedModel.id,
            documents: initial.documents,
            heartbeat: initial.heartbeat,
            channelSessions: initial.channelSessions,
            runtime: .init(type: .native)
        ),
        availableModels: [installedModel]
    )
    #expect(configured.selectedModel == installedModel.id)

    let reloaded = try store.getAgentConfig(
        agentID: agent.id,
        availableModels: [fallbackModel],
        persistedModelAllowed: { _ in false }
    )

    #expect(reloaded.selectedModel == installedModel.id)
    #expect(reloaded.availableModels.contains { $0.id == installedModel.id })
}
