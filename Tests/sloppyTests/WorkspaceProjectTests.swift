import Foundation
import Testing
@testable import Protocols
@testable import sloppy

private func makeWorkspaceRoots(_ count: Int = 2) throws -> [URL] {
    try (0..<count).map { index in
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sloppy-workspace-\(index)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@Test
func workspaceCreationPreservesRootOrderAndPrimaryRepoPath() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let roots = try makeWorkspaceRoots()
    defer { roots.forEach { try? FileManager.default.removeItem(at: $0) } }

    let result = try await service.createProject(
        ProjectCreateRequest(
            id: "workspace-roots",
            name: "Workspace Roots",
            kind: .workspace,
            directoryPaths: roots.map(\.path)
        )
    )

    #expect(result.project.kind == .workspace)
    #expect(result.project.directoryPaths == roots.map(\.path))
    #expect(result.project.repoPath == roots[0].path)

    let context = await service.toolContextForSession(
        sessionID: "workspace-test-session",
        sessionTitle: "Workspace",
        projectID: result.project.id
    )
    #expect(context.workingDirectory == roots[0].path)
    #expect(context.extraRoots.contains(roots[0].path))
    #expect(context.extraRoots.contains(roots[1].path))
}

@Test
func workspaceValidationRejectsInvalidRootsAndRepoURLConflict() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let roots = try makeWorkspaceRoots()
    defer { roots.forEach { try? FileManager.default.removeItem(at: $0) } }

    await #expect(throws: CoreService.ProjectError.self) {
        try await service.createProject(
            ProjectCreateRequest(
                name: "One Root",
                kind: .workspace,
                directoryPaths: [roots[0].path]
            )
        )
    }
    await #expect(throws: CoreService.ProjectError.self) {
        try await service.createProject(
            ProjectCreateRequest(
                name: "Duplicate Roots",
                kind: .workspace,
                directoryPaths: [roots[0].path, roots[0].path]
            )
        )
    }
    await #expect(throws: CoreService.ProjectError.self) {
        try await service.createProject(
            ProjectCreateRequest(
                name: "Repository Conflict",
                repoUrl: "https://example.com/repository.git",
                kind: .workspace,
                directoryPaths: roots.map(\.path)
            )
        )
    }
}

@Test
func updatingWorkspaceRefreshesExistingSessionRoots() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let roots = try makeWorkspaceRoots(3)
    defer { roots.forEach { try? FileManager.default.removeItem(at: $0) } }

    let created = try await service.createProject(
        ProjectCreateRequest(
            id: "workspace-update",
            name: "Workspace Update",
            kind: .workspace,
            directoryPaths: [roots[0].path, roots[1].path]
        )
    ).project
    let sessionID = "already-open-workspace-session"
    let before = await service.toolContextForSession(
        sessionID: sessionID,
        sessionTitle: "Workspace",
        projectID: created.id
    )
    #expect(before.extraRoots.contains(roots[1].path))

    let updated = try await service.updateProject(
        projectID: created.id,
        request: ProjectUpdateRequest(
            kind: .workspace,
            directoryPaths: [roots[2].path, roots[0].path]
        )
    )
    #expect(updated.repoPath == roots[2].path)

    let after = await service.toolContextForSession(
        sessionID: sessionID,
        sessionTitle: "Workspace",
        projectID: created.id
    )
    #expect(after.workingDirectory == roots[2].path)
    #expect(after.extraRoots.contains(roots[0].path))
    #expect(after.extraRoots.contains(roots[2].path))
    #expect(!after.extraRoots.contains(roots[1].path))
}

@Test
func workspaceSessionCanUseEveryRootAndKeepsManualRootsAfterUpdate() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let roots = try makeWorkspaceRoots(4)
    defer { roots.forEach { try? FileManager.default.removeItem(at: $0) } }
    try Data("secondary".utf8).write(to: roots[1].appendingPathComponent("secondary.txt"))
    let agentID = "workspace-session-agent"
    _ = try await service.createAgent(
        AgentCreateRequest(id: agentID, displayName: "Workspace Session Agent", role: "assistant")
    )
    _ = try await service.createProject(
        ProjectCreateRequest(
            id: "workspace-session-access",
            name: "Workspace Session Access",
            kind: .workspace,
            directoryPaths: [roots[0].path, roots[1].path]
        )
    )
    let session = try await service.createAgentSession(
        agentID: agentID,
        request: AgentSessionCreateRequest(title: "Workspace Chat", projectId: "workspace-session-access")
    )

    let read = await service.invokeToolFromRuntime(
        agentID: agentID,
        sessionID: session.id,
        request: ToolInvocationRequest(
            tool: "files.read",
            arguments: ["path": .string(roots[1].appendingPathComponent("secondary.txt").path)]
        ),
        recordSessionEvents: false
    )
    #expect(read.ok)
    #expect(read.data?.asObject?["content"]?.asString == "secondary")

    _ = try await service.addAgentSessionDirectory(
        agentID: agentID,
        sessionID: session.id,
        request: AgentSessionDirectoryRequest(path: roots[2].path)
    )
    _ = try await service.updateProject(
        projectID: "workspace-session-access",
        request: ProjectUpdateRequest(
            kind: .workspace,
            directoryPaths: [roots[3].path, roots[0].path]
        )
    )

    let context = await service.toolContextForSession(
        sessionID: session.id,
        sessionTitle: session.title,
        projectID: "workspace-session-access"
    )
    #expect(context.workingDirectory == roots[3].path)
    #expect(context.extraRoots.contains(roots[0].path))
    #expect(context.extraRoots.contains(roots[2].path))
    #expect(context.extraRoots.contains(roots[3].path))
    #expect(!context.extraRoots.contains(roots[1].path))
}

