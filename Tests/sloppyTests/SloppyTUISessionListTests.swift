import Foundation
import Testing
@testable import sloppy
@testable import Protocols
@testable import PluginSDK

@Test
func tuiStateDecodesTrackedSessionsDefault() throws {
    let data = Data(#"{"selections":{},"drafts":{},"sessionDirectories":{}}"#.utf8)
    let state = try JSONDecoder().decode(SloppyTUIState.self, from: data)

    #expect(state.trackedSessions.isEmpty)
}

@Test
func tuiStatePersistsTrackedSessions() throws {
    let now = Date(timeIntervalSince1970: 42)
    let state = SloppyTUIState(trackedSessions: [
        "project:demo": [
            .init(
                agentId: "yadev",
                sessionId: "session-1",
                pinned: true,
                background: true,
                worktreePath: "/tmp/worktree",
                worktreeBranch: "sloppy/task-demo",
                createdAt: now,
                lastOpenedAt: now
            )
        ]
    ])

    let data = try JSONEncoder().encode(state)
    let decoded = try JSONDecoder().decode(SloppyTUIState.self, from: data)

    #expect(decoded.trackedSessions["project:demo"]?.first?.sessionId == "session-1")
    #expect(decoded.trackedSessions["project:demo"]?.first?.pinned == true)
    #expect(decoded.trackedSessions["project:demo"]?.first?.background == true)
    #expect(decoded.trackedSessions["project:demo"]?.first?.worktreePath == "/tmp/worktree")
}

@Test
func sessionListClassifiesWaitingWorkingAndCompletedFromTypedEvents() {
    let request = PlanInputRequest(questions: [
        PlanInputQuestion(id: "q", question: "Choose?", options: [])
    ])
    let waitingEvents = [
        AgentSessionEvent(agentId: "a", sessionId: "s", type: .inputRequest, inputRequest: request)
    ]
    let answeredEvents = waitingEvents + [
        AgentSessionEvent(
            agentId: "a",
            sessionId: "s",
            type: .inputResponse,
            inputResponse: PlanInputResponse(requestId: request.id, status: .answered, answers: [], userId: "tui")
        )
    ]
    let workingEvents = [
        AgentSessionEvent(
            agentId: "a",
            sessionId: "s",
            type: .runStatus,
            runStatus: AgentRunStatusEvent(stage: .responding, label: "Responding")
        )
    ]
    let completedEvents = [
        AgentSessionEvent(
            agentId: "a",
            sessionId: "s",
            type: .runStatus,
            runStatus: AgentRunStatusEvent(stage: .done, label: "Done")
        )
    ]

    #expect(SloppyTUISessionList.section(for: waitingEvents, isPosting: false) == .waitingInput)
    #expect(SloppyTUISessionList.section(for: answeredEvents, isPosting: false) == .completed)
    #expect(SloppyTUISessionList.section(for: workingEvents, isPosting: false) == .working)
    #expect(SloppyTUISessionList.section(for: completedEvents, isPosting: false) == .completed)
    #expect(SloppyTUISessionList.section(for: completedEvents, isPosting: true) == .working)
}

@Test
func sessionListSortsPinnedFirstWithinSections() {
    let old = Date(timeIntervalSince1970: 1)
    let new = Date(timeIntervalSince1970: 2)
    let unpinned = sessionListEntry(sessionID: "session-unpinned", pinned: false, updatedAt: new)
    let pinned = sessionListEntry(sessionID: "session-pinned", pinned: true, updatedAt: old)

    let sorted = SloppyTUISessionList.sortedEntries([unpinned, pinned])

    #expect(sorted.map(\.sessionId) == ["session-pinned", "session-unpinned"])
}

@Test
func sessionListSelectionClampsAcrossEntryRows() {
    #expect(SloppyTUISessionList.clampedSelection(-1, entryCount: 2) == 0)
    #expect(SloppyTUISessionList.clampedSelection(3, entryCount: 2) == 1)
    #expect(SloppyTUISessionList.clampedSelection(9, entryCount: 0) == 0)
}

@Test
func tuiBackgroundWorktreeUsesProjectProviderAndManagedRoot() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    defer {
        try? FileManager.default.removeItem(at: config.resolvedWorkspaceRootURL())
    }
    await service.registerSourceControlProvider(TUIFakeSourceControlProvider())
    let repo = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-tui-bg-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: repo) }

    _ = try await service.createProject(ProjectCreateRequest(
        id: "tui-bg",
        name: "TUI BG",
        repoPath: repo.path,
        sourceControlProviderId: "tui-fake-sc"
    ))

    let worktree = try await service.createTUIBackgroundWorktree(projectID: "tui-bg", taskID: "tui-session")

    #expect(worktree.branchName == "fake/tui-session")
    #expect(worktree.worktreePath.hasSuffix("/worktrees/tui-bg/tui-session"))
}

