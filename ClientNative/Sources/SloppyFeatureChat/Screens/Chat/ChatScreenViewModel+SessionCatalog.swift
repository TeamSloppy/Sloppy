import Foundation
import Observation
import SloppyClientCore
import SloppyClientUI
import SwiftUI
import UniformTypeIdentifiers

extension ChatScreenViewModel {
    public func loadInitialData() {
        guard !didLoadInitialData, initialDataTask == nil else { return }

        initialDataTask = Task { @MainActor [weak self] in
            await self?.performInitialDataLoad()
        }
    }

    public func waitForInitialData() async {
        loadInitialData()
        let task = initialDataTask
        await task?.value
    }

    private func performInitialDataLoad() async {
        guard !didLoadInitialData, !isLoadingInitialData else { return }

        isLoadingInitialData = true
        await restoreInitialDataFromCache()

        // Cached data is enough to render the workspace. Network refreshes
        // continue after this flag releases the initial loading screen.
        didLoadInitialData = true

        await revalidateInitialData()
        isLoadingInitialData = false
        initialDataTask = nil
    }

    public func installAggregatedSessionCatalog(_ sessions: [ChatSessionSummary]) {
        sessionLoadGeneration += 1
        isLoadingSessions = false
        sessionCatalog = sortSessions(
            ChatSessionCatalog.mergeAggregated(existing: sessionCatalog, incoming: sessions)
        )
    }

    public func removeSessionFromCatalog(_ session: ChatSessionSummary) {
        sessionCatalog.removeAll { $0.storageID == session.storageID }
    }

    public func loadSessions(for agent: APIAgentRecord, projectId: String? = nil) async {
        sessionLoadGeneration += 1
        let generation = sessionLoadGeneration
        isLoadingSessions = true

        let cached = await cacheStore.loadSessions(agentId: agent.id, projectId: projectId)
        guard generation == sessionLoadGeneration else { return }
        sessions = sortSessions(cached.filter { $0.kind != "heartbeat" })

        do {
            if let projectId {
                _ = try? await apiClient.openLongChat(agentId: agent.id, projectId: projectId)
            }
            let fetched = try await apiClient.fetchAgentSessions(agentId: agent.id, projectId: projectId, includeWorkers: true)
            guard generation == sessionLoadGeneration else { return }
            let filtered = fetched.filter { $0.kind != "heartbeat" }
            sessions = sortSessions(filtered)
            await cacheStore.cacheSessions(agentId: agent.id, projectId: projectId, sessions: filtered)
        } catch {
            // Keep the cached snapshot visible while offline.
        }

        if generation == sessionLoadGeneration {
            isLoadingSessions = false
        }
    }

