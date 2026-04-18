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

    /// True when `.git` exists under `repoPath` (normal clone or worktree checkout).
    func isGitWorkingCopy(repoPath: String) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: URL(fileURLWithPath: repoPath).appendingPathComponent(".git").path)
    }

    /// Added/deleted line counts for the working tree vs `HEAD`, or all uncommitted changes when there is no commit yet.
    func workingTreeLineStats(repoPath: String) async throws -> (linesAdded: Int, linesDeleted: Int) {
        let hasHead = await hasHeadCommit(repoPath: repoPath)
        if hasHead {
            let (_, out) = try await runGit(args: ["diff", "HEAD", "--numstat"], cwd: repoPath)
            return Self.accumulateNumstat(out)
        }
        let (_, unstaged) = try await runGit(args: ["diff", "--numstat"], cwd: repoPath)
        let (_, staged) = try await runGit(args: ["diff", "--cached", "--numstat"], cwd: repoPath)
        let a = Self.accumulateNumstat(unstaged)
        let b = Self.accumulateNumstat(staged)
        return (a.linesAdded + b.linesAdded, a.linesDeleted + b.linesDeleted)
    }

    /// Unified diff text for the working tree (same scope as ``workingTreeLineStats``).
    func workingTreePatch(repoPath: String, maxBytes: Int) async throws -> (text: String, truncated: Bool) {
        let hasHead = await hasHeadCommit(repoPath: repoPath)
        let raw: String
        if hasHead {
            let (_, out) = try await runGit(args: ["diff", "HEAD"], cwd: repoPath)
            raw = out
        } else {
            let (_, unstaged) = try await runGit(args: ["diff"], cwd: repoPath)
            let (_, staged) = try await runGit(args: ["diff", "--cached"], cwd: repoPath)
            let parts = [unstaged, staged].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            raw = parts.joined(separator: "\n\n")
        }
        return Self.truncateUTF8(raw, maxBytes: maxBytes)
    }

    /// Restores a tracked path to the committed version at `HEAD` (staged + working tree).
    func restorePathFromHead(repoPath: String, relativePath: String) async throws {
        let (exitCode, output) = try await runGit(
            args: ["restore", "--source=HEAD", "--staged", "--worktree", "--", relativePath],
            cwd: repoPath
        )
        guard exitCode == 0 else {
            throw GitWorktreeError.commandFailed(exitCode, output)
        }
    }

    /// Current branch name, or nil if detached / unknown.
    func currentBranchLabel(repoPath: String) async throws -> String? {
        let (code, out) = try await runGit(args: ["branch", "--show-current"], cwd: repoPath)
        if code == 0 {
            let s = out.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { return s }
        }
        let (c2, o2) = try await runGit(args: ["rev-parse", "--abbrev-ref", "HEAD"], cwd: repoPath)
        guard c2 == 0 else { return nil }
        let ref = o2.trimmingCharacters(in: .whitespacesAndNewlines)
        if ref.isEmpty || ref == "HEAD" { return nil }
        return ref
    }

    private func hasHeadCommit(repoPath: String) async -> Bool {
        guard let (code, _) = try? await runGit(args: ["rev-parse", "--verify", "HEAD"], cwd: repoPath) else {
            return false
        }
        return code == 0
    }

    private static func accumulateNumstat(_ text: String) -> (linesAdded: Int, linesDeleted: Int) {
        var add = 0
        var del = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) where !line.isEmpty {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }
            let a = String(parts[0])
            let d = String(parts[1])
            if a == "-" || d == "-" { continue }
            if let ai = Int(a), let di = Int(d) {
                add += ai
                del += di
            }
        }
        return (add, del)
    }

    private static func truncateUTF8(_ string: String, maxBytes: Int) -> (String, Bool) {
        guard maxBytes > 0 else { return ("", string.isEmpty ? false : true) }
        var total = 0
        var result = ""
        result.reserveCapacity(min(string.count, maxBytes))
        for ch in string {
            let seg = String(ch)
            let n = seg.utf8.count
            if total + n > maxBytes {
                let note = "\n\n…(diff truncated by server)"
                let noteBytes = note.utf8.count
                if total + noteBytes > maxBytes {
                    return (result + String(note.prefix(max(0, maxBytes - total))), true)
                }
                return (result + note, true)
            }
            result.append(ch)
            total += n
        }
        return (result, false)
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
            process.environment = childProcessEnvironment()

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
