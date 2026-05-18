import Foundation
import Protocols

public enum SourceControlCapability: String, Codable, Sendable, Hashable {
    case inspectRepository = "inspect_repository"
    case workingTreeStatus = "working_tree_status"
    case workingTreeDiff = "working_tree_diff"
    case branchDiff = "branch_diff"
    case worktrees
    case restore
    case merge
}

public enum SourceControlProviderError: Error, LocalizedError, Sendable {
    case unsupportedOperation(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedOperation(let operation):
            return "Source control provider does not support \(operation)."
        }
    }
}

public protocol SourceControlProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var capabilities: Set<SourceControlCapability> { get }

    func inspectRepository(at path: String) async -> SourceControlRepositoryInfo
    func workingTreeStatus(at path: String) async throws -> SourceControlWorkingTreeStatus
    func workingTreeDiff(at path: String, maxBytes: Int) async throws -> SourceControlDiffResult
    func branchDiff(at path: String, branchName: String, baseBranch: String, maxBytes: Int) async throws -> SourceControlDiffResult
    func currentBranch(at path: String) async throws -> String?
    func defaultBranch(at path: String) async throws -> String
    func createWorktree(repoPath: String, taskId: String, baseBranch: String) async throws -> SourceControlWorktreeResult
    func removeWorktree(repoPath: String, worktreePath: String) async throws
    func worktreePath(repoPath: String, taskId: String) -> String
    func restorePathFromHead(repoPath: String, relativePath: String) async throws
    func mergeBranch(repoPath: String, branchName: String, targetBranch: String) async throws
}

public extension SourceControlProvider {
    var displayName: String { id }
    var capabilities: Set<SourceControlCapability> { [] }

    func inspectRepository(at path: String) async -> SourceControlRepositoryInfo {
        SourceControlRepositoryInfo(
            providerId: id,
            isRepository: false,
            rootPath: path,
            message: "Repository inspection is not supported."
        )
    }

    func workingTreeStatus(at path: String) async throws -> SourceControlWorkingTreeStatus {
        throw SourceControlProviderError.unsupportedOperation("working tree status")
    }

    func workingTreeDiff(at path: String, maxBytes: Int) async throws -> SourceControlDiffResult {
        throw SourceControlProviderError.unsupportedOperation("working tree diff")
    }

    func branchDiff(at path: String, branchName: String, baseBranch: String, maxBytes: Int) async throws -> SourceControlDiffResult {
        throw SourceControlProviderError.unsupportedOperation("branch diff")
    }

    func currentBranch(at path: String) async throws -> String? {
        throw SourceControlProviderError.unsupportedOperation("current branch")
    }

    func defaultBranch(at path: String) async throws -> String {
        throw SourceControlProviderError.unsupportedOperation("default branch")
    }

    func createWorktree(repoPath: String, taskId: String, baseBranch: String = "HEAD") async throws -> SourceControlWorktreeResult {
        throw SourceControlProviderError.unsupportedOperation("create worktree")
    }

    func removeWorktree(repoPath: String, worktreePath: String) async throws {
        throw SourceControlProviderError.unsupportedOperation("remove worktree")
    }

    func worktreePath(repoPath: String, taskId: String) -> String {
        URL(fileURLWithPath: repoPath)
            .appendingPathComponent(".sloppy-worktrees", isDirectory: true)
            .appendingPathComponent(taskId, isDirectory: true)
            .path
    }

    func restorePathFromHead(repoPath: String, relativePath: String) async throws {
        throw SourceControlProviderError.unsupportedOperation("restore")
    }

    func mergeBranch(repoPath: String, branchName: String, targetBranch: String) async throws {
        throw SourceControlProviderError.unsupportedOperation("merge")
    }
}