    private func loadSessionCatalog(for agents: [APIAgentRecord]) async {
        sessionLoadGeneration += 1
        let generation = sessionLoadGeneration
        isLoadingSessions = true

        var cachedBatches: [[ChatSessionSummary]] = []
        for agent in agents {
            cachedBatches.append(await cacheStore.loadSessions(agentId: agent.id))
        }
        guard generation == sessionLoadGeneration else { return }
        sessionCatalog = sortSessions(ChatSessionCatalog.merge(cachedBatches))

        let apiClient = apiClient
        let results = await withTaskGroup(
            of: SessionCatalogFetchResult.self,
            returning: [SessionCatalogFetchResult].self
        ) { group in
            for agent in agents {
                group.addTask {
                    SessionCatalogFetchResult(
                        agentId: agent.id,
                        sessions: try? await apiClient.fetchAgentSessions(agentId: agent.id, includeWorkers: true)
                    )
                }
            }

            var results: [SessionCatalogFetchResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        guard generation == sessionLoadGeneration else { return }
        var batches: [[ChatSessionSummary]] = []
        for result in results {
            if let fetched = result.sessions {
                let filtered = fetched.filter { $0.kind != "heartbeat" }
                batches.append(filtered)
                await cacheStore.cacheSessions(
                    agentId: result.agentId,
                    projectId: nil,
                    sessions: filtered
                )
            } else {
                batches.append(await cacheStore.loadSessions(agentId: result.agentId))
            }
        }

        guard generation == sessionLoadGeneration else { return }
        sessionCatalog = sortSessions(ChatSessionCatalog.merge(batches))
        isLoadingSessions = false
    }

    public func refreshCurrentContext() async {
        guard let agent = selectedAgent else {
            return
        }

        if loadsGlobalSessionCatalog {
            await loadSessionCatalog(for: agents)
        }
        await loadSessions(for: agent, projectId: activeTaskId == nil ? activeProjectId : nil)

        if let selectedSessionId {
            await hydrateSession(agentId: agent.id, sessionId: selectedSessionId)
        }
    }

    private func restoreInitialDataFromCache() async {
        async let cachedAgentsRequest = cacheStore.loadAgents()
        async let cachedProjectsRequest = cacheStore.loadProjects()

        agents = await cachedAgentsRequest
        projects = await cachedProjectsRequest
        restoreLastProjectContextIfAvailable()
        await restoreInitialAgentContext(using: agents, loadsCachedSessionsOnly: true)
    }

    private func revalidateInitialData() async {
        async let agentsRequest: [APIAgentRecord]? = try? await apiClient.fetchAgents()
        async let modelsRequest: [ChatModelOption]? = try? await apiClient.fetchAvailableModels()
        async let projectsRevalidation: Void = revalidateInitialProjects()

        let fetchedAgents = await agentsRequest
        if let fetchedAgents {
            agents = fetchedAgents
            await cacheStore.cacheAgents(fetchedAgents)
        }
        await restoreInitialAgentContext(using: agents, loadsCachedSessionsOnly: false)
        if let fetchedModels = await modelsRequest {
            applyAvailableModels(fetchedModels)
        }
        await projectsRevalidation
    }

    private func revalidateInitialProjects() async {
        if let fetchedProjects = try? await apiClient.fetchProjects() {
            projects = fetchedProjects
            await cacheStore.cacheProjects(fetchedProjects)
            restoreLastProjectContextIfAvailable()
        }
    }

    private func restoreInitialAgentContext(
        using availableAgents: [APIAgentRecord],
        loadsCachedSessionsOnly: Bool
    ) async {
        let preferredAgentId = selectedAgent?.id ?? settings.lastAgentId
        guard let agent = availableAgents.first(where: { $0.id == preferredAgentId })
            ?? availableAgents.first else {
            return
        }

        selectedAgent = agent
        settings.lastAgentId = agent.id
        restoreModelSelection(agentId: agent.id, sessionId: selectedSessionId)

        if loadsGlobalSessionCatalog {
            if loadsCachedSessionsOnly {
                var batches: [[ChatSessionSummary]] = []
                for availableAgent in availableAgents {
                    batches.append(await cacheStore.loadSessions(agentId: availableAgent.id))
                }
                sessionCatalog = sortSessions(ChatSessionCatalog.merge(batches))
            } else {
                await loadSessionCatalog(for: availableAgents)
            }
            sessions = sortSessions(sessionCatalog.filter {
                $0.agentId == agent.id
                    && (activeSessionProjectFilter == nil || $0.projectId == activeSessionProjectFilter)
            })
        } else if loadsCachedSessionsOnly {
            let cached = await cacheStore.loadSessions(
                agentId: agent.id,
                projectId: activeSessionProjectFilter
            )
            sessions = sortSessions(cached.filter { $0.kind != "heartbeat" })
        } else {
            await loadSessions(for: agent, projectId: activeSessionProjectFilter)
        }

        if !loadsCachedSessionsOnly, let projectId = activeProjectId, activeTaskId == nil,
           let main = try? await apiClient.openLongChat(agentId: agent.id, projectId: projectId) {
            upsertSessionSummary(main)
            if restoresLastSession, selectedSessionId == nil, pendingSessionSummary == nil,
               pendingNavigationRequest == nil, !createsSeparateProjectChat,
               activeProjectId == projectId, activeTaskId == nil, selectedAgent?.id == agent.id {
                selectProjectLongChat(main, contextTitle: activeContextTitle)
            }
        }
        restorePendingOrLastSession(for: agent)
        if let pendingNavigationRequest {
            applyNavigationRequest(pendingNavigationRequest)
        }
    }

    private func restoreLastProjectContextIfAvailable() {
        guard activeProjectId == nil,
              activeTaskId == nil,
              selectedSessionId == nil,
              pendingNavigationRequest == nil,
              let projectId = settings.lastProjectId,
              let project = projects.first(where: { $0.id == projectId }) else {
            return
        }

        activeProjectId = project.id
        activeContextTitle = "Project: \(project.name)"
    }

    private func restorePendingOrLastSession(for agent: APIAgentRecord) {
        if let pendingSessionSummary {
            openSessionFromSummary(pendingSessionSummary)
            return
        }

        if selectedSessionId == nil,
           restoresLastSession,
           activeProjectId == nil || activeTaskId != nil,
           let lastSessionId = settings.lastSessionId,
           sessions.contains(where: { $0.id == lastSessionId }) {
            selectSession(lastSessionId)
            return
        }

        guard selectedSessionId == nil else { return }
        if transcript.isEmpty {
            syncComposerDraft(
                toSessionId: nil,
                projectId: activeProjectId,
                taskId: activeTaskId,
                agentId: agent.id
            )
        }
    }

    private var activeSessionProjectFilter: String? {
        activeTaskId == nil ? activeProjectId : nil
    }
}
