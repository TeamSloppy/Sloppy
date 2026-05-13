import Foundation
import Testing
@testable import sloppy
@testable import Protocols

@Test
func tuiLaunchStartsDraftDespitePersistedSessionSelection() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    defer {
        try? FileManager.default.removeItem(at: config.resolvedWorkspaceRootURL())
    }

    let agent = try await service.createAgent(
        AgentCreateRequest(id: "yadev", displayName: "YADev", role: "Developer")
    )
    let session = try await service.createAgentSession(
        agentID: agent.id,
        request: AgentSessionCreateRequest(projectId: "mobius")
    )

    let resolved = try await SloppyTUIApp.resolveLaunchSelection(
        service: service,
        project: makeTUIProject(id: "mobius"),
        requestedSessionID: nil,
        selection: .init(agentId: agent.id, sessionId: session.id),
        agents: [agent]
    )

    #expect(resolved.agent.id == agent.id)
    #expect(resolved.session.id == "new")
    #expect(!resolved.hasPersistedSession)
}

@Test
func tuiLaunchFallsBackToDraftWhenPersistedSessionIsMissing() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    defer {
        try? FileManager.default.removeItem(at: config.resolvedWorkspaceRootURL())
    }

    let agent = try await service.createAgent(
        AgentCreateRequest(id: "yadev", displayName: "YADev", role: "Developer")
    )

    let resolved = try await SloppyTUIApp.resolveLaunchSelection(
        service: service,
        project: makeTUIProject(id: "mobius"),
        requestedSessionID: nil,
        selection: .init(agentId: agent.id, sessionId: "session-missing"),
        agents: [agent]
    )

    #expect(resolved.agent.id == agent.id)
    #expect(resolved.session.id == "new")
    #expect(!resolved.hasPersistedSession)
}

@Test
func tuiLaunchStartsDraftWhenLatestProjectSessionExists() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    defer {
        try? FileManager.default.removeItem(at: config.resolvedWorkspaceRootURL())
    }

    let agent = try await service.createAgent(
        AgentCreateRequest(id: "yadev", displayName: "YADev", role: "Developer")
    )
    _ = try await service.createAgentSession(
        agentID: agent.id,
        request: AgentSessionCreateRequest(projectId: "mobius")
    )

    let resolved = try await SloppyTUIApp.resolveLaunchSelection(
        service: service,
        project: makeTUIProject(id: "mobius"),
        requestedSessionID: nil,
        selection: .init(agentId: agent.id),
        agents: [agent]
    )

    #expect(resolved.agent.id == agent.id)
    #expect(resolved.session.id == "new")
    #expect(!resolved.hasPersistedSession)
}

@Test
func tuiLaunchRequestedSessionCanResolveWithoutProjectMetadata() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    defer {
        try? FileManager.default.removeItem(at: config.resolvedWorkspaceRootURL())
    }

    let agent = try await service.createAgent(
        AgentCreateRequest(id: "yadev", displayName: "YADev", role: "Developer")
    )
    let legacySession = try await service.createAgentSession(
        agentID: agent.id,
        request: AgentSessionCreateRequest()
    )

    let resolved = try await SloppyTUIApp.resolveLaunchSelection(
        service: service,
        project: makeTUIProject(id: "mobius"),
        requestedSessionID: legacySession.id,
        selection: nil,
        agents: [agent]
    )

    #expect(resolved.agent.id == agent.id)
    #expect(resolved.session.id == legacySession.id)
    #expect(resolved.hasPersistedSession)
}

@Test
func tuiLaunchSavedProjectAgentWinsOverProjectActors() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    defer {
        try? FileManager.default.removeItem(at: config.resolvedWorkspaceRootURL())
    }

    let saved = try await service.createAgent(
        AgentCreateRequest(id: "last-used", displayName: "Last Used", role: "Developer")
    )
    let projectActor = try await service.createAgent(
        AgentCreateRequest(id: "project-actor", displayName: "Project Actor", role: "Reviewer")
    )

    let resolved = try await SloppyTUIApp.resolveLaunchSelection(
        service: service,
        project: makeTUIProject(id: "mobius", actors: [projectActor.id]),
        requestedSessionID: nil,
        selection: .init(agentId: saved.id),
        agents: [saved, projectActor]
    )

    #expect(resolved.agent.id == saved.id)
    #expect(resolved.session.id == "new")
    #expect(!resolved.hasPersistedSession)
}

