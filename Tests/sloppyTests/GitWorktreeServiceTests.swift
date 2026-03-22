import Foundation
import Testing
@testable import sloppy

private func makeGitRepo() throws -> URL {
    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-worktree-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

    func git(_ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = tmpDir
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "git", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: out])
        }
    }

    try git(["init", "--initial-branch=main"])
    try git(["config", "user.email", "test@sloppy.dev"])
    try git(["config", "user.name", "SloppyTest"])
    let readme = tmpDir.appendingPathComponent("README.md")
    try "# Test".write(to: readme, atomically: true, encoding: .utf8)
    try git(["add", "."])
    try git(["commit", "-m", "Initial commit"])
    return tmpDir
}

@Test
func gitWorktreeCreateAndRemove() async throws {
    let repoURL = try makeGitRepo()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    let service = GitWorktreeService()
    let taskId = "task-test-\(UUID().uuidString)"
    let result = try await service.createWorktree(repoPath: repoURL.path, taskId: taskId)

    #expect(result.branchName.hasPrefix("sloppy/task-"))
    #expect(FileManager.default.fileExists(atPath: result.worktreePath))

    try await service.removeWorktree(repoPath: repoURL.path, worktreePath: result.worktreePath)
    #expect(!FileManager.default.fileExists(atPath: result.worktreePath))
}

@Test
func gitWorktreePathIsConsistent() async throws {
    let repoURL = try makeGitRepo()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    let service = GitWorktreeService()
    let taskId = "task-123"
    let expectedPath = repoURL.appendingPathComponent(".sloppy-worktrees/task-123").path
    let computedPath = service.worktreePath(repoPath: repoURL.path, taskId: taskId)
    #expect(computedPath == expectedPath)
}

@Test
func gitWorktreeBranchDiff() async throws {
    let repoURL = try makeGitRepo()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    let service = GitWorktreeService()
    let taskId = "task-diff-\(UUID().uuidString)"
    let result = try await service.createWorktree(repoPath: repoURL.path, taskId: taskId)

    let newFile = URL(fileURLWithPath: result.worktreePath).appendingPathComponent("feature.txt")
    try "new content".write(to: newFile, atomically: true, encoding: .utf8)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["add", ".", "--", "-e"]
    process.currentDirectoryURL = URL(fileURLWithPath: result.worktreePath)
    let p2 = Process()
    p2.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    p2.arguments = ["add", "."]
    p2.currentDirectoryURL = URL(fileURLWithPath: result.worktreePath)
    try p2.run(); p2.waitUntilExit()

    let p3 = Process()
    p3.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    p3.arguments = ["commit", "-m", "Add feature"]
    p3.currentDirectoryURL = URL(fileURLWithPath: result.worktreePath)
    p3.environment = ["GIT_AUTHOR_EMAIL": "test@sloppy.dev", "GIT_AUTHOR_NAME": "Test",
                      "GIT_COMMITTER_EMAIL": "test@sloppy.dev", "GIT_COMMITTER_NAME": "Test"]
    try p3.run(); p3.waitUntilExit()

    let diff = try await service.branchDiff(repoPath: repoURL.path, branchName: result.branchName, baseBranch: "main")
    #expect(!diff.isEmpty)
    #expect(diff.contains("feature.txt"))

    try await service.removeWorktree(repoPath: repoURL.path, worktreePath: result.worktreePath)
}

@Test
func gitWorktreeDefaultBranch() async throws {
    let repoURL = try makeGitRepo()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    let service = GitWorktreeService()
    let branch = try await service.defaultBranch(repoPath: repoURL.path)
    #expect(branch == "main")
}

@Test
func gitWorktreeErrorOnNonRepo() async throws {
    let service = GitWorktreeService()
    let fakePath = FileManager.default.temporaryDirectory
        .appendingPathComponent("not-a-repo-\(UUID().uuidString)").path
    try FileManager.default.createDirectory(atPath: fakePath, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: fakePath) }

    do {
        _ = try await service.createWorktree(repoPath: fakePath, taskId: "task-1")
        Issue.record("Expected error for non-repo path")
    } catch is GitWorktreeError {
        // expected
    }
}
