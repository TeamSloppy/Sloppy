import Foundation
import Protocols
import PluginSDK

struct GitCLISourceControlProvider: SourceControlProvider {
    let id = "git-cli"
    let displayName = "Git CLI"
    let capabilities: Set<SourceControlCapability> = [
        .inspectRepository,
        .workingTreeStatus,
        .workingTreeDiff,
        .branchDiff,
        .worktrees,
        .restore,
        .merge
    ]

    private let service: GitWorktreeService

    init(service: GitWorktreeService = GitWorktreeService()) {
        self.service = service
    }

    func inspectRepository(at path: String) async -> SourceControlRepositoryInfo {
        await service.repositoryInfo(providerId: id, repoPath: path)
    }

    func workingTreeStatus(at path: String) async throws -> SourceControlWorkingTreeStatus {
        try await service.workingTreeStatus(providerId: id, repoPath: path)
    }

    func workingTreeDiff(at path: String, maxBytes: Int) async throws -> SourceControlDiffResult {
        try await service.workingTreeDiffResult(providerId: id, repoPath: path, maxBytes: maxBytes)
    }

    func branchDiff(at path: String, branchName: String, baseBranch: String, maxBytes: Int) async throws -> SourceControlDiffResult {
        try await service.branchDiffResult(
            providerId: id,
            repoPath: path,
            branchName: branchName,
            baseBranch: baseBranch,
            maxBytes: maxBytes
        )
    }

    func currentBranch(at path: String) async throws -> String? {
        try await service.currentBranchLabel(repoPath: path)
    }

    func defaultBranch(at path: String) async throws -> String {
        try await service.defaultBranch(repoPath: path)
    }

    func createWorktree(
        repoPath: String,
        taskId: String,
        baseBranch: String,
        worktreeRootPath: String?
    ) async throws -> SourceControlWorktreeResult {
        let result = try await service.createWorktree(
            repoPath: repoPath,
            taskId: taskId,
            baseBranch: baseBranch,
            worktreeRootPath: worktreeRootPath
        )
        return SourceControlWorktreeResult(worktreePath: result.worktreePath, branchName: result.branchName)
    }

    func removeWorktree(repoPath: String, worktreePath: String) async throws {
        try await service.removeWorktree(repoPath: repoPath, worktreePath: worktreePath)
    }

    func worktreePath(repoPath: String, taskId: String, worktreeRootPath: String?) -> String {
        service.worktreePath(repoPath: repoPath, taskId: taskId, worktreeRootPath: worktreeRootPath)
    }

    func restorePathFromHead(repoPath: String, relativePath: String) async throws {
        try await service.restorePathFromHead(repoPath: repoPath, relativePath: relativePath)
    }

    func mergeBranch(repoPath: String, branchName: String, targetBranch: String) async throws {
        try await service.mergeBranch(repoPath: repoPath, branchName: branchName, targetBranch: targetBranch)
    }
}