@Test
func tuiLaunchUsesFirstProjectActorLinkedAgent() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    defer {
        try? FileManager.default.removeItem(at: config.resolvedWorkspaceRootURL())
    }

    let fallback = try await service.createAgent(
        AgentCreateRequest(id: "fallback", displayName: "Fallback", role: "Generalist")
    )
    let builder = try await service.createAgent(
        AgentCreateRequest(id: "builder", displayName: "Builder", role: "Developer")
    )
    _ = try await service.createActorNode(
        node: ActorNode(
            id: "actor:builder",
            displayName: "Builder Actor",
            kind: .agent,
            linkedAgentId: builder.id
        )
    )

    let resolved = try await SloppyTUIApp.resolveLaunchSelection(
        service: service,
        project: makeTUIProject(id: "mobius", actors: ["actor:builder"]),
        requestedSessionID: nil,
        selection: nil,
        agents: [fallback, builder]
    )

    #expect(resolved.agent.id == builder.id)
    #expect(resolved.session.id == "new")
    #expect(!resolved.hasPersistedSession)
}

@Test
func tuiLaunchUsesDirectProjectActorAgentID() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    defer {
        try? FileManager.default.removeItem(at: config.resolvedWorkspaceRootURL())
    }

    let fallback = try await service.createAgent(
        AgentCreateRequest(id: "fallback", displayName: "Fallback", role: "Generalist")
    )
    let builder = try await service.createAgent(
        AgentCreateRequest(id: "builder", displayName: "Builder", role: "Developer")
    )

    let resolved = try await SloppyTUIApp.resolveLaunchSelection(
        service: service,
        project: makeTUIProject(id: "mobius", actors: [builder.id]),
        requestedSessionID: nil,
        selection: nil,
        agents: [fallback, builder]
    )

    #expect(resolved.agent.id == builder.id)
    #expect(resolved.session.id == "new")
    #expect(!resolved.hasPersistedSession)
}

@Test
func tuiLaunchStaleSavedAgentFallsBackToProjectActor() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    defer {
        try? FileManager.default.removeItem(at: config.resolvedWorkspaceRootURL())
    }

    let fallback = try await service.createAgent(
        AgentCreateRequest(id: "fallback", displayName: "Fallback", role: "Generalist")
    )
    let builder = try await service.createAgent(
        AgentCreateRequest(id: "builder", displayName: "Builder", role: "Developer")
    )

    let resolved = try await SloppyTUIApp.resolveLaunchSelection(
        service: service,
        project: makeTUIProject(id: "mobius", actors: [builder.id]),
        requestedSessionID: nil,
        selection: .init(agentId: "missing-agent"),
        agents: [fallback, builder]
    )

    #expect(resolved.agent.id == builder.id)
    #expect(resolved.session.id == "new")
    #expect(!resolved.hasPersistedSession)
}

@Test
func tuiLaunchInvalidProjectActorsFallBackToDefaultAgent() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    defer {
        try? FileManager.default.removeItem(at: config.resolvedWorkspaceRootURL())
    }

    let fallback = try await service.createAgent(
        AgentCreateRequest(id: "fallback", displayName: "Fallback", role: "Generalist")
    )
    _ = try await service.createActorNode(
        node: ActorNode(
            id: "human:dispatcher",
            displayName: "Dispatcher",
            kind: .human
        )
    )

    let resolved = try await SloppyTUIApp.resolveLaunchSelection(
        service: service,
        project: makeTUIProject(id: "mobius", actors: ["", "human:dispatcher", "actor:missing"]),
        requestedSessionID: nil,
        selection: nil,
        agents: [fallback]
    )

    #expect(resolved.agent.id == fallback.id)
    #expect(resolved.session.id == "new")
    #expect(!resolved.hasPersistedSession)
}

private func makeTUIProject(id: String, actors: [String] = []) -> ProjectRecord {
    ProjectRecord(
        id: id,
        name: id,
        description: "",
        channels: [],
        tasks: [],
        actors: actors
    )
}