@Test
func workspaceFileBrowserExposesEveryRootWithExactPaths() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let roots = try makeWorkspaceRoots()
    defer { roots.forEach { try? FileManager.default.removeItem(at: $0) } }
    try Data("first".utf8).write(to: roots[0].appendingPathComponent("shared.txt"))
    try Data("second".utf8).write(to: roots[1].appendingPathComponent("shared.txt"))

    _ = try await service.createProject(
        ProjectCreateRequest(
            id: "workspace-files",
            name: "Workspace Files",
            kind: .workspace,
            directoryPaths: roots.map(\.path)
        )
    )

    let response = await router.handle(method: "GET", path: "/v1/projects/workspace-files/files", body: nil)
    #expect(response.status == 200)
    let entries = try JSONDecoder().decode([ProjectFileEntry].self, from: response.body)
    #expect(entries.map(\.path) == roots.map { Optional($0.path) })

    let encodedPath = roots[1].appendingPathComponent("shared.txt").path
        .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
    let contentResponse = await router.handle(
        method: "GET",
        path: "/v1/projects/workspace-files/files/content?path=\(encodedPath)",
        body: nil
    )
    #expect(contentResponse.status == 200)
    let content = try JSONDecoder().decode(ProjectFileContentResponse.self, from: contentResponse.body)
    #expect(content.content == "second")

    let outside = FileManager.default.temporaryDirectory
        .appendingPathComponent("workspace-outside-\(UUID().uuidString).txt")
    defer { try? FileManager.default.removeItem(at: outside) }
    try Data("outside".utf8).write(to: outside)
    let escape = roots[0].appendingPathComponent("escape.txt")
    try FileManager.default.createSymbolicLink(at: escape, withDestinationURL: outside)
    let encodedEscape = escape.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
    let escapeResponse = await router.handle(
        method: "GET",
        path: "/v1/projects/workspace-files/files/content?path=\(encodedEscape)",
        body: nil
    )
    #expect(escapeResponse.status == 400)
}

@Test
func workspaceContextLoadsAllRootsWithinOneBudget() throws {
    let roots = try makeWorkspaceRoots()
    defer { roots.forEach { try? FileManager.default.removeItem(at: $0) } }
    for (index, root) in roots.enumerated() {
        try Data("root-\(index)-instructions".utf8).write(to: root.appendingPathComponent("AGENTS.md"))
        let skillDirectory = root
            .appendingPathComponent(".skills", isDirectory: true)
            .appendingPathComponent("skill-\(index)", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        let skillFile = skillDirectory.appendingPathComponent("SKILL.md")
        try Data("skill-\(index)".utf8).write(to: skillFile)
        #expect(FileManager.default.fileExists(atPath: skillFile.path))
    }

    let loader = ProjectContextLoader(
        limits: .init(maxSkillFiles: 1, maxCharsPerFile: 1_000, maxTotalChars: 1_000)
    )
    let result = loader.load(repoPaths: roots.map(\.path))

    #expect(result.loadedDocs.map(\.relativePath) == roots.map { $0.appendingPathComponent("AGENTS.md").path })
    #expect(result.loadedSkills.count == 1)
    #expect(result.truncated)
    #expect(result.totalChars <= 1_000)
}

@Test
func sqliteWorkspacePersistencePreservesDirectoryOrder() async throws {
    let roots = try makeWorkspaceRoots()
    defer { roots.forEach { try? FileManager.default.removeItem(at: $0) } }
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-workspace-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    var config = CoreConfig.test
    config.sqlitePath = databaseURL.path

    let service = CoreService(config: config)
    _ = try await service.createProject(
        ProjectCreateRequest(
            id: "sqlite-workspace",
            name: "SQLite Workspace",
            kind: .workspace,
            directoryPaths: [roots[1].path, roots[0].path]
        )
    )

    let restarted = CoreService(config: config)
    let project = try await restarted.getProject(id: "sqlite-workspace")
    #expect(project.kind == .workspace)
    #expect(project.directoryPaths == [roots[1].path, roots[0].path])
    #expect(project.repoPath == roots[1].path)
}
