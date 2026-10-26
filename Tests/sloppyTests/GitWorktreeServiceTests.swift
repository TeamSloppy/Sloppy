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
        try waitForProcessExit(process, timeoutSeconds: 10, operation: "git \(args.joined(separator: " "))")
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
func gitWorktreeCreateUsesFallbackBranchNameWhenTaskBranchExists() async throws {
    let repoURL = try makeGitRepo()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    try runGit(["branch", "sloppy/task-adaengin"], in: repoURL)

    let service = GitWorktreeService()
    let result = try await service.createWorktree(repoPath: repoURL.path, taskId: "adaengine-fix")

    #expect(result.branchName == "sloppy/task-adaengin-2")
    #expect(FileManager.default.fileExists(atPath: result.worktreePath))

    try await service.removeWorktree(repoPath: repoURL.path, worktreePath: result.worktreePath)
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
func gitWorktreeUsesExplicitRootWhenProvided() async throws {
    let repoURL = try makeGitRepo()
    let worktreeRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-worktrees-root-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: repoURL)
        try? FileManager.default.removeItem(at: worktreeRoot)
    }

    let service = GitWorktreeService()
    let taskId = "task-custom-root"
    let result = try await service.createWorktree(
        repoPath: repoURL.path,
        taskId: taskId,
        worktreeRootPath: worktreeRoot.path
    )

    #expect(result.worktreePath == worktreeRoot.appendingPathComponent(taskId, isDirectory: true).path)
    #expect(FileManager.default.fileExists(atPath: result.worktreePath))

    try await service.removeWorktree(repoPath: repoURL.path, worktreePath: result.worktreePath)
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
    try p2.run()
    try waitForProcessExit(p2, timeoutSeconds: 10, operation: "git add .")

    let p3 = Process()
    p3.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    p3.arguments = ["commit", "-m", "Add feature"]
    p3.currentDirectoryURL = URL(fileURLWithPath: result.worktreePath)
    p3.environment = ["GIT_AUTHOR_EMAIL": "test@sloppy.dev", "GIT_AUTHOR_NAME": "Test",
                      "GIT_COMMITTER_EMAIL": "test@sloppy.dev", "GIT_COMMITTER_NAME": "Test"]
    let commitPipe = Pipe()
    p3.standardOutput = commitPipe
    p3.standardError = commitPipe
    try p3.run()
    try waitForProcessExit(p3, timeoutSeconds: 10, operation: "git commit -m Add feature")

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
func gitCLISourceControlProviderWorkingTreeStatusAndDiff() async throws {
    let repoURL = try makeGitRepo()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    let readme = repoURL.appendingPathComponent("README.md")
    try "# Test\n\nMore notes\n".write(to: readme, atomically: true, encoding: .utf8)
    try "scratch".write(to: repoURL.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

    let provider = GitCLISourceControlProvider()
    let repository = await provider.inspectRepository(at: repoURL.path)
    #expect(repository.providerId == "git-cli")
    #expect(repository.isRepository)
    #expect(repository.branch == "main")

    let status = try await provider.workingTreeStatus(at: repoURL.path)
    #expect(status.repository.isRepository)
    #expect(status.linesAdded >= 1)
    #expect(status.files.contains { $0.path == "README.md" && $0.kind == .modified && $0.unstaged })
    #expect(status.files.contains { $0.path == "notes.txt" && $0.kind == .untracked })

    let diff = try await provider.workingTreeDiff(at: repoURL.path, maxBytes: 512 * 1024)
    #expect(diff.providerId == "git-cli")
    #expect(diff.hasChanges)
    #expect(diff.text.contains("README.md"))
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

@Test(.timeLimit(.minutes(2)))
func gitWorktreeLargeDiffCompletesAndTruncatesConcurrentRequests() async throws {
    let repoURL = try makeGitRepo()
    defer { try? FileManager.default.removeItem(at: repoURL) }
    let content = String(repeating: "A changed line with enough text to fill the Git stdout pipe.\n", count: 20_000)
    try content.write(to: repoURL.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

    let service = GitWorktreeService()
    let complete = try await service.workingTreePatch(repoPath: repoURL.path, maxBytes: 2 * 1024 * 1024)
    #expect(!complete.truncated)
    #expect(complete.text.utf8.count > 1024 * 1024)
    #expect(complete.text.contains("+A changed line"))

    try await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0..<16 {
            group.addTask {
                let patch = try await service.workingTreePatch(repoPath: repoURL.path, maxBytes: 1024)
                #expect(patch.truncated)
                #expect(patch.text.contains("README.md"))
            }
        }
        try await group.waitForAll()
    }
}

#if !os(Windows)
@Test(.timeLimit(.minutes(2)))
func gitWorktreeDiffDrainsStandardOutputAndErrorConcurrently() async throws {
    let repoURL = try makeGitRepo()
    defer { try? FileManager.default.removeItem(at: repoURL) }
    try installExternalDiff(in: repoURL, body: """
    i=0
    while [ "$i" -lt 256 ]; do
        printf '%01024d\\n' 0
        printf '%01024d\\n' 0 >&2
        i=$((i + 1))
    done
    printf '\\nstdout-complete\\n'
    printf '\\nstderr-complete\\n' >&2
    """)

    let patch = try await GitWorktreeService().workingTreePatch(
        repoPath: repoURL.path,
        maxBytes: 2 * 1024 * 1024
    )
    #expect(!patch.truncated)
    #expect(patch.text.utf8.count > 512 * 1024)
    #expect(patch.text.contains("stdout-complete"))
    #expect(patch.text.contains("stderr-complete"))
}

@Test(.timeLimit(.minutes(2)))
func gitWorktreeDiffTimesOut() async throws {
    let repoURL = try makeGitRepo()
    defer { try? FileManager.default.removeItem(at: repoURL) }
    try installExternalDiff(in: repoURL, body: """
    parent=$PPID
    while kill -0 "$parent" 2>/dev/null; do
        /bin/sleep 0.05
    done
    """)

    do {
        _ = try await GitWorktreeService(commandTimeoutMs: 200).workingTreePatch(
            repoPath: repoURL.path,
            maxBytes: 1024
        )
        Issue.record("Expected the Git command to time out")
    } catch GitWorktreeError.commandTimedOut {
        // The runner must return even while the diff helper still holds its pipes open.
    }
}

@Test(.timeLimit(.minutes(2)))
func gitWorktreeDiffPropagatesCancellation() async throws {
    let repoURL = try makeGitRepo()
    defer { try? FileManager.default.removeItem(at: repoURL) }
    let startedURL = repoURL.appendingPathComponent("diff-started")
    try installExternalDiff(in: repoURL, body: """
    printf started > "\(startedURL.path)"
    parent=$PPID
    while kill -0 "$parent" 2>/dev/null; do
        /bin/sleep 0.05
    done
    """)

    let request = Task {
        try await GitWorktreeService().workingTreePatch(
            repoPath: repoURL.path,
            maxBytes: 1024
        )
    }
    defer { request.cancel() }
    let deadline = Date().addingTimeInterval(60)
    while !FileManager.default.fileExists(atPath: startedURL.path) && Date() < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(FileManager.default.fileExists(atPath: startedURL.path))
    request.cancel()
    do {
        _ = try await request.value
        Issue.record("Expected cancellation of the Git command")
    } catch is CancellationError {
        // Cancellation is preserved instead of becoming a Git timeout or launch error.
    }
}

private func installExternalDiff(in directory: URL, body: String) throws {
    let scriptURL = directory.appendingPathComponent("external-diff.sh")
    try ("#!/bin/sh\n" + body + "\n").write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    try runGit(["config", "diff.external", scriptURL.path], in: directory)
    try "Changed\n".write(to: directory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
}
#endif

private func runGit(_ args: [String], in directory: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = args
    process.currentDirectoryURL = directory
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    try waitForProcessExit(process, timeoutSeconds: 10, operation: "git \(args.joined(separator: " "))")
    guard process.terminationStatus == 0 else {
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        throw NSError(domain: "git", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: out])
    }
}

private func waitForProcessExit(
    _ process: Process,
    timeoutSeconds: TimeInterval,
    operation: String
) throws {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while process.isRunning && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.05)
    }

    if process.isRunning {
        process.terminate()
        throw NSError(
            domain: "GitWorktreeServiceTests.Timeout",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "\(operation) timed out after \(timeoutSeconds)s"]
        )
    }
}
