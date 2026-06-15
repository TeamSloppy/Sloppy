import Foundation
import Protocols
import Testing
@testable import sloppy

private func runGit(_ args: [String], cwd: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = args
    process.currentDirectoryURL = cwd
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        throw NSError(domain: "git", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: output])
    }
}

@Test
func workspaceGitSyncPushesConfigurationSnapshotOnly() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-git-sync-test-\(UUID().uuidString)", isDirectory: true)
    let workspace = root.appendingPathComponent(".sloppy", isDirectory: true)
    let remote = root.appendingPathComponent("remote.git", isDirectory: true)
    let verify = root.appendingPathComponent("verify", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
    try runGit(["init", "--bare"], cwd: remote)

    try FileManager.default.createDirectory(
        at: workspace.appendingPathComponent("agents/sloppy", isDirectory: true),
        withIntermediateDirectories: true
    )
    try Data("agent instructions".utf8).write(to: workspace.appendingPathComponent("agents/sloppy/AGENTS.md"))
    try Data("{}".utf8).write(to: workspace.appendingPathComponent("channel-models.json"))
    try Data(
        """
        {
          "auth": { "token": "dev-secret" },
          "gitSync": { "authToken": "ghp_secret", "repository": "ignored" },
          "models": [{ "apiKey": "sk-secret", "model": "example" }]
        }
        """.utf8
    ).write(to: workspace.appendingPathComponent("sloppy.json"))

    try FileManager.default.createDirectory(at: workspace.appendingPathComponent("memory", isDirectory: true), withIntermediateDirectories: true)
    try Data("sqlite".utf8).write(to: workspace.appendingPathComponent("memory/core.sqlite"))
    try FileManager.default.createDirectory(at: workspace.appendingPathComponent("projects/repo", isDirectory: true), withIntermediateDirectories: true)
    try Data("project".utf8).write(to: workspace.appendingPathComponent("projects/repo/file.txt"))
    try FileManager.default.createDirectory(at: workspace.appendingPathComponent("auth", isDirectory: true), withIntermediateDirectories: true)
    try Data("token".utf8).write(to: workspace.appendingPathComponent("auth/github.json"))

    let service = WorkspaceGitSyncService()
    let response = try await service.syncNow(
        config: .init(
            enabled: true,
            repository: remote.path,
            branch: "main",
            conflictStrategy: .remoteWins
        ),
        workspaceRootURL: workspace
    )

    #expect(response.ok)
    #expect(response.filesChanged > 0)

    try runGit(["clone", remote.path, verify.path], cwd: root)
    try runGit(["checkout", "main"], cwd: verify)

    #expect(FileManager.default.fileExists(atPath: verify.appendingPathComponent("agents/sloppy/AGENTS.md").path))
    #expect(FileManager.default.fileExists(atPath: verify.appendingPathComponent("channel-models.json").path))
    #expect(!FileManager.default.fileExists(atPath: verify.appendingPathComponent("memory/core.sqlite").path))
    #expect(!FileManager.default.fileExists(atPath: verify.appendingPathComponent("projects/repo/file.txt").path))
    #expect(!FileManager.default.fileExists(atPath: verify.appendingPathComponent("auth/github.json").path))

    let syncedConfig = try String(contentsOf: verify.appendingPathComponent("sloppy.json"), encoding: .utf8)
    #expect(!syncedConfig.contains("dev-secret"))
    #expect(!syncedConfig.contains("ghp_secret"))
    #expect(!syncedConfig.contains("sk-secret"))
}

@Test
func workspaceGitSyncEndpointReturnsBadRequestWhenDisabled() async throws {
    let configPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-git-sync-disabled-\(UUID().uuidString).json")
        .path
    defer { try? FileManager.default.removeItem(atPath: configPath) }

    let service = CoreService(config: .test, configPath: configPath, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)

    let response = await router.handle(method: "POST", path: "/v1/git-sync/run", body: nil)
    #expect(response.status == 400)

    let payload = try JSONDecoder().decode(WorkspaceGitSyncResponse.self, from: response.body)
    #expect(payload.ok == false)
    #expect(payload.status?.failedAttempts == 1)
    #expect(payload.status?.lastAttemptAt?.isEmpty == false)
    #expect(payload.status?.lastFailureAt == payload.status?.lastAttemptAt)
    #expect(payload.status?.lastError == "Workspace Git Sync is disabled.")
}

@Test
func workspaceGitSyncEndpointRecordsFailedAttemptStatus() async throws {
    let configPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-git-sync-failure-\(UUID().uuidString).json")
        .path
    defer { try? FileManager.default.removeItem(atPath: configPath) }

    var config = CoreConfig.test
    config.gitSync = .init(enabled: true, repository: "", branch: "main")
    let service = CoreService(config: config, configPath: configPath, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)

    let response = await router.handle(method: "POST", path: "/v1/git-sync/run", body: nil)
    #expect(response.status == 400)

    let payload = try JSONDecoder().decode(WorkspaceGitSyncResponse.self, from: response.body)
    #expect(payload.ok == false)
    #expect(payload.status?.failedAttempts == 1)
    #expect(payload.status?.lastAttemptAt?.isEmpty == false)
    #expect(payload.status?.lastFailureAt == payload.status?.lastAttemptAt)
    #expect(payload.status?.lastError == "Workspace Git Sync repository is not configured.")

    let updatedConfig = await service.getConfig()
    #expect(updatedConfig.gitSync.status.failedAttempts == 1)
    #expect(updatedConfig.gitSync.status.lastError == "Workspace Git Sync repository is not configured.")
}

@Test
func workspaceGitSyncEndpointRecordsSuccessfulSyncStatus() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-git-sync-status-test-\(UUID().uuidString)", isDirectory: true)
    let workspace = root.appendingPathComponent("workspace", isDirectory: true)
    let remote = root.appendingPathComponent("remote.git", isDirectory: true)
    let configPath = root.appendingPathComponent("sloppy.json").path
    defer { try? FileManager.default.removeItem(at: root) }

    try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
    try runGit(["init", "--bare"], cwd: remote)
    try Data("{}".utf8).write(to: workspace.appendingPathComponent("channel-models.json"))

    var config = CoreConfig.test
    config.workspace = .init(name: workspace.lastPathComponent, basePath: root.path)
    config.gitSync = .init(
        enabled: true,
        repository: remote.path,
        branch: "main",
        conflictStrategy: .remoteWins,
        status: .init(
            lastAttemptAt: "2026-06-14T10:00:00Z",
            lastFailureAt: "2026-06-14T10:00:00Z",
            lastError: "previous failure",
            failedAttempts: 2
        )
    )

    let service = CoreService(config: config, configPath: configPath, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)

    let response = await router.handle(method: "POST", path: "/v1/git-sync/run", body: nil)
    #expect(response.status == 200)

    let payload = try JSONDecoder().decode(WorkspaceGitSyncResponse.self, from: response.body)
    #expect(payload.ok)
    #expect(payload.commit?.isEmpty == false)
    #expect(payload.status?.failedAttempts == 0)
    #expect(payload.status?.lastError == nil)
    #expect(payload.status?.lastSuccessAt == payload.status?.lastAttemptAt)
    #expect(payload.status?.lastCommit == payload.commit)
    #expect(payload.status?.lastFilesChanged == payload.filesChanged)

    let updatedConfig = await service.getConfig()
    #expect(updatedConfig.gitSync.status.failedAttempts == 0)
    #expect(updatedConfig.gitSync.status.lastSuccessAt == payload.status?.lastSuccessAt)
}
