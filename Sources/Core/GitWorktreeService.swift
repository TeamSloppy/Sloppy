import Foundation

enum GitWorktreeError: Error, LocalizedError {
    case gitNotAvailable
    case notAGitRepository(String)
    case worktreeAlreadyExists(String)
    case worktreeCreationFailed(String)
    case mergeConflict(String)
    case commandFailed(Int32, String)
    case invalidPath

    var errorDescription: String? {
        switch self {
        case .gitNotAvailable:
            return "git is not available on the system"
        case .notAGitRepository(let path):
            return "Not a git repository: \(path)"
        case .worktreeAlreadyExists(let path):
            return "Worktree already exists at: \(path)"
        case .worktreeCreationFailed(let msg):
            return "Failed to create worktree: \(msg)"
        case .mergeConflict(let msg):
            return "Merge conflict: \(msg)"
        case .commandFailed(let code, let output):
            return "Git command failed (exit \(code)): \(output)"
        case .invalidPath:
            return "Invalid repository path"
        }
    }
}

struct GitWorktreeResult: Sendable {
    let worktreePath: String
    let branchName: String
}

// Keep the service stateless so CoreService can safely await its methods across
// actor boundaries. We still use FileManager.default, but only as a temporary
// local dependency inside each call instead of storing a shared reference.
struct GitWorktreeService: Sendable {

    /// Creates a git worktree for a task at `<repoPath>/.sloppy-worktrees/<taskId>/`
    /// and checks out a new branch `sloppy/task-<shortId>`.
    func createWorktree(repoPath: String, taskId: String, baseBranch: String = "HEAD") async throws -> GitWorktreeResult {
        // Use a local FileManager so the service itself remains Sendable.
        let fileManager = FileManager.default
        let repoURL = URL(fileURLWithPath: repoPath)
        guard fileManager.fileExists(atPath: repoURL.appendingPathComponent(".git").path) ||
              (try? isWorktreeRoot(repoPath: repoPath)) == true else {
            throw GitWorktreeError.notAGitRepository(repoPath)
        }

        let shortId = String(taskId.prefix(8)).lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "-", options: .regularExpression)
        let branchName = "sloppy/task-\(shortId)"
        let worktreesDir = repoURL.appendingPathComponent(".sloppy-worktrees", isDirectory: true)
        let worktreePath = worktreesDir.appendingPathComponent(taskId, isDirectory: true).path

        if fileManager.fileExists(atPath: worktreePath) {
            throw GitWorktreeError.worktreeAlreadyExists(worktreePath)
        }

        try fileManager.createDirectory(at: worktreesDir, withIntermediateDirectories: true)

        let (exitCode, output) = try await runGit(
            args: ["worktree", "add", "-b", branchName, worktreePath, baseBranch],
            cwd: repoPath
        )
        guard exitCode == 0 else {
            throw GitWorktreeError.worktreeCreationFailed(output)
        }

        return GitWorktreeResult(worktreePath: worktreePath, branchName: branchName)
    }

    /// Removes a git worktree and its directory.
    func removeWorktree(repoPath: String, worktreePath: String) async throws {
        // Use a local FileManager so the service itself remains Sendable.
        let fileManager = FileManager.default
        let (exitCode, output) = try await runGit(
            args: ["worktree", "remove", "--force", worktreePath],
            cwd: repoPath
        )
        guard exitCode == 0 else {
            throw GitWorktreeError.commandFailed(exitCode, output)
        }

        if fileManager.fileExists(atPath: worktreePath) {
            try? fileManager.removeItem(atPath: worktreePath)
        }
    }

    /// Merges a task branch into the target branch (default: current HEAD branch).
    func mergeBranch(repoPath: String, branchName: String, targetBranch: String) async throws {
        let (checkoutCode, checkoutOut) = try await runGit(
            args: ["checkout", targetBranch],
            cwd: repoPath
        )
        guard checkoutCode == 0 else {
            throw GitWorktreeError.commandFailed(checkoutCode, checkoutOut)
        }

        let (mergeCode, mergeOut) = try await runGit(
            args: ["merge", "--no-ff", branchName, "-m", "Merge task branch \(branchName)"],
            cwd: repoPath
        )
        guard mergeCode == 0 else {
            if mergeOut.contains("CONFLICT") {
                throw GitWorktreeError.mergeConflict(mergeOut)
            }
            throw GitWorktreeError.commandFailed(mergeCode, mergeOut)
        }
    }

    /// Returns the diff between the task branch and its base.
    func branchDiff(repoPath: String, branchName: String, baseBranch: String) async throws -> String {
        let (exitCode, output) = try await runGit(
            args: ["diff", "\(baseBranch)...\(branchName)", "--stat", "--patch"],
            cwd: repoPath
        )
        guard exitCode == 0 else {
            throw GitWorktreeError.commandFailed(exitCode, output)
        }
        return output
    }

    /// Returns the current default branch name (e.g. "main" or "master").
    func defaultBranch(repoPath: String) async throws -> String {
        let (exitCode, output) = try await runGit(
            args: ["symbolic-ref", "--short", "HEAD"],
            cwd: repoPath
        )
        guard exitCode == 0 else {
            return "main"
        }
        let branch = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return branch.isEmpty ? "main" : branch
    }

    /// Returns the worktree path for a task (whether it exists or not).
    func worktreePath(repoPath: String, taskId: String) -> String {
        URL(fileURLWithPath: repoPath)
            .appendingPathComponent(".sloppy-worktrees", isDirectory: true)
            .appendingPathComponent(taskId, isDirectory: true)
            .path
    }

    private func isWorktreeRoot(repoPath: String) throws -> Bool {
        // Use a local FileManager so the service itself remains Sendable.
        let fileManager = FileManager.default
        let gitFile = URL(fileURLWithPath: repoPath).appendingPathComponent(".git").path
        if fileManager.fileExists(atPath: gitFile) {
            return true
        }
        return false
    }

    @discardableResult
    private func runGit(args: [String], cwd: String) async throws -> (Int32, String) {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = args
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)

            let pipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errorPipe

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: GitWorktreeError.gitNotAvailable)
                return
            }

            process.waitUntilExit()

            let outData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let outStr = String(data: outData, encoding: .utf8) ?? ""
            let errStr = String(data: errData, encoding: .utf8) ?? ""
            let combined = [outStr, errStr].filter { !$0.isEmpty }.joined(separator: "\n")
            continuation.resume(returning: (process.terminationStatus, combined))
        }
    }
}