@Test
func tuiBackgroundSessionIsCreatedAndOwnedByCoreService() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    defer {
        try? FileManager.default.removeItem(at: config.resolvedWorkspaceRootURL())
    }
    await service.registerSourceControlProvider(TUIFakeSourceControlProvider())
    let repo = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-tui-bg-session-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: repo) }

    _ = try await service.createAgent(AgentCreateRequest(id: "bg-agent", displayName: "BG Agent", role: "Testing"))
    _ = try await service.createProject(ProjectCreateRequest(
        id: "tui-bg-session",
        name: "TUI BG Session",
        repoPath: repo.path,
        sourceControlProviderId: "tui-fake-sc"
    ))

    let result = try await service.startTUIBackgroundSession(
        agentID: "bg-agent",
        projectID: "tui-bg-session",
        task: "Keep working after the TUI exits",
        mode: .build,
        reasoningEffort: .low
    )

    let sessions = try await service.listAgentSessions(agentID: "bg-agent", projectID: nil, limit: nil, offset: 0)
    #expect(sessions.contains(where: { $0.id == result.session.id }))
    #expect(result.session.title == "Background: Keep working after the TUI exits")
    #expect(result.worktree.branchName.hasPrefix("fake/tui-"))
}

@Test
func consecutiveTUIBackgroundSessionsUseDistinctWorktrees() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    defer {
        try? FileManager.default.removeItem(at: config.resolvedWorkspaceRootURL())
    }
    await service.registerSourceControlProvider(TUIFakeSourceControlProvider())
    let repo = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-tui-bg-distinct-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: repo) }

    _ = try await service.createAgent(AgentCreateRequest(id: "bg-distinct-agent", displayName: "BG Agent", role: "Testing"))
    _ = try await service.createProject(ProjectCreateRequest(
        id: "tui-bg-distinct",
        name: "TUI BG Distinct",
        repoPath: repo.path,
        sourceControlProviderId: "tui-fake-sc"
    ))

    let first = try await service.startTUIBackgroundSession(
        agentID: "bg-distinct-agent",
        projectID: "tui-bg-distinct",
        task: "First background task",
        mode: .build,
        reasoningEffort: .low
    )
    let second = try await service.startTUIBackgroundSession(
        agentID: "bg-distinct-agent",
        projectID: "tui-bg-distinct",
        task: "Second background task",
        mode: .build,
        reasoningEffort: .low
    )

    #expect(first.worktree.worktreePath != second.worktree.worktreePath)
    #expect(first.worktree.branchName != second.worktree.branchName)
}

@Test
func taskWorkerRetryPreservesExistingTaskSessions() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    defer {
        try? FileManager.default.removeItem(at: config.resolvedWorkspaceRootURL())
    }
    let agentID = "retry-worker"
    let taskID = "TASK-42"
    _ = try await service.createAgent(AgentCreateRequest(id: agentID, displayName: "Retry Worker", role: "Testing"))
    let existing = try await service.createAgentSession(
        agentID: agentID,
        request: AgentSessionCreateRequest(title: "task-\(taskID)")
    )

    _ = await service.runSubagentTask(
        agentID: agentID,
        taskID: taskID,
        objective: "Do the retry without deleting evidence.",
        workingDirectory: nil,
        toolsetNames: ["file"]
    )

    let sessions = try await service.listAgentSessions(agentID: agentID, projectID: nil, limit: nil, offset: 0)
    #expect(sessions.contains(where: { $0.id == existing.id && $0.title == "task-\(taskID)" }))
    #expect(sessions.contains(where: { $0.title == "task-\(taskID)-attempt-2" }))
}

private func sessionListEntry(
    sessionID: String,
    pinned: Bool,
    updatedAt: Date,
    section: SloppyTUISessionListSection = .completed
) -> SloppyTUISessionListEntry {
    SloppyTUISessionListEntry(
        tracked: .init(agentId: "a", sessionId: sessionID, pinned: pinned, createdAt: updatedAt),
        summary: AgentSessionSummary(id: sessionID, agentId: "a", title: sessionID, updatedAt: updatedAt),
        section: section,
        detail: ""
    )
}

private struct TUIFakeSourceControlProvider: SourceControlProvider {
    let id = "tui-fake-sc"
    let displayName = "TUI Fake Source Control"
    let capabilities: Set<SourceControlCapability> = [.worktrees]

    func inspectRepository(at path: String) async -> SourceControlRepositoryInfo {
        SourceControlRepositoryInfo(providerId: id, isRepository: true, rootPath: path, branch: "main")
    }

    func createWorktree(
        repoPath: String,
        taskId: String,
        baseBranch: String,
        worktreeRootPath: String?
    ) async throws -> SourceControlWorktreeResult {
        let root = worktreeRootPath ?? URL(fileURLWithPath: repoPath).appendingPathComponent(".sloppy-worktrees").path
        return SourceControlWorktreeResult(
            worktreePath: URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent(taskId).path,
            branchName: "fake/\(taskId)"
        )
    }
}
