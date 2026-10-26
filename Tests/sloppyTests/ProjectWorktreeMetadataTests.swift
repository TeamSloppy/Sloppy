import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
@testable import Protocols
@testable import sloppy

private func makeWorktreeMetadataTempDirectory(prefix: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

@discardableResult
private func runGit(_ arguments: [String], in directory: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git"] + arguments
    process.currentDirectoryURL = directory

    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error

    try process.run()
    process.waitUntilExit()

    let outputText = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let errorText = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    guard process.terminationStatus == 0 else {
        throw NSError(
            domain: "ProjectWorktreeMetadataTests",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: errorText.isEmpty ? outputText : errorText]
        )
    }
    return outputText
}

@discardableResult
private func createProject(
    service: CoreService,
    id: String,
    name: String,
    repoPath: String
) async throws -> ProjectRecord {
    try await service.createProject(
        ProjectCreateRequest(
            id: id,
            name: name,
            description: "",
            channels: [],
            repoPath: repoPath
        )
    ).project
}

@Test
func projectSummariesAnnotateGitWorktreeParent() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let repo = try makeWorktreeMetadataTempDirectory(prefix: "project-worktree-git")
    defer { try? FileManager.default.removeItem(at: repo) }

    try runGit(["init"], in: repo)
    try runGit(["config", "user.email", "test@example.com"], in: repo)
    try runGit(["config", "user.name", "Test User"], in: repo)
    try "hello\n".write(to: repo.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
    try runGit(["add", "README.md"], in: repo)
    try runGit(["commit", "-m", "Initial commit"], in: repo)
    try runGit(["branch", "-M", "main"], in: repo)

    let worktree = repo
        .appendingPathComponent(".sloppy-worktrees", isDirectory: true)
        .appendingPathComponent("feature-child", isDirectory: true)
    try runGit(["worktree", "add", "-b", "feature/child", worktree.path, "main"], in: repo)

    _ = try await createProject(service: service, id: "main-repo", name: "Main Repo", repoPath: repo.path)
    _ = try await createProject(service: service, id: "worktree-repo", name: "Feature Child", repoPath: worktree.path)

    let summaries = await service.listProjectSummaries()
    let parent = try #require(summaries.first { $0.id == "main-repo" })
    let child = try #require(summaries.first { $0.id == "worktree-repo" })

    #expect(parent.isWorktree == false)
    #expect(parent.parentProjectId == nil)
    #expect(child.isWorktree == true)
    #expect(child.parentProjectId == "main-repo")
    #expect(child.worktreeBranch == "feature/child")
}

@Test
func projectSummariesAnnotateFallbackWorktreeParent() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let repo = try makeWorktreeMetadataTempDirectory(prefix: "project-worktree-fallback")
    defer { try? FileManager.default.removeItem(at: repo) }

    let worktree = repo
        .appendingPathComponent(".sloppy-worktrees", isDirectory: true)
        .appendingPathComponent("branch-a", isDirectory: true)
    try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)

    _ = try await createProject(service: service, id: "fallback-main", name: "Fallback Main", repoPath: repo.path)
    _ = try await createProject(service: service, id: "fallback-child", name: "Fallback Child", repoPath: worktree.path)

    let summaries = await service.listProjectSummaries()
    let parent = try #require(summaries.first { $0.id == "fallback-main" })
    let child = try #require(summaries.first { $0.id == "fallback-child" })

    #expect(parent.isWorktree == false)
    #expect(child.isWorktree == true)
    #expect(child.parentProjectId == "fallback-main")
    #expect(child.worktreeBranch == "branch-a")
}

@Test
func projectSummariesLeaveRegularProjectsTopLevel() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let repo = try makeWorktreeMetadataTempDirectory(prefix: "project-worktree-regular")
    defer { try? FileManager.default.removeItem(at: repo) }

    _ = try await createProject(service: service, id: "regular-project", name: "Regular Project", repoPath: repo.path)

    let summaries = await service.listProjectSummaries()
    let project = try #require(summaries.first { $0.id == "regular-project" })

    #expect(project.isWorktree == false)
    #expect(project.parentProjectId == nil)
    #expect(project.worktreeBranch == nil)
}

#if !os(Windows)
@Test(.timeLimit(.minutes(2)))
func projectListsBoundStalledGitMetadataWithoutBlockingOtherRequests() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let repo = try makeWorktreeMetadataTempDirectory(prefix: "project-worktree-stalled")
    defer { try? FileManager.default.removeItem(at: repo) }
    try runGit(["init"], in: repo)
    _ = try await createProject(service: service, id: "stalled-git", name: "Stalled Git", repoPath: repo.path)

    // Git blocks reading an included config until a writer closes the FIFO.
    let fifo = repo.appendingPathComponent("blocked-config")
    try #require(mkfifo(fifo.path, 0o600) == 0)
    let descriptor = open(fifo.path, O_RDWR | O_NONBLOCK)
    try #require(descriptor >= 0)
    let writer = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer { try? writer.close() }
    try "[include]\n    path = \(fifo.path)\n".write(
        to: repo.appendingPathComponent(".git/config"), atomically: true, encoding: .utf8
    )

    // Keep a regression bounded even if process timeouts are accidentally removed.
    let watchdog = DispatchWorkItem {
        try? FileManager.default.removeItem(at: fifo)
        try? writer.close()
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: watchdog)
    defer { watchdog.cancel() }

    await withTaskGroup(of: [ProjectRecord].self) { group in
        for _ in 0..<16 {
            group.addTask { await service.listProjects() }
        }
        let project = try? await service.getProject(id: "stalled-git")
        #expect(project?.id == "stalled-git")
        for await projects in group {
            #expect(projects.contains { $0.id == "stalled-git" })
        }
    }
    #expect(FileManager.default.fileExists(atPath: fifo.path))
}
#endif
