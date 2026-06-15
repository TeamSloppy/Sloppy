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
        ProviderModelOption(id: "openai-api:acme/foo", title: "B", capabilities: [])
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

    let installedModel = ProviderModelOption(id: "openai-api:temporary-model", title: "Temporary", capabilities: ["tools"])
    let fallbackModel = ProviderModelOption(id: "openai-api:fallback-model", title: "Fallback", capabilities: ["tools"])
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

@Test
func readingAgentConfigPreservesTemporarilyUnavailablePlannerModel() async throws {
    let agentsRootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-planner-model-preserve-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("agents", isDirectory: true)
    let store = AgentCatalogFileStore(agentsRootURL: agentsRootURL)
    defer {
        try? FileManager.default.removeItem(at: agentsRootURL.deletingLastPathComponent())
    }

    let executorModel = ProviderModelOption(id: "openai-api:executor-model", title: "Executor", capabilities: ["tools"])
    let plannerModel = ProviderModelOption(id: "openai-api:planner-model", title: "Planner", capabilities: ["reasoning"])
    let fallbackModel = ProviderModelOption(id: "openai-api:fallback-model", title: "Fallback", capabilities: ["tools"])
    let agent = try store.createAgent(
        AgentCreateRequest(id: "planner-agent", displayName: "Planner Agent", role: "Developer"),
        availableModels: [executorModel, plannerModel]
    )
    let initial = try store.getAgentConfig(agentID: agent.id, availableModels: [executorModel, plannerModel])
    let configured = try store.updateAgentConfig(
        agentID: agent.id,
        request: AgentConfigUpdateRequest(
            role: initial.role,
            selectedModel: executorModel.id,
            plannerModel: plannerModel.id,
            documents: initial.documents,
            heartbeat: initial.heartbeat,
            channelSessions: initial.channelSessions,
            runtime: .init(type: .native)
        ),
        availableModels: [executorModel, plannerModel]
    )
    #expect(configured.selectedModel == executorModel.id)
    #expect(configured.plannerModel == plannerModel.id)

    let reloaded = try store.getAgentConfig(
        agentID: agent.id,
        availableModels: [fallbackModel],
        persistedModelAllowed: { _ in false }
    )

    #expect(reloaded.selectedModel == executorModel.id)
    #expect(reloaded.plannerModel == plannerModel.id)
    #expect(reloaded.availableModels.contains { $0.id == executorModel.id })
    #expect(reloaded.availableModels.contains { $0.id == plannerModel.id })
}

@Test
func updatingAgentConfigPersistsReasoningEffortDefault() async throws {
    let agentsRootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-reasoning-effort-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("agents", isDirectory: true)
    let store = AgentCatalogFileStore(agentsRootURL: agentsRootURL)
    defer {
        try? FileManager.default.removeItem(at: agentsRootURL.deletingLastPathComponent())
    }

    let model = ProviderModelOption(id: "openai-api:o4-mini", title: "Reasoning", capabilities: ["reasoning", "tools"])
    let agent = try store.createAgent(
        AgentCreateRequest(id: "reasoning-config-agent", displayName: "Reasoning Config Agent", role: "Developer"),
        availableModels: [model]
    )
    let initial = try store.getAgentConfig(agentID: agent.id, availableModels: [model])

    let updated = try store.updateAgentConfig(
        agentID: agent.id,
        request: AgentConfigUpdateRequest(
            role: initial.role,
            selectedModel: model.id,
            documents: initial.documents,
            heartbeat: initial.heartbeat,
            channelSessions: initial.channelSessions,
            reasoningEffort: .high,
            runtime: .init(type: .native),
            skills: initial.skills
        ),
        availableModels: [model]
    )
    let reloaded = try store.getAgentConfig(agentID: agent.id, availableModels: [model])

    #expect(updated.reasoningEffort == .high)
    #expect(reloaded.reasoningEffort == .high)
}
