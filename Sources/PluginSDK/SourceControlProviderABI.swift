import Foundation
import Protocols

/// Wraps a source-control provider implementation for return through
/// `sloppy_source_control_create`.
///
/// Source plugins that declare `"protocol": "source_control"` in `plugin.json`
/// should export a C ABI entrypoint with this contract:
///
/// ```swift
/// @_cdecl("sloppy_source_control_create")
/// public func sloppy_source_control_create(
///     _ manifestJSON: UnsafePointer<CChar>
/// ) -> UnsafeMutableRawPointer?
/// ```
///
/// The returned pointer must be an `Unmanaged.passRetained(AnySourceControlProviderBox(...)).toOpaque()`.
public final class AnySourceControlProviderBox: SourceControlProvider, @unchecked Sendable {
    public let id: String
    public let displayName: String
    public let capabilities: Set<SourceControlCapability>

    private let _inspectRepository: @Sendable (String) async -> SourceControlRepositoryInfo
    private let _workingTreeStatus: @Sendable (String) async throws -> SourceControlWorkingTreeStatus
    private let _workingTreeDiff: @Sendable (String, Int) async throws -> SourceControlDiffResult
    private let _branchDiff: @Sendable (String, String, String, Int) async throws -> SourceControlDiffResult
    private let _currentBranch: @Sendable (String) async throws -> String?
    private let _defaultBranch: @Sendable (String) async throws -> String
    private let _createWorktree: @Sendable (String, String, String, String?) async throws -> SourceControlWorktreeResult
    private let _removeWorktree: @Sendable (String, String) async throws -> Void
    private let _worktreePath: @Sendable (String, String, String?) -> String
    private let _restorePathFromHead: @Sendable (String, String) async throws -> Void
    private let _mergeBranch: @Sendable (String, String, String) async throws -> Void

    public init(
        id: String,
        displayName: String? = nil,
        capabilities: Set<SourceControlCapability> = [],
        inspectRepository: @escaping @Sendable (String) async -> SourceControlRepositoryInfo,
        workingTreeStatus: @escaping @Sendable (String) async throws -> SourceControlWorkingTreeStatus,
        workingTreeDiff: @escaping @Sendable (String, Int) async throws -> SourceControlDiffResult,
        branchDiff: @escaping @Sendable (String, String, String, Int) async throws -> SourceControlDiffResult,
        currentBranch: @escaping @Sendable (String) async throws -> String?,
        defaultBranch: @escaping @Sendable (String) async throws -> String,
        createWorktree: @escaping @Sendable (String, String, String) async throws -> SourceControlWorktreeResult,
        removeWorktree: @escaping @Sendable (String, String) async throws -> Void,
        worktreePath: @escaping @Sendable (String, String) -> String,
        restorePathFromHead: @escaping @Sendable (String, String) async throws -> Void,
        mergeBranch: @escaping @Sendable (String, String, String) async throws -> Void
    ) {
        self.id = id
        self.displayName = displayName ?? id
        self.capabilities = capabilities
        self._inspectRepository = inspectRepository
        self._workingTreeStatus = workingTreeStatus
        self._workingTreeDiff = workingTreeDiff
        self._branchDiff = branchDiff
        self._currentBranch = currentBranch
        self._defaultBranch = defaultBranch
        self._createWorktree = { repoPath, taskId, baseBranch, _ in
            try await createWorktree(repoPath, taskId, baseBranch)
        }
        self._removeWorktree = removeWorktree
        self._worktreePath = { repoPath, taskId, _ in
            worktreePath(repoPath, taskId)
        }
        self._restorePathFromHead = restorePathFromHead
        self._mergeBranch = mergeBranch
    }

    public func inspectRepository(at path: String) async -> SourceControlRepositoryInfo {
        await _inspectRepository(path)
    }

    public func workingTreeStatus(at path: String) async throws -> SourceControlWorkingTreeStatus {
        try await _workingTreeStatus(path)
    }

    public func workingTreeDiff(at path: String, maxBytes: Int) async throws -> SourceControlDiffResult {
        try await _workingTreeDiff(path, maxBytes)
    }

    public func branchDiff(at path: String, branchName: String, baseBranch: String, maxBytes: Int) async throws -> SourceControlDiffResult {
        try await _branchDiff(path, branchName, baseBranch, maxBytes)
    }

    public func currentBranch(at path: String) async throws -> String? {
        try await _currentBranch(path)
    }

    public func defaultBranch(at path: String) async throws -> String {
        try await _defaultBranch(path)
    }

    public func createWorktree(
        repoPath: String,
        taskId: String,
        baseBranch: String,
        worktreeRootPath: String?
    ) async throws -> SourceControlWorktreeResult {
        try await _createWorktree(repoPath, taskId, baseBranch, worktreeRootPath)
    }

    public func removeWorktree(repoPath: String, worktreePath: String) async throws {
        try await _removeWorktree(repoPath, worktreePath)
    }

    public func worktreePath(repoPath: String, taskId: String, worktreeRootPath: String?) -> String {
        _worktreePath(repoPath, taskId, worktreeRootPath)
    }

    public func restorePathFromHead(repoPath: String, relativePath: String) async throws {
        try await _restorePathFromHead(repoPath, relativePath)
    }

    public func mergeBranch(repoPath: String, branchName: String, targetBranch: String) async throws {
        try await _mergeBranch(repoPath, branchName, targetBranch)
    }
}
