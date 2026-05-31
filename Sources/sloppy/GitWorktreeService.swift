import Foundation
import Protocols

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

    /// Creates a git worktree for a task at `<worktreeRootPath>/<taskId>/`.
    /// and checks out a new branch `sloppy/task-<shortId>`.
    func createWorktree(
        repoPath: String,
        taskId: String,
        baseBranch: String = "HEAD",
        worktreeRootPath: String? = nil
    ) async throws -> GitWorktreeResult {
        // Use a local FileManager so the service itself remains Sendable.
        let fileManager = FileManager.default
        let repoURL = URL(fileURLWithPath: repoPath)
        guard fileManager.fileExists(atPath: repoURL.appendingPathComponent(".git").path) ||
              (try? isWorktreeRoot(repoPath: repoPath)) == true else {
            throw GitWorktreeError.notAGitRepository(repoPath)
        }

        let shortId = String(taskId.prefix(8)).lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "-", options: .regularExpression)
        let branchBaseName = "sloppy/task-\(shortId)"
        let worktreesDir = worktreeRootURL(repoPath: repoPath, worktreeRootPath: worktreeRootPath)
        guard repoURL.standardizedFileURL.path != worktreesDir.standardizedFileURL.path else {
            throw GitWorktreeError.invalidPath
        }
        let worktreePath = worktreesDir.appendingPathComponent(taskId, isDirectory: true).path

        if fileManager.fileExists(atPath: worktreePath) {
            throw GitWorktreeError.worktreeAlreadyExists(worktreePath)
        }

        try fileManager.createDirectory(at: worktreesDir, withIntermediateDirectories: true)

        for attempt in 1...100 {
            let branchName = attempt == 1 ? branchBaseName : "\(branchBaseName)-\(attempt)"
            if try await branchExists(repoPath: repoPath, branchName: branchName) {
                continue
            }

            let (exitCode, output) = try await runGit(
                args: ["worktree", "add", "-b", branchName, worktreePath, baseBranch],
                cwd: repoPath
            )
            guard exitCode == 0 else {
                throw GitWorktreeError.worktreeCreationFailed(output)
            }

            return GitWorktreeResult(worktreePath: worktreePath, branchName: branchName)
        }

        throw GitWorktreeError.worktreeCreationFailed("Could not find an available branch name for \(branchBaseName)")
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
    func worktreePath(repoPath: String, taskId: String, worktreeRootPath: String? = nil) -> String {
        worktreeRootURL(repoPath: repoPath, worktreeRootPath: worktreeRootPath)
            .appendingPathComponent(taskId, isDirectory: true)
            .path
    }

    private func worktreeRootURL(repoPath: String, worktreeRootPath: String?) -> URL {
        if let worktreeRootPath {
            let trimmed = worktreeRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return URL(fileURLWithPath: trimmed, isDirectory: true)
            }
        }
        return URL(fileURLWithPath: repoPath)
            .appendingPathComponent(".sloppy-worktrees", isDirectory: true)
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

    func repositoryInfo(providerId: String, repoPath: String) async -> SourceControlRepositoryInfo {
        guard isGitWorkingCopy(repoPath: repoPath) else {
            return SourceControlRepositoryInfo(
                providerId: providerId,
                isRepository: false,
                rootPath: repoPath,
                message: "This project folder is not a git repository."
            )
        }

        let branch = try? await currentBranchLabel(repoPath: repoPath)
        let head: String?
        if let (code, output) = try? await runGit(args: ["rev-parse", "HEAD"], cwd: repoPath), code == 0 {
            head = output.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            head = nil
        }

        return SourceControlRepositoryInfo(
            providerId: providerId,
            isRepository: true,
            rootPath: repoPath,
            branch: branch,
            head: head
        )
    }

    func workingTreeStatus(providerId: String, repoPath: String) async throws -> SourceControlWorkingTreeStatus {
        let repository = await repositoryInfo(providerId: providerId, repoPath: repoPath)
        guard repository.isRepository else {
            return SourceControlWorkingTreeStatus(repository: repository)
        }

        let hasHead = await hasHeadCommit(repoPath: repoPath)
        let statsText: String
        if hasHead {
            let (_, out) = try await runGit(args: ["diff", "HEAD", "--numstat"], cwd: repoPath)
            statsText = out
        } else {
            let (_, unstaged) = try await runGit(args: ["diff", "--numstat"], cwd: repoPath)
            let (_, staged) = try await runGit(args: ["diff", "--cached", "--numstat"], cwd: repoPath)
            statsText = [unstaged, staged].joined(separator: "\n")
        }

        let totals = Self.accumulateNumstat(statsText)
        let statsByPath = Self.numstatByPath(statsText)
        let (_, statusText) = try await runGit(args: ["status", "--porcelain=v1"], cwd: repoPath)
        let files = Self.mergeStatus(statusText, statsByPath: statsByPath)

        return SourceControlWorkingTreeStatus(
            repository: repository,
            files: files,
            linesAdded: totals.linesAdded,
            linesDeleted: totals.linesDeleted
        )
    }

    func workingTreeDiffResult(providerId: String, repoPath: String, maxBytes: Int) async throws -> SourceControlDiffResult {
        let patch = try await workingTreePatch(repoPath: repoPath, maxBytes: maxBytes)
        let status = try? await workingTreeStatus(providerId: providerId, repoPath: repoPath)
        return SourceControlDiffResult(
            providerId: providerId,
            baseRef: "HEAD",
            headRef: status?.repository.branch,
            text: patch.text,
            truncated: patch.truncated,
            files: status?.files ?? []
        )
    }

    func branchDiffResult(
        providerId: String,
        repoPath: String,
        branchName: String,
        baseBranch: String,
        maxBytes: Int
    ) async throws -> SourceControlDiffResult {
        let (exitCode, output) = try await runGit(
            args: ["diff", "\(baseBranch)...\(branchName)", "--stat", "--patch"],
            cwd: repoPath
        )
        guard exitCode == 0 else {
            throw GitWorktreeError.commandFailed(exitCode, output)
        }
        let truncated = Self.truncateUTF8(output, maxBytes: maxBytes)
        return SourceControlDiffResult(
            providerId: providerId,
            baseRef: baseBranch,
            headRef: branchName,
            text: truncated.0,
            truncated: truncated.1
        )
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

    private static func numstatByPath(_ text: String) -> [String: (linesAdded: Int, linesDeleted: Int)] {
        var stats: [String: (linesAdded: Int, linesDeleted: Int)] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) where !line.isEmpty {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }
            let added = String(parts[0])
            let deleted = String(parts[1])
            guard added != "-", deleted != "-", let addedCount = Int(added), let deletedCount = Int(deleted) else {
                continue
            }
            let path = String(parts.last ?? "")
            guard !path.isEmpty else { continue }
            let current = stats[path] ?? (0, 0)
            stats[path] = (current.linesAdded + addedCount, current.linesDeleted + deletedCount)
        }
        return stats
    }

    private static func mergeStatus(
        _ text: String,
        statsByPath: [String: (linesAdded: Int, linesDeleted: Int)]
    ) -> [SourceControlFileChange] {
        var changes: [String: SourceControlFileChange] = [:]

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) where line.count >= 3 {
            let raw = String(line)
            let x = raw[raw.startIndex]
            let y = raw[raw.index(after: raw.startIndex)]
            var path = String(raw.dropFirst(3))
            var oldPath: String?
            if let range = path.range(of: " -> ") {
                oldPath = String(path[..<range.lowerBound])
                path = String(path[range.upperBound...])
            }

            let stats = statsByPath[path] ?? (0, 0)
            changes[path] = SourceControlFileChange(
                path: path,
                oldPath: oldPath,
                kind: changeKind(indexStatus: x, worktreeStatus: y),
                staged: x != " " && x != "?" && x != "!",
                unstaged: y != " " && y != "!",
                linesAdded: stats.linesAdded,
                linesDeleted: stats.linesDeleted
            )
        }

        for (path, stats) in statsByPath where changes[path] == nil {
            changes[path] = SourceControlFileChange(
                path: path,
                kind: .modified,
                staged: true,
                unstaged: true,
                linesAdded: stats.linesAdded,
                linesDeleted: stats.linesDeleted
            )
        }

        return changes.values.sorted { $0.path < $1.path }
    }

    private static func changeKind(indexStatus: Character, worktreeStatus: Character) -> SourceControlChangeKind {
        if indexStatus == "?" && worktreeStatus == "?" { return .untracked }
        if indexStatus == "!" && worktreeStatus == "!" { return .ignored }
        if indexStatus == "U" || worktreeStatus == "U" { return .conflicted }
        let status = indexStatus != " " ? indexStatus : worktreeStatus
        switch status {
        case "A": return .added
        case "M": return .modified
        case "D": return .deleted
        case "R": return .renamed
        case "C": return .copied
        case "T": return .typeChanged
        default: return .unknown
        }
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

    private func branchExists(repoPath: String, branchName: String) async throws -> Bool {
        let (exitCode, _) = try await runGit(
            args: ["show-ref", "--verify", "--quiet", "refs/heads/\(branchName)"],
            cwd: repoPath
        )
        return exitCode == 0
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
